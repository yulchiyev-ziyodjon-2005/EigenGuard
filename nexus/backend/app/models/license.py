"""License model — issued by Superadmin, validated periodically."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import TYPE_CHECKING
from uuid import UUID, uuid4

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.dialects.postgresql import JSONB, UUID as PgUUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..core.database import Base

if TYPE_CHECKING:
    from .tenant import Tenant


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class License(Base):
    __tablename__ = "licenses"

    id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True), primary_key=True, default=uuid4
    )
    tenant_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        ForeignKey("tenants.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # Public-facing key — distributed to the client (UUID or random 32-byte hex)
    key: Mapped[str] = mapped_column(
        String(128), unique=True, nullable=False, index=True
    )

    # Ed25519-signed cert payload for air-gapped offline validation.
    # Format: <payload_b64>.<signature_b64>
    # Payload JSON: {license_key, tenant_id, expires_at, features, max_devices, max_users}
    signed_certificate: Mapped[str | None] = mapped_column(Text)

    issued_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )

    # Quotas
    max_devices: Mapped[int] = mapped_column(Integer, default=10, nullable=False)
    max_users: Mapped[int] = mapped_column(Integer, default=5, nullable=False)
    # Feature flags — {"custom_ai": true, "multi_site": false, "alert_routing": true}
    features: Mapped[dict] = mapped_column(JSONB, default=dict, nullable=False)

    # Periodic validation tracking
    last_validated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    is_revoked: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    revocation_reason: Mapped[str | None] = mapped_column(Text)

    tenant: Mapped["Tenant"] = relationship(back_populates="licenses")

    # ── Convenience helpers ─────────────────────────────────────────────
    @property
    def is_expired(self) -> bool:
        return datetime.now(timezone.utc) >= self.expires_at

    @property
    def is_valid(self) -> bool:
        return not self.is_revoked and not self.is_expired

    def needs_revalidation(self, hours: int = 24) -> bool:
        if self.last_validated_at is None:
            return True
        return datetime.now(timezone.utc) - self.last_validated_at > timedelta(hours=hours)

    def __repr__(self) -> str:
        status = "REVOKED" if self.is_revoked else "EXPIRED" if self.is_expired else "active"
        return f"<License {self.key[:8]}... tenant={self.tenant_id} {status}>"
