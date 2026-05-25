"""Tenant admin manages mobile users (xodimlar). Bir tenant ichida ishlaydi."""
from __future__ import annotations

from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..core.database import get_db
from ..core.deps import get_admin_user, get_current_user
from ..core.security import hash_password
from ..models.tenant import Tenant
from ..models.user import User, UserRole

router = APIRouter(prefix="/api/v1/users", tags=["users"])


class UserOut(BaseModel):
    id: str
    username: str
    email: str
    full_name: str | None
    role: str
    is_admin: bool
    is_active: bool
    created_at: datetime
    last_login_at: datetime | None


class UserCreate(BaseModel):
    username: str | None = Field(default=None, min_length=3, max_length=80)
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    full_name: str | None = None
    role: str = UserRole.engineer.value
    is_admin: bool = False


class UserPatch(BaseModel):
    full_name: str | None = None
    role: str | None = None
    is_admin: bool | None = None
    is_active: bool | None = None


class PasswordReset(BaseModel):
    new_password: str = Field(min_length=8, max_length=128)


def _ser(u: User) -> UserOut:
    return UserOut(
        id=str(u.id),
        username=u.username,
        email=u.email,
        full_name=u.full_name,
        role=u.role,
        is_admin=u.is_admin,
        is_active=u.is_active,
        created_at=u.created_at,
        last_login_at=u.last_login_at,
    )


def _normalize_username(value: str) -> str:
    username = value.strip().lower()
    if not username:
        raise HTTPException(422, "Username is required")
    allowed = set("abcdefghijklmnopqrstuvwxyz0123456789_-")
    if any(ch not in allowed for ch in username):
        raise HTTPException(
            422,
            "Username may contain only lowercase letters, numbers, underscore and dash",
        )
    return username


def _default_username(email: str) -> str:
    allowed = set("abcdefghijklmnopqrstuvwxyz0123456789_-")
    base = email.split("@", 1)[0].strip().lower()
    username = "".join(ch if ch in allowed else "-" for ch in base).strip("-_")
    return _normalize_username(username or "user")


def _normalize_role(value: str, *, is_admin: bool = False) -> str:
    if is_admin and value == UserRole.engineer.value:
        return UserRole.tenant_admin.value
    try:
        role = UserRole(value).value
    except ValueError:
        raise HTTPException(422, f"Invalid role: {value}")
    if role == UserRole.superadmin.value:
        raise HTTPException(403, "Superadmin role cannot be assigned inside a tenant")
    return role


def _is_admin_role(role: str) -> bool:
    return role in (UserRole.superadmin.value, UserRole.tenant_admin.value)


@router.get("", response_model=list[UserOut])
async def list_users(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
):
    tenant: Tenant = request.state.tenant
    rows = (
        await db.execute(
            select(User).where(User.tenant_id == tenant.id).order_by(User.created_at.desc())
        )
    ).scalars().all()
    return [_ser(u) for u in rows]


@router.post("", status_code=status.HTTP_201_CREATED, response_model=UserOut)
async def create_user(
    payload: UserCreate,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_admin_user),
):
    tenant: Tenant = request.state.tenant
    username = _normalize_username(payload.username or _default_username(payload.email))
    role = _normalize_role(payload.role, is_admin=payload.is_admin)
    existing = (
        await db.execute(
            select(User).where(
                User.tenant_id == tenant.id,
                (User.email == payload.email.lower()) | (User.username == username),
            )
        )
    ).scalar_one_or_none()
    if existing is not None:
        raise HTTPException(409, "Username or email already exists in this tenant")
    user = User(
        tenant_id=tenant.id,
        username=username,
        email=payload.email.lower(),
        password_hash=hash_password(payload.password),
        full_name=payload.full_name,
        role=role,
        is_admin=_is_admin_role(role),
        is_active=True,
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return _ser(user)


@router.patch("/{user_id}", response_model=UserOut)
async def update_user(
    user_id: UUID,
    payload: UserPatch,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_admin_user),
):
    tenant: Tenant = request.state.tenant
    user = (
        await db.execute(
            select(User).where(User.id == user_id, User.tenant_id == tenant.id)
        )
    ).scalar_one_or_none()
    if user is None:
        raise HTTPException(404, "User not found in this tenant")
    if payload.full_name is not None:
        user.full_name = payload.full_name
    if payload.role is not None:
        user.role = _normalize_role(payload.role)
        user.is_admin = _is_admin_role(user.role)
    if payload.is_admin is not None:
        user.is_admin = payload.is_admin
        if payload.is_admin and user.role not in (
            UserRole.superadmin.value,
            UserRole.tenant_admin.value,
        ):
            user.role = UserRole.tenant_admin.value
        if not payload.is_admin and user.role == UserRole.tenant_admin.value:
            user.role = UserRole.engineer.value
    if payload.is_active is not None:
        user.is_active = payload.is_active
    await db.commit()
    await db.refresh(user)
    return _ser(user)


@router.post("/{user_id}/reset-password", status_code=status.HTTP_204_NO_CONTENT)
async def reset_password(
    user_id: UUID,
    payload: PasswordReset,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_admin_user),
):
    tenant: Tenant = request.state.tenant
    user = (
        await db.execute(
            select(User).where(User.id == user_id, User.tenant_id == tenant.id)
        )
    ).scalar_one_or_none()
    if user is None:
        raise HTTPException(404, "User not found")
    user.password_hash = hash_password(payload.new_password)
    await db.commit()


@router.delete("/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_user(
    user_id: UUID,
    request: Request,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(get_admin_user),
):
    if user_id == admin.id:
        raise HTTPException(400, "Cannot delete yourself")
    tenant: Tenant = request.state.tenant
    user = (
        await db.execute(
            select(User).where(User.id == user_id, User.tenant_id == tenant.id)
        )
    ).scalar_one_or_none()
    if user is None:
        raise HTTPException(404, "User not found")
    await db.delete(user)
    await db.commit()
