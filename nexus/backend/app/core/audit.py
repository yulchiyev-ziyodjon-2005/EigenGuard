"""Audit log yozish uchun yagona helper — superadmin mutatsiyalarda chaqiriladi."""
from __future__ import annotations

from typing import Any
from uuid import UUID

from fastapi import Request
from sqlalchemy.ext.asyncio import AsyncSession

from ..models.audit_log import AuditAction, AuditLog
from ..models.tenant import Tenant
from ..models.user import User


def _client_ip(request: Request | None) -> str | None:
    if request is None:
        return None
    # X-Forwarded-For — reverse proxy ortida (nginx)
    xff = request.headers.get("x-forwarded-for")
    if xff:
        return xff.split(",")[0].strip()
    client = request.client
    return client.host if client else None


async def log_audit(
    *,
    db: AsyncSession,
    actor: User,
    action: AuditAction,
    entity_type: str,
    entity_id: str | UUID | None = None,
    target_tenant: Tenant | None = None,
    payload: dict[str, Any] | None = None,
    request: Request | None = None,
    commit: bool = False,
) -> AuditLog:
    """Yangi AuditLog yozuvini yaratadi. Default — flush only, parent commit qiladi."""
    entry = AuditLog(
        actor_user_id=actor.id,
        actor_email=actor.email,
        target_tenant_id=target_tenant.id if target_tenant else None,
        target_tenant_subdomain=target_tenant.subdomain if target_tenant else None,
        action=action,
        entity_type=entity_type,
        entity_id=str(entity_id) if entity_id is not None else None,
        payload=payload,
        ip_address=_client_ip(request),
        user_agent=(request.headers.get("user-agent") if request else None),
    )
    db.add(entry)
    if commit:
        await db.commit()
    else:
        await db.flush()
    return entry
