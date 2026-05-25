"""Superadmin audit log — barcha tenant/license mutatsiyalari tarixi."""
from __future__ import annotations

from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy import desc, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..core.database import get_db
from ..core.deps import require_superadmin
from ..models.audit_log import AuditAction, AuditLog

router = APIRouter(
    prefix="/api/v1/superadmin/audit-logs",
    tags=["superadmin"],
    dependencies=[Depends(require_superadmin)],
)


class AuditLogOut(BaseModel):
    id: str
    actor_user_id: str | None
    actor_email: str
    target_tenant_id: str | None
    target_tenant_subdomain: str | None
    action: str
    entity_type: str
    entity_id: str | None
    payload: dict | None
    ip_address: str | None
    user_agent: str | None
    created_at: datetime


class AuditLogPage(BaseModel):
    total: int
    items: list[AuditLogOut]


def _ser(row: AuditLog) -> AuditLogOut:
    return AuditLogOut(
        id=str(row.id),
        actor_user_id=str(row.actor_user_id) if row.actor_user_id else None,
        actor_email=row.actor_email,
        target_tenant_id=str(row.target_tenant_id) if row.target_tenant_id else None,
        target_tenant_subdomain=row.target_tenant_subdomain,
        action=row.action.value,
        entity_type=row.entity_type,
        entity_id=row.entity_id,
        payload=row.payload,
        ip_address=str(row.ip_address) if row.ip_address else None,
        user_agent=row.user_agent,
        created_at=row.created_at,
    )


@router.get("", response_model=AuditLogPage)
async def list_audit_logs(
    db: AsyncSession = Depends(get_db),
    action: str | None = Query(None, description="Filter — masalan tenant_create"),
    tenant_id: UUID | None = Query(None, description="Filter — target tenant_id"),
    actor_email: str | None = Query(None),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
):
    where = []
    if action:
        try:
            where.append(AuditLog.action == AuditAction(action))
        except ValueError:
            # noma'lum action — bo'sh natija
            return AuditLogPage(total=0, items=[])
    if tenant_id is not None:
        where.append(AuditLog.target_tenant_id == tenant_id)
    if actor_email:
        where.append(AuditLog.actor_email.ilike(f"%{actor_email.lower()}%"))

    total_q = select(func.count(AuditLog.id))
    list_q = select(AuditLog).order_by(desc(AuditLog.created_at))
    for cond in where:
        total_q = total_q.where(cond)
        list_q = list_q.where(cond)
    list_q = list_q.limit(limit).offset(offset)

    total = (await db.execute(total_q)).scalar_one()
    rows = (await db.execute(list_q)).scalars().all()
    return AuditLogPage(total=total, items=[_ser(r) for r in rows])


@router.get("/actions", response_model=list[str])
async def list_actions():
    """Mavjud action turlari — frontend filter dropdown uchun."""
    return [a.value for a in AuditAction]
