"""MeasurementRecord — server-side mirror of the Flutter app's measurement.

Every row carries `tenant_id` for hard isolation. Mobile uploader POSTs the
flat JSON; server assigns its own UUID `id`, retains the original `local_id`.
"""
from __future__ import annotations

from datetime import datetime, timezone
from enum import Enum
from typing import TYPE_CHECKING
from uuid import UUID, uuid4

from sqlalchemy import (
    Boolean,
    DateTime,
    Enum as SqlEnum,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID as PgUUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..core.database import Base

if TYPE_CHECKING:
    from .tenant import Tenant


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class MeasurementSource(str, Enum):
    mobile = "mobile"
    edge = "edge"
    fused = "fused"


class MeasurementRecord(Base):
    __tablename__ = "measurements"
    __table_args__ = (
        Index("ix_measurements_tenant_timestamp", "tenant_id", "timestamp"),
        Index("ix_measurements_tenant_device", "tenant_id", "device_id"),
        Index("ix_measurements_tenant_source", "tenant_id", "source"),
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

    # ── Mobile-side identifiers ─────────────────────────────────────────
    local_id: Mapped[int | None] = mapped_column(Integer)
    device_id: Mapped[str | None] = mapped_column(String(100), index=True)
    source: Mapped[MeasurementSource] = mapped_column(
        SqlEnum(MeasurementSource, name="measurement_source"),
        nullable=False,
        default=MeasurementSource.mobile,
    )

    # ── Core measurement ────────────────────────────────────────────────
    timestamp: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    risk_percent: Mapped[float] = mapped_column(Float, nullable=False)
    frequency_hz: Mapped[float] = mapped_column(Float, nullable=False)
    amplitude_mm: Mapped[float] = mapped_column(Float, nullable=False)
    risk_level: Mapped[str] = mapped_column(String(20), nullable=False)
    frame_count: Mapped[int | None] = mapped_column(Integer)
    duration_seconds: Mapped[int | None] = mapped_column(Integer)

    # ── Material + object ──────────────────────────────────────────────
    material_id: Mapped[str | None] = mapped_column(String(50))
    object_label: Mapped[str | None] = mapped_column(String(100))

    # ── Geo (Phase 3) ──────────────────────────────────────────────────
    lat: Mapped[float | None] = mapped_column(Float)
    lng: Mapped[float | None] = mapped_column(Float)
    accuracy_m: Mapped[float | None] = mapped_column(Float)

    # ── Magnetometer (Phase 3) ─────────────────────────────────────────
    magnetic_field_ut: Mapped[float | None] = mapped_column(Float)
    magnetic_anomaly: Mapped[bool | None] = mapped_column(Boolean)

    # ── Prediction §6.4 (parabolic) ────────────────────────────────────
    prediction_a: Mapped[float | None] = mapped_column(Float)
    prediction_b: Mapped[float | None] = mapped_column(Float)
    prediction_c: Mapped[float | None] = mapped_column(Float)
    hours_to_critical: Mapped[float | None] = mapped_column(Float)

    # ── Hotspots + fusion ──────────────────────────────────────────────
    hotspots: Mapped[list | dict | None] = mapped_column(JSONB)
    fusion_confidence: Mapped[float | None] = mapped_column(Float)

    # ── Server metadata ────────────────────────────────────────────────
    received_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    raw_payload: Mapped[dict | None] = mapped_column(JSONB)  # debug / replay

    tenant: Mapped["Tenant"] = relationship(back_populates="measurements")

    def __repr__(self) -> str:
        return (
            f"<MeasurementRecord {self.id} tenant={self.tenant_id} "
            f"{self.risk_level} {self.risk_percent:.0f}%>"
        )
