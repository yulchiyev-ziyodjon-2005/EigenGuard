"""Tenant model — every data row is FK-bound to one tenant for isolation."""
from __future__ import annotations

from datetime import datetime, timezone
from enum import Enum
from typing import TYPE_CHECKING
from uuid import UUID, uuid4

from sqlalchemy import Boolean, DateTime, Enum as SqlEnum, String
from sqlalchemy.dialects.postgresql import UUID as PgUUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..core.database import Base

if TYPE_CHECKING:
    from .license import License
    from .measurement import MeasurementRecord


class DeploymentMode(str, Enum):
    cloud = "cloud"
    on_premise = "on_premise"
    air_gapped = "air_gapped"
    superadmin = "superadmin"


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Tenant(Base):
    __tablename__ = "tenants"

    id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True), primary_key=True, default=uuid4
    )
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    # Cloud routing — `clientA` for `clientA.eigenguard.uz`
    # On-premise default — "default"
    subdomain: Mapped[str] = mapped_column(
        String(63), unique=True, nullable=False, index=True
    )
    deployment_mode: Mapped[DeploymentMode] = mapped_column(
        SqlEnum(DeploymentMode, name="deployment_mode"),
        nullable=False,
        default=DeploymentMode.cloud,
    )
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    contact_email: Mapped[str | None] = mapped_column(String(200))
    notes: Mapped[str | None] = mapped_column(String(1000))

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utcnow,
        onupdate=_utcnow,
        nullable=False,
    )

    licenses: Mapped[list["License"]] = relationship(
        back_populates="tenant", cascade="all, delete-orphan"
    )
    measurements: Mapped[list["MeasurementRecord"]] = relationship(
        back_populates="tenant", cascade="all, delete-orphan"
    )

    def __repr__(self) -> str:
        return f"<Tenant {self.subdomain} ({self.deployment_mode.value})>"
