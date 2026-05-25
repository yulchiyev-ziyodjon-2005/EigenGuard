"""Superadmin licenses CRUD — tenantlarga litsenziya berish/yangilash/bekor qilish."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from secrets import token_hex
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from pydantic import BaseModel, Field
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..core.audit import log_audit
from ..core.database import get_db
from ..core.deps import require_superadmin
from ..models.audit_log import AuditAction
from ..models.license import License
from ..models.tenant import Tenant
from ..models.user import User

router = APIRouter(
    prefix="/api/v1/superadmin/licenses",
    tags=["superadmin"],
    dependencies=[Depends(require_superadmin)],
)


class LicenseOut(BaseModel):
    id: str
    tenant_id: str
    tenant_subdomain: str | None
    tenant_name: str | None
    key: str
    issued_at: datetime
    expires_at: datetime
    max_devices: int
    max_users: int
    features: dict
    last_validated_at: datetime | None
    is_revoked: bool
    is_expired: bool
    is_valid: bool
    revocation_reason: str | None


class LicenseCreate(BaseModel):
    tenant_id: UUID
    duration_days: int = Field(365, ge=1, le=3650)
    max_devices: int = Field(10, ge=1, le=10000)
    max_users: int = Field(5, ge=1, le=10000)
    features: dict = Field(default_factory=dict)


class LicenseRenew(BaseModel):
    duration_days: int = Field(365, ge=1, le=3650)
    # If true: yangi muddat hozirgi vaqtdan boshlanadi
    # If false (default): mavjud expires_at ga qo'shiladi
    reset_from_now: bool = False


class LicensePatch(BaseModel):
    max_devices: int | None = Field(None, ge=1, le=10000)
    max_users: int | None = Field(None, ge=1, le=10000)
    features: dict | None = None


class LicenseRevoke(BaseModel):
    reason: str = Field(min_length=1, max_length=500)


def _ser(lic: License, tenant: Tenant | None = None) -> LicenseOut:
    return LicenseOut(
        id=str(lic.id),
        tenant_id=str(lic.tenant_id),
        tenant_subdomain=tenant.subdomain if tenant else None,
        tenant_name=tenant.name if tenant else None,
        key=lic.key,
        issued_at=lic.issued_at,
        expires_at=lic.expires_at,
        max_devices=lic.max_devices,
        max_users=lic.max_users,
        features=lic.features or {},
        last_validated_at=lic.last_validated_at,
        is_revoked=lic.is_revoked,
        is_expired=lic.is_expired,
        is_valid=lic.is_valid,
        revocation_reason=lic.revocation_reason,
    )


async def _get_tenant_map(
    db: AsyncSession, tenant_ids: set[UUID]
) -> dict[UUID, Tenant]:
    if not tenant_ids:
        return {}
    rows = (
        await db.execute(select(Tenant).where(Tenant.id.in_(tenant_ids)))
    ).scalars().all()
    return {t.id: t for t in rows}


@router.get("", response_model=list[LicenseOut])
async def list_licenses(
    db: AsyncSession = Depends(get_db),
    tenant_id: UUID | None = Query(None),
    only_active: bool = Query(False),
):
    q = select(License).order_by(desc(License.issued_at))
    if tenant_id is not None:
        q = q.where(License.tenant_id == tenant_id)
    if only_active:
        q = q.where(License.is_revoked.is_(False))
    rows = (await db.execute(q)).scalars().all()
    tenant_map = await _get_tenant_map(db, {r.tenant_id for r in rows})
    return [_ser(r, tenant_map.get(r.tenant_id)) for r in rows]


@router.post("", status_code=status.HTTP_201_CREATED, response_model=LicenseOut)
async def create_license(
    payload: LicenseCreate,
    request: Request,
    db: AsyncSession = Depends(get_db),
    actor: User = Depends(require_superadmin),
):
    tenant = (
        await db.execute(select(Tenant).where(Tenant.id == payload.tenant_id))
    ).scalar_one_or_none()
    if tenant is None:
        raise HTTPException(404, "Tenant not found")

    now = datetime.now(timezone.utc)
    lic = License(
        tenant_id=tenant.id,
        key=token_hex(32),  # 64 hex chars
        issued_at=now,
        expires_at=now + timedelta(days=payload.duration_days),
        max_devices=payload.max_devices,
        max_users=payload.max_users,
        features=payload.features,
    )
    db.add(lic)
    await db.flush()

    await log_audit(
        db=db,
        actor=actor,
        action=AuditAction.license_create,
        entity_type="license",
        entity_id=lic.id,
        target_tenant=tenant,
        payload={
            "after": {
                "duration_days": payload.duration_days,
                "max_devices": lic.max_devices,
                "max_users": lic.max_users,
                "features": lic.features,
                "expires_at": lic.expires_at.isoformat(),
            }
        },
        request=request,
    )
    await db.commit()
    await db.refresh(lic)
    return _ser(lic, tenant)


@router.patch("/{license_id}", response_model=LicenseOut)
async def update_license(
    license_id: UUID,
    payload: LicensePatch,
    request: Request,
    db: AsyncSession = Depends(get_db),
    actor: User = Depends(require_superadmin),
):
    lic = (
        await db.execute(select(License).where(License.id == license_id))
    ).scalar_one_or_none()
    if lic is None:
        raise HTTPException(404, "License not found")
    if lic.is_revoked:
        raise HTTPException(409, "License is revoked — cannot edit")
    before: dict = {}
    after: dict = {}
    if payload.max_devices is not None and payload.max_devices != lic.max_devices:
        before["max_devices"] = lic.max_devices
        after["max_devices"] = payload.max_devices
        lic.max_devices = payload.max_devices
    if payload.max_users is not None and payload.max_users != lic.max_users:
        before["max_users"] = lic.max_users
        after["max_users"] = payload.max_users
        lic.max_users = payload.max_users
    if payload.features is not None and payload.features != (lic.features or {}):
        before["features"] = lic.features or {}
        after["features"] = payload.features
        lic.features = payload.features

    tenant = (
        await db.execute(select(Tenant).where(Tenant.id == lic.tenant_id))
    ).scalar_one_or_none()
    if after:
        await log_audit(
            db=db,
            actor=actor,
            action=AuditAction.license_update,
            entity_type="license",
            entity_id=lic.id,
            target_tenant=tenant,
            payload={"before": before, "after": after},
            request=request,
        )
    await db.commit()
    await db.refresh(lic)
    return _ser(lic, tenant)


@router.post("/{license_id}/renew", response_model=LicenseOut)
async def renew_license(
    license_id: UUID,
    payload: LicenseRenew,
    request: Request,
    db: AsyncSession = Depends(get_db),
    actor: User = Depends(require_superadmin),
):
    lic = (
        await db.execute(select(License).where(License.id == license_id))
    ).scalar_one_or_none()
    if lic is None:
        raise HTTPException(404, "License not found")
    if lic.is_revoked:
        raise HTTPException(409, "License is revoked — issue a new one instead")
    now = datetime.now(timezone.utc)
    base = now if payload.reset_from_now or lic.expires_at < now else lic.expires_at
    before_expires = lic.expires_at
    lic.expires_at = base + timedelta(days=payload.duration_days)

    tenant = (
        await db.execute(select(Tenant).where(Tenant.id == lic.tenant_id))
    ).scalar_one_or_none()
    await log_audit(
        db=db,
        actor=actor,
        action=AuditAction.license_renew,
        entity_type="license",
        entity_id=lic.id,
        target_tenant=tenant,
        payload={
            "before": {"expires_at": before_expires.isoformat()},
            "after": {
                "expires_at": lic.expires_at.isoformat(),
                "duration_days": payload.duration_days,
                "reset_from_now": payload.reset_from_now,
            },
        },
        request=request,
    )
    await db.commit()
    await db.refresh(lic)
    return _ser(lic, tenant)


@router.post("/{license_id}/revoke", response_model=LicenseOut)
async def revoke_license(
    license_id: UUID,
    payload: LicenseRevoke,
    request: Request,
    db: AsyncSession = Depends(get_db),
    actor: User = Depends(require_superadmin),
):
    lic = (
        await db.execute(select(License).where(License.id == license_id))
    ).scalar_one_or_none()
    if lic is None:
        raise HTTPException(404, "License not found")
    if lic.is_revoked:
        raise HTTPException(409, "License already revoked")
    lic.is_revoked = True
    lic.revocation_reason = payload.reason

    tenant = (
        await db.execute(select(Tenant).where(Tenant.id == lic.tenant_id))
    ).scalar_one_or_none()
    await log_audit(
        db=db,
        actor=actor,
        action=AuditAction.license_revoke,
        entity_type="license",
        entity_id=lic.id,
        target_tenant=tenant,
        payload={"after": {"reason": payload.reason}},
        request=request,
    )
    await db.commit()
    await db.refresh(lic)
    return _ser(lic, tenant)


@router.delete("/{license_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_license(
    license_id: UUID,
    request: Request,
    db: AsyncSession = Depends(get_db),
    actor: User = Depends(require_superadmin),
):
    lic = (
        await db.execute(select(License).where(License.id == license_id))
    ).scalar_one_or_none()
    if lic is None:
        raise HTTPException(404, "License not found")
    tenant = (
        await db.execute(select(Tenant).where(Tenant.id == lic.tenant_id))
    ).scalar_one_or_none()
    await log_audit(
        db=db,
        actor=actor,
        action=AuditAction.license_delete,
        entity_type="license",
        entity_id=lic.id,
        target_tenant=tenant,
        payload={
            "before": {
                "key_prefix": lic.key[:8],
                "expires_at": lic.expires_at.isoformat(),
                "is_revoked": lic.is_revoked,
            }
        },
        request=request,
    )
    await db.delete(lic)
    await db.commit()
