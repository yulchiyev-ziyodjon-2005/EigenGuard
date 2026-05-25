"""User model: tenant-scoped account with username, role and password hash."""
from __future__ import annotations

from datetime import datetime, timezone
from enum import Enum
from typing import TYPE_CHECKING
from uuid import UUID, uuid4

from sqlalchemy import Boolean, DateTime, ForeignKey, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID as PgUUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..core.database import Base

if TYPE_CHECKING:
    from .tenant import Tenant


class UserRole(str, Enum):
    superadmin = "superadmin"
    tenant_admin = "tenant_admin"
    engineer = "engineer"
    operator = "operator"
    viewer = "viewer"


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = "users"
    # Same username/email may exist across tenants, but not inside one tenant.
    __table_args__ = (
        UniqueConstraint("tenant_id", "email", name="uq_users_tenant_email"),
        UniqueConstraint("tenant_id", "username", name="uq_users_tenant_username"),
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
    username: Mapped[str] = mapped_column(String(80), nullable=False)
    email: Mapped[str] = mapped_column(String(200), nullable=False)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    full_name: Mapped[str | None] = mapped_column(String(200))
    role: Mapped[str] = mapped_column(
        String(30), default=UserRole.engineer.value, nullable=False
    )
    # Backward-compatible admin flag used by existing route guards/JWTs.
    is_admin: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    tenant: Mapped["Tenant"] = relationship()

    def __repr__(self) -> str:
        return f"<User {self.username} tenant={self.tenant_id} role={self.role}>"
