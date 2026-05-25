"""Device — bog'langan mobile telefon (har tenant uchun alohida ro'yxat)."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import TYPE_CHECKING
from uuid import UUID, uuid4

from sqlalchemy import Boolean, DateTime, ForeignKey, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID as PgUUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..core.database import Base

if TYPE_CHECKING:
    from .tenant import Tenant
    from .user import User


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Device(Base):
    """Telefon ro'yxati. Bitta xodim bitta yoki ko'p telefondan login qila oladi.

    Mobile birinchi marta WebSocket'ga ulanganda yoki o'lchov yuborganda
    avtomatik ro'yxatga olinadi.
    """

    __tablename__ = "devices"
    __table_args__ = (
        UniqueConstraint(
            "tenant_id", "device_identifier", name="uq_devices_tenant_ident"
        ),
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
    user_id: Mapped[UUID | None] = mapped_column(
        PgUUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        index=True,
    )
    # Telefonning unique identifikatori (Android ID, iOS identifierForVendor,
    # yoki birinchi install'da generatsiya qilingan UUID)
    device_identifier: Mapped[str] = mapped_column(String(128), nullable=False)
    platform: Mapped[str] = mapped_column(String(20), default="android", nullable=False)
    device_name: Mapped[str | None] = mapped_column(String(200))
    push_token: Mapped[str | None] = mapped_column(String(500))  # FCM/APNs token
    app_version: Mapped[str | None] = mapped_column(String(50))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    last_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )

    tenant: Mapped["Tenant"] = relationship()
    user: Mapped["User | None"] = relationship()

    def __repr__(self) -> str:
        return f"<Device {self.device_identifier[:16]}... tenant={self.tenant_id}>"
