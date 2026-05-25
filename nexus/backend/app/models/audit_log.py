"""AuditLog — superadmin mutatsiyalari uchun immutable o'zgarishlar tarixi.

Har bir tenant create/update/delete va license create/renew/revoke/update
yozuvi shu jadvalga tushadi. Bu compliance + xavfsizlik uchun ham, jonli
debug uchun ham kerak.

Eslatma: ushbu jadval `tenant.id` ga `SET NULL` (CASCADE EMAS) sifatida
bog'lanadi — tenant o'chirilsa ham audit yozuvi qoladi (tarix saqlanadi).
"""
from __future__ import annotations

from datetime import datetime, timezone
from enum import Enum
from uuid import UUID, uuid4

from sqlalchemy import DateTime, Enum as SqlEnum, ForeignKey, Index, String
from sqlalchemy.dialects.postgresql import INET, JSONB, UUID as PgUUID
from sqlalchemy.orm import Mapped, mapped_column

from ..core.database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class AuditAction(str, Enum):
    tenant_create = "tenant_create"
    tenant_update = "tenant_update"
    tenant_delete = "tenant_delete"
    license_create = "license_create"
    license_update = "license_update"
    license_renew = "license_renew"
    license_revoke = "license_revoke"
    license_delete = "license_delete"


class AuditLog(Base):
    __tablename__ = "audit_logs"
    __table_args__ = (
        Index("ix_audit_logs_action_created", "action", "created_at"),
        Index("ix_audit_logs_target_tenant", "target_tenant_id", "created_at"),
    )

    id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True), primary_key=True, default=uuid4
    )

    # Kim qildi — user o'chirilsa ham email saqlanadi
    actor_user_id: Mapped[UUID | None] = mapped_column(
        PgUUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL")
    )
    actor_email: Mapped[str] = mapped_column(String(200), nullable=False)

    # Nima ustida — tenant o'chirilsa ham yozuv qoladi
    target_tenant_id: Mapped[UUID | None] = mapped_column(
        PgUUID(as_uuid=True),
        ForeignKey("tenants.id", ondelete="SET NULL"),
        index=True,
    )
    target_tenant_subdomain: Mapped[str | None] = mapped_column(String(63))

    action: Mapped[AuditAction] = mapped_column(
        SqlEnum(AuditAction, name="audit_action"), nullable=False, index=True
    )
    entity_type: Mapped[str] = mapped_column(String(50), nullable=False)
    entity_id: Mapped[str | None] = mapped_column(String(64))

    # Erkin payload — qaysi maydonlar o'zgarganini saqlash uchun
    # Masalan: {"before": {"is_active": true}, "after": {"is_active": false}}
    payload: Mapped[dict | None] = mapped_column(JSONB)

    ip_address: Mapped[str | None] = mapped_column(INET)
    user_agent: Mapped[str | None] = mapped_column(String(500))

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False, index=True
    )

    def __repr__(self) -> str:
        return (
            f"<AuditLog {self.action.value} actor={self.actor_email} "
            f"target={self.target_tenant_subdomain}>"
        )
