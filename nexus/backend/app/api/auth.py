"""Auth API: tenant login, superadmin login, logout and current user."""
from __future__ import annotations

from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from pydantic import BaseModel
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..core.config import settings
from ..core.database import get_db
from ..core.security import decode_jwt, issue_jwt, verify_password
from ..models.tenant import DeploymentMode, Tenant
from ..models.user import User

router = APIRouter(prefix="/api/v1/auth", tags=["auth"])


class LoginRequest(BaseModel):
    username: str | None = None
    email: str | None = None
    password: str


class LoginResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    id: str
    username: str
    email: str
    full_name: str | None
    role: str
    is_admin: bool
    is_superadmin: bool
    user_id: str
    tenant_id: str
    tenant_subdomain: str
    tenant_name: str
    deployment_mode: str


class MeResponse(BaseModel):
    id: str
    username: str
    email: str
    full_name: str | None
    role: str
    is_admin: bool
    is_superadmin: bool
    tenant_id: str
    tenant_subdomain: str
    tenant_name: str
    deployment_mode: str


def _token_from_request(request: Request) -> str | None:
    auth = request.headers.get("authorization", "")
    if auth.lower().startswith("bearer "):
        return auth[7:].strip() or None
    if request.headers.get("x-eigenguard-auth-scope", "").lower() == "superadmin":
        return request.cookies.get("superadmin_access_token")
    return request.cookies.get("access_token")


def _requested_scope(request: Request) -> str:
    scope = request.headers.get("x-eigenguard-auth-scope", "").lower()
    return "superadmin" if scope == "superadmin" else "tenant"


def _serialize_user(user: User, tenant: Tenant) -> MeResponse:
    return MeResponse(
        id=str(user.id),
        username=user.username,
        email=user.email,
        full_name=user.full_name,
        role=user.role,
        is_admin=user.is_admin,
        is_superadmin=(
            tenant.deployment_mode == DeploymentMode.superadmin and user.is_admin
        ),
        tenant_id=str(tenant.id),
        tenant_subdomain=tenant.subdomain,
        tenant_name=tenant.name,
        deployment_mode=tenant.deployment_mode.value,
    )


def _serialize_login(user: User, tenant: Tenant, token: str) -> LoginResponse:
    current = _serialize_user(user, tenant)
    return LoginResponse(
        access_token=token,
        id=current.id,
        username=current.username,
        email=current.email,
        full_name=current.full_name,
        role=current.role,
        is_admin=current.is_admin,
        is_superadmin=current.is_superadmin,
        user_id=current.id,
        tenant_id=current.tenant_id,
        tenant_subdomain=current.tenant_subdomain,
        tenant_name=current.tenant_name,
        deployment_mode=current.deployment_mode,
    )


async def _authenticate(
    payload: LoginRequest,
    db: AsyncSession,
    *,
    require_superadmin: bool,
) -> tuple[User, Tenant]:
    credential = (payload.username or payload.email or "").strip().lower()
    if not credential:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Username is required")

    rows = (
        await db.execute(
            select(User, Tenant)
            .join(Tenant, Tenant.id == User.tenant_id)
            .where(
                or_(User.email == credential, User.username == credential),
                User.is_active.is_(True),
                Tenant.is_active.is_(True),
            )
        )
    ).all()

    matches: list[tuple[User, Tenant]] = [
        (user, tenant)
        for user, tenant in rows
        if verify_password(payload.password, user.password_hash)
    ]
    if require_superadmin:
        matches = [
            (user, tenant)
            for user, tenant in matches
            if tenant.deployment_mode == DeploymentMode.superadmin and user.is_admin
        ]
    else:
        matches = [
            (user, tenant)
            for user, tenant in matches
            if tenant.deployment_mode != DeploymentMode.superadmin
        ]

    if not matches:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid username or password")
    if len(matches) > 1:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            "Credential maps to multiple tenants; use a unique username/password pair",
        )
    return matches[0]


def _set_auth_cookie(response: Response, token: str, *, superadmin: bool) -> None:
    response.set_cookie(
        key="superadmin_access_token" if superadmin else "access_token",
        value=token,
        httponly=True,
        secure=settings.environment != "development",
        samesite="lax",
        max_age=settings.jwt_expire_minutes * 60,
        path="/",
    )


async def _issue_login(
    user: User,
    tenant: Tenant,
    response: Response,
    db: AsyncSession,
    *,
    superadmin: bool,
) -> LoginResponse:
    token = issue_jwt(user_id=user.id, tenant_id=user.tenant_id, is_admin=user.is_admin)
    user.last_login_at = datetime.now(timezone.utc)
    await db.commit()
    _set_auth_cookie(response, token, superadmin=superadmin)
    response.delete_cookie(
        "access_token" if superadmin else "superadmin_access_token",
        path="/",
    )
    return _serialize_login(user, tenant, token)


@router.post("/login", response_model=LoginResponse)
async def login(
    payload: LoginRequest,
    response: Response,
    db: AsyncSession = Depends(get_db),
):
    """Tenant user login only. Superadmin must use /superadmin/login."""
    user, tenant = await _authenticate(payload, db, require_superadmin=False)
    return await _issue_login(user, tenant, response, db, superadmin=False)


@router.post("/superadmin/login", response_model=LoginResponse)
async def superadmin_login(
    payload: LoginRequest,
    response: Response,
    db: AsyncSession = Depends(get_db),
):
    """Superadmin login only."""
    user, tenant = await _authenticate(payload, db, require_superadmin=True)
    return await _issue_login(user, tenant, response, db, superadmin=True)


@router.post("/logout")
async def logout(response: Response):
    response.delete_cookie("access_token", path="/")
    response.delete_cookie("superadmin_access_token", path="/")
    return {"status": "ok"}


@router.get("/me", response_model=MeResponse)
async def me(request: Request, db: AsyncSession = Depends(get_db)):
    requested_scope = _requested_scope(request)
    token = _token_from_request(request)
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated",
            headers={"WWW-Authenticate": "Bearer"},
        )

    payload = decode_jwt(token)
    if not payload:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid or expired token")
    try:
        user_id = UUID(payload["sub"])
        tenant_id = UUID(payload["tenant_id"])
    except (KeyError, ValueError):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Malformed token")

    row = (
        await db.execute(
            select(User, Tenant)
            .join(Tenant, Tenant.id == User.tenant_id)
            .where(
                User.id == user_id,
                User.tenant_id == tenant_id,
                User.is_active.is_(True),
                Tenant.is_active.is_(True),
            )
        )
    ).first()
    if row is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "User or tenant inactive")

    user, tenant = row
    is_superadmin = tenant.deployment_mode == DeploymentMode.superadmin and user.is_admin
    if requested_scope == "superadmin" and not is_superadmin:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Superadmin session required")
    if requested_scope == "tenant" and tenant.deployment_mode == DeploymentMode.superadmin:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Tenant session required")
    return _serialize_user(user, tenant)
