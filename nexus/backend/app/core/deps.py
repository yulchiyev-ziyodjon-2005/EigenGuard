"""FastAPI dependency injectors — DB session + current user."""
from __future__ import annotations

from uuid import UUID

from fastapi import Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..models.tenant import Tenant
from ..models.user import User, UserRole
from .database import get_db
from .security import decode_jwt


def _extract_token(request: Request) -> str | None:
    """JWT — `Authorization: Bearer <token>` header yoki `access_token` cookie."""
    auth = request.headers.get("authorization", "")
    if auth.lower().startswith("bearer "):
        return auth[7:].strip() or None
    if request.url.path.startswith("/api/v1/superadmin/"):
        return request.cookies.get("superadmin_access_token")
    return request.cookies.get("access_token")


async def get_current_user(
    request: Request,
    db: AsyncSession = Depends(get_db),
) -> User:
    """Returns the authenticated user, verifying they belong to the resolved tenant."""
    token = _extract_token(request)
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
        token_tenant_id = UUID(payload["tenant_id"])
    except (KeyError, ValueError):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Malformed token")

    # Tenant from middleware (set in request.state) — must match token's tenant_id
    tenant: Tenant | None = getattr(request.state, "tenant", None)
    if tenant is not None and tenant.id != token_tenant_id:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            "Token tenant does not match resolved tenant (cross-tenant access blocked)",
        )

    user = (await db.execute(select(User).where(User.id == user_id))).scalar_one_or_none()
    if user is None or not user.is_active:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "User not found or inactive")
    if user.tenant_id != token_tenant_id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "User-tenant mismatch")
    return user


async def get_admin_user(user: User = Depends(get_current_user)) -> User:
    if user.role not in (UserRole.superadmin.value, UserRole.tenant_admin.value) and not user.is_admin:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Admin privileges required")
    return user


async def require_superadmin(
    request: Request, user: User = Depends(get_current_user)
) -> User:
    """Tenant deployment_mode == superadmin AND user is admin."""
    tenant: Tenant | None = getattr(request.state, "tenant", None)
    from ..models.tenant import DeploymentMode  # local import to avoid cycle
    if (
        tenant is None
        or tenant.deployment_mode != DeploymentMode.superadmin
        or (
            user.role != UserRole.superadmin.value
            and not user.is_admin
        )
    ):
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, "Superadmin access required"
        )
    return user
