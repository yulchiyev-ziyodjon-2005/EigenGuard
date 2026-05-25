"""Superadmin tenants CRUD — faqat superadmin tenant'idan kirgan adminlar uchun."""
from __future__ import annotations

from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import desc, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..core.audit import log_audit
from ..core.database import get_db
from ..core.deps import require_superadmin
from ..core.security import hash_password
from ..models.audit_log import AuditAction
from ..models.device import Device
from ..models.license import License
from ..models.measurement import MeasurementRecord
from ..models.tenant import DeploymentMode, Tenant
from ..models.user import User, UserRole

router = APIRouter(
    prefix="/api/v1/superadmin/tenants",
    tags=["superadmin"],
    dependencies=[Depends(require_superadmin)],
)


class TenantOut(BaseModel):
    id: str
    name: str
    subdomain: str
    deployment_mode: str
    is_active: bool
    contact_email: str | None
    user_count: int = 0
    measurement_count: int = 0
    device_count: int = 0
    active_license_count: int = 0
    created_at: datetime


class TenantCreate(BaseModel):
    name: str = Field(min_length=2, max_length=200)
    subdomain: str = Field(pattern=r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")
    deployment_mode: str = "cloud"
    contact_email: EmailStr | None = None
    # Birinchi admin user — tenant yaratish bilan birga
    admin_username: str | None = Field(default=None, min_length=3, max_length=80)
    admin_email: EmailStr
    admin_password: str = Field(min_length=8, max_length=128)
    admin_full_name: str | None = None


class TenantPatch(BaseModel):
    name: str | None = None
    is_active: bool | None = None
    contact_email: EmailStr | None = None
    deployment_mode: str | None = None
    notes: str | None = None


class UserBrief(BaseModel):
    id: str
    username: str
    email: str
    full_name: str | None
    role: str
    is_admin: bool
    is_active: bool
    created_at: datetime
    last_login_at: datetime | None


class DeviceBrief(BaseModel):
    id: str
    device_identifier: str
    platform: str
    device_name: str | None
    is_active: bool
    last_seen_at: datetime
    created_at: datetime


class LicenseBrief(BaseModel):
    id: str
    key: str
    issued_at: datetime
    expires_at: datetime
    max_devices: int
    max_users: int
    is_revoked: bool
    is_expired: bool
    features: dict | None


class MeasurementBrief(BaseModel):
    id: str
    timestamp: datetime
    risk_percent: float
    risk_level: str
    frequency_hz: float
    amplitude_mm: float
    source: str
    device_id: str | None


class TenantDetail(BaseModel):
    tenant: TenantOut
    users: list[UserBrief]
    devices: list[DeviceBrief]
    licenses: list[LicenseBrief]
    recent_measurements: list[MeasurementBrief]


def _to_mode(value: str) -> DeploymentMode:
    try:
        return DeploymentMode(value)
    except ValueError:
        raise HTTPException(400, f"Invalid deployment_mode: {value}")


def _normalize_username(value: str) -> str:
    username = value.strip().lower()
    if not username:
        raise HTTPException(422, "Admin username is required")
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
    return _normalize_username(username or "admin")


async def _stats(db: AsyncSession, tenant_id: UUID) -> tuple[int, int, int, int]:
    uc = (
        await db.execute(select(func.count(User.id)).where(User.tenant_id == tenant_id))
    ).scalar_one()
    mc = (
        await db.execute(
            select(func.count(MeasurementRecord.id)).where(
                MeasurementRecord.tenant_id == tenant_id
            )
        )
    ).scalar_one()
    dc = (
        await db.execute(
            select(func.count(Device.id)).where(Device.tenant_id == tenant_id)
        )
    ).scalar_one()
    lc = (
        await db.execute(
            select(func.count(License.id)).where(
                License.tenant_id == tenant_id, License.is_revoked.is_(False)
            )
        )
    ).scalar_one()
    return uc, mc, dc, lc


def _serialize(
    t: Tenant,
    *,
    user_count: int = 0,
    measurement_count: int = 0,
    device_count: int = 0,
    active_license_count: int = 0,
) -> TenantOut:
    return TenantOut(
        id=str(t.id),
        name=t.name,
        subdomain=t.subdomain,
        deployment_mode=t.deployment_mode.value,
        is_active=t.is_active,
        contact_email=t.contact_email,
        user_count=user_count,
        measurement_count=measurement_count,
        device_count=device_count,
        active_license_count=active_license_count,
        created_at=t.created_at,
    )


@router.get("", response_model=list[TenantOut])
async def list_tenants(db: AsyncSession = Depends(get_db)):
    tenants = (
        await db.execute(select(Tenant).order_by(Tenant.created_at.desc()))
    ).scalars().all()
    out: list[TenantOut] = []
    for t in tenants:
        uc, mc, dc, lc = await _stats(db, t.id)
        out.append(
            _serialize(
                t,
                user_count=uc,
                measurement_count=mc,
                device_count=dc,
                active_license_count=lc,
            )
        )
    return out


@router.post("", status_code=status.HTTP_201_CREATED, response_model=TenantOut)
async def create_tenant(
    payload: TenantCreate,
    request: Request,
    db: AsyncSession = Depends(get_db),
    actor: User = Depends(require_superadmin),
):
    mode = _to_mode(payload.deployment_mode)
    if mode == DeploymentMode.superadmin:
        raise HTTPException(400, "Superadmin tenant cannot be created from tenant CRUD")
    # Subdomain unique check
    existing = (
        await db.execute(select(Tenant).where(Tenant.subdomain == payload.subdomain))
    ).scalar_one_or_none()
    if existing is not None:
        raise HTTPException(409, f"Subdomain '{payload.subdomain}' already taken")
    admin_username = _normalize_username(
        payload.admin_username or _default_username(payload.admin_email)
    )

    tenant = Tenant(
        name=payload.name,
        subdomain=payload.subdomain.lower(),
        deployment_mode=mode,
        contact_email=payload.contact_email,
        is_active=True,
    )
    db.add(tenant)
    await db.flush()  # get tenant.id

    admin = User(
        tenant_id=tenant.id,
        username=admin_username,
        email=payload.admin_email.lower(),
        password_hash=hash_password(payload.admin_password),
        full_name=payload.admin_full_name,
        role=UserRole.tenant_admin.value,
        is_admin=True,
        is_active=True,
    )
    db.add(admin)
    await db.flush()

    await log_audit(
        db=db,
        actor=actor,
        action=AuditAction.tenant_create,
        entity_type="tenant",
        entity_id=tenant.id,
        target_tenant=tenant,
        payload={
            "after": {
                "name": tenant.name,
                "subdomain": tenant.subdomain,
                "deployment_mode": tenant.deployment_mode.value,
                "contact_email": tenant.contact_email,
                "admin_username": admin.username,
                "admin_email": admin.email,
            }
        },
        request=request,
    )
    await db.commit()
    await db.refresh(tenant)
    return _serialize(tenant, user_count=1)


@router.get("/{tenant_id}", response_model=TenantDetail)
async def tenant_detail(tenant_id: UUID, db: AsyncSession = Depends(get_db)):
    tenant = (
        await db.execute(select(Tenant).where(Tenant.id == tenant_id))
    ).scalar_one_or_none()
    if tenant is None:
        raise HTTPException(404, "Tenant not found")

    uc, mc, dc, lc = await _stats(db, tenant.id)

    users = (
        await db.execute(
            select(User)
            .where(User.tenant_id == tenant.id)
            .order_by(desc(User.created_at))
        )
    ).scalars().all()

    devices = (
        await db.execute(
            select(Device)
            .where(Device.tenant_id == tenant.id)
            .order_by(desc(Device.last_seen_at))
        )
    ).scalars().all()

    licenses = (
        await db.execute(
            select(License)
            .where(License.tenant_id == tenant.id)
            .order_by(desc(License.issued_at))
        )
    ).scalars().all()

    measurements = (
        await db.execute(
            select(MeasurementRecord)
            .where(MeasurementRecord.tenant_id == tenant.id)
            .order_by(desc(MeasurementRecord.timestamp))
            .limit(20)
        )
    ).scalars().all()

    return TenantDetail(
        tenant=_serialize(
            tenant,
            user_count=uc,
            measurement_count=mc,
            device_count=dc,
            active_license_count=lc,
        ),
        users=[
            UserBrief(
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
            for u in users
        ],
        devices=[
            DeviceBrief(
                id=str(d.id),
                device_identifier=d.device_identifier,
                platform=d.platform,
                device_name=d.device_name,
                is_active=d.is_active,
                last_seen_at=d.last_seen_at,
                created_at=d.created_at,
            )
            for d in devices
        ],
        licenses=[
            LicenseBrief(
                id=str(lic.id),
                key=lic.key,
                issued_at=lic.issued_at,
                expires_at=lic.expires_at,
                max_devices=lic.max_devices,
                max_users=lic.max_users,
                is_revoked=lic.is_revoked,
                is_expired=lic.is_expired,
                features=lic.features,
            )
            for lic in licenses
        ],
        recent_measurements=[
            MeasurementBrief(
                id=str(m.id),
                timestamp=m.timestamp,
                risk_percent=m.risk_percent,
                risk_level=m.risk_level,
                frequency_hz=m.frequency_hz,
                amplitude_mm=m.amplitude_mm,
                source=m.source.value,
                device_id=m.device_id,
            )
            for m in measurements
        ],
    )


@router.patch("/{tenant_id}", response_model=TenantOut)
async def update_tenant(
    tenant_id: UUID,
    payload: TenantPatch,
    request: Request,
    db: AsyncSession = Depends(get_db),
    actor: User = Depends(require_superadmin),
):
    tenant = (
        await db.execute(select(Tenant).where(Tenant.id == tenant_id))
    ).scalar_one_or_none()
    if tenant is None:
        raise HTTPException(404, "Tenant not found")
    before: dict = {}
    after: dict = {}
    if payload.name is not None and payload.name != tenant.name:
        before["name"] = tenant.name
        after["name"] = payload.name
        tenant.name = payload.name
    if payload.is_active is not None and payload.is_active != tenant.is_active:
        before["is_active"] = tenant.is_active
        after["is_active"] = payload.is_active
        tenant.is_active = payload.is_active
    if payload.contact_email is not None and payload.contact_email != tenant.contact_email:
        before["contact_email"] = tenant.contact_email
        after["contact_email"] = payload.contact_email
        tenant.contact_email = payload.contact_email
    if payload.deployment_mode is not None:
        new_mode = _to_mode(payload.deployment_mode)
        if new_mode != tenant.deployment_mode:
            before["deployment_mode"] = tenant.deployment_mode.value
            after["deployment_mode"] = new_mode.value
            tenant.deployment_mode = new_mode
    if payload.notes is not None and payload.notes != tenant.notes:
        before["notes"] = tenant.notes
        after["notes"] = payload.notes
        tenant.notes = payload.notes

    if after:
        await log_audit(
            db=db,
            actor=actor,
            action=AuditAction.tenant_update,
            entity_type="tenant",
            entity_id=tenant.id,
            target_tenant=tenant,
            payload={"before": before, "after": after},
            request=request,
        )

    await db.commit()
    await db.refresh(tenant)
    uc, mc, dc, lc = await _stats(db, tenant.id)
    return _serialize(
        tenant,
        user_count=uc,
        measurement_count=mc,
        device_count=dc,
        active_license_count=lc,
    )


@router.delete("/{tenant_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_tenant(
    tenant_id: UUID,
    request: Request,
    db: AsyncSession = Depends(get_db),
    actor: User = Depends(require_superadmin),
):
    tenant = (
        await db.execute(select(Tenant).where(Tenant.id == tenant_id))
    ).scalar_one_or_none()
    if tenant is None:
        raise HTTPException(404, "Tenant not found")
    if tenant.deployment_mode == DeploymentMode.superadmin:
        raise HTTPException(403, "Cannot delete superadmin tenant")
    # Audit yozuvini delete'dan oldin commit qilamiz, chunki AuditLog target_tenant_id
    # SET NULL bog'langan — agar bir tranzaksiyada o'chirsak ham, yozuvda subdomain
    # nusxasi qoladi.
    await log_audit(
        db=db,
        actor=actor,
        action=AuditAction.tenant_delete,
        entity_type="tenant",
        entity_id=tenant.id,
        target_tenant=tenant,
        payload={
            "before": {
                "name": tenant.name,
                "subdomain": tenant.subdomain,
                "deployment_mode": tenant.deployment_mode.value,
            }
        },
        request=request,
    )
    await db.delete(tenant)
    await db.commit()
