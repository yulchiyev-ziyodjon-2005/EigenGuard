"""Command — tenant admindan mobile telefonga buyruq.

Status lifecycle:
  pending      → web admin POST qildi, hali yetkazilmagan
  delivered    → mobile WebSocket orqali oldi
  acknowledged → mobile bajarilganini POST qildi
  failed       → mobile xato qaytardi
  expired      → expires_at o'tib ketdi
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from enum import Enum
from typing import TYPE_CHECKING
from uuid import UUID, uuid4

from sqlalchemy import DateTime, Enum as SqlEnum, ForeignKey, Index, String
from sqlalchemy.dialects.postgresql import JSONB, UUID as PgUUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..core.database import Base

if TYPE_CHECKING:
    from .device import Device
    from .tenant import Tenant
    from .user import User


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _default_expiry() -> datetime:
    return datetime.now(timezone.utc) + timedelta(hours=24)


class CommandStatus(str, Enum):
    pending = "pending"
    delivered = "delivered"
    acknowledged = "acknowledged"
    failed = "failed"
    expired = "expired"


class CommandType(str, Enum):
    """Web admin tomonidan mobile'ga yuboriladigan buyruqlar ro'yxati.

    Mobile tomonida har bir type uchun handler kerak.
    """
    notify = "notify"                    # Oddiy bildirishnoma (text)
    start_scan = "start_scan"            # Monitoring boshlash
    stop_scan = "stop_scan"              # Monitoring to'xtatish
    enable_demo_mode = "enable_demo_mode"
    disable_demo_mode = "disable_demo_mode"
    set_material = "set_material"        # payload: {material_id}
    take_snapshot = "take_snapshot"      # Skrinshot olish va Nexus'ga yuborish
    sync_now = "sync_now"                # NexusUploadService.syncNow()
    custom = "custom"                    # Erkin payload


class Command(Base):
    __tablename__ = "commands"
    __table_args__ = (
        Index("ix_commands_tenant_status", "tenant_id", "status"),
        Index("ix_commands_device_status", "device_id", "status"),
    )

    id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True), primary_key=True, default=uuid4
    )
    tenant_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        ForeignKey("tenants.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    device_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        ForeignKey("devices.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    issued_by_user_id: Mapped[UUID | None] = mapped_column(
        PgUUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL")
    )

    command_type: Mapped[CommandType] = mapped_column(
        SqlEnum(CommandType, name="command_type"), nullable=False
    )
    payload: Mapped[dict | None] = mapped_column(JSONB)
    status: Mapped[CommandStatus] = mapped_column(
        SqlEnum(CommandStatus, name="command_status"),
        default=CommandStatus.pending,
        nullable=False,
    )
    error_message: Mapped[str | None] = mapped_column(String(500))
    result_payload: Mapped[dict | None] = mapped_column(JSONB)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    delivered_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    acknowledged_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_default_expiry, nullable=False
    )

    tenant: Mapped["Tenant"] = relationship()
    device: Mapped["Device"] = relationship()
    issued_by: Mapped["User | None"] = relationship()

    def to_wire(self) -> dict:
        """Mobile WebSocket'ga yuboriladigan kompakt format."""
        return {
            "id": str(self.id),
            "type": self.command_type.value,
            "payload": self.payload or {},
            "issued_at": self.created_at.isoformat(),
            "expires_at": self.expires_at.isoformat(),
        }

    def __repr__(self) -> str:
        return (
            f"<Command {self.command_type.value} device={self.device_id} "
            f"status={self.status.value}>"
        )
