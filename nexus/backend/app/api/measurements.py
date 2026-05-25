"""Measurements REST API — mobile uploader POSTs, web panel GETs."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from pydantic import BaseModel, Field
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..core.database import get_db
from ..core.deps import get_current_user
from ..core.ws_manager import ws_manager
from ..models.measurement import MeasurementRecord, MeasurementSource
from ..models.tenant import Tenant
from ..models.user import User

router = APIRouter(prefix="/api/v1/measurements", tags=["measurements"])


class MeasurementIn(BaseModel):
    """Lenient input schema — matches Flutter `NexusUploadService._recordToJson()`."""
    local_id: int | None = None
    device_id: str | None = None
    source: str = "mobile"
    timestamp: datetime
    risk_percent: float
    frequency_hz: float
    amplitude_mm: float
    risk_level: str
    frame_count: int | None = None
    duration_seconds: int | None = None
    object_label: str | None = None
    material_id: str | None = None
    lat: float | None = None
    lng: float | None = None
    accuracy_m: float | None = None
    magnetic_field_ut: float | None = None
    magnetic_anomaly: bool | None = None
    prediction_a: float | None = None
    prediction_b: float | None = None
    prediction_c: float | None = None
    hours_to_critical: float | None = None
    hotspots: Any | None = None
    fusion_confidence: float | None = None


class MeasurementOut(BaseModel):
    id: str
    nexus_id: str = Field(alias="id")  # for mobile uploader to track
    local_id: int | None = None
    device_id: str | None = None
    source: str
    timestamp: datetime
    risk_percent: float
    frequency_hz: float
    amplitude_mm: float
    risk_level: str
    fusion_confidence: float | None = None
    received_at: datetime

    model_config = {"populate_by_name": True}


class PredictionInput(BaseModel):
    """Sensor + camera features used by the MVP mock AI engine."""

    device_id: str | None = None
    timestamp: datetime | None = None
    amplitude_mm: float = Field(ge=0)
    frequency_hz: float = Field(ge=0)
    camera_risk: float = Field(ge=0, le=100)


class PredictionOutput(BaseModel):
    device_id: str | None = None
    timestamp: datetime
    health_index: float
    anomaly_probability: float
    hours_to_critical: float | None
    risk_level: str
    verdict: str
    recommendations: list[str]
    created_at: datetime


def _to_source(value: str) -> MeasurementSource:
    try:
        return MeasurementSource(value.lower())
    except ValueError:
        return MeasurementSource.mobile


def _clamp(value: float, minimum: float = 0.0, maximum: float = 100.0) -> float:
    return max(minimum, min(maximum, value))


def _risk_level(total_risk: float) -> str:
    if total_risk >= 80:
        return "CRITICAL"
    if total_risk >= 60:
        return "HIGH"
    if total_risk >= 35:
        return "MEDIUM"
    return "LOW"


def _hours_to_critical(total_risk: float) -> float | None:
    if total_risk >= 80:
        return 0.0
    if total_risk < 35:
        return None
    return round(max(2.0, (80.0 - total_risk) * 2.4), 1)


def _recommendations(level: str, total_risk: float) -> list[str]:
    if level == "CRITICAL":
        return [
            "Darhol inspektor tekshiruvi va yuklamani kamaytirish talab qilinadi.",
            "Sensor va kamera ma'lumotlarini qayta kalibrlab, yaqin monitoring rejimini yoqing.",
        ]
    if level == "HIGH":
        return [
            "48 soat ichida texnik ko'rik rejalashtiring.",
            "Vibratsiya amplitudasi va kamera riskini har 15 daqiqada qayta o'lchang.",
        ]
    if level == "MEDIUM":
        return [
            "Profilaktik monitoringni kuchaytiring.",
            "Chastota trendi o'sishda davom etsa, obyektni qayta skan qiling.",
        ]
    if total_risk >= 20:
        return ["Rejali monitoringni davom ettiring."]
    return ["Tizim normal holatda, standart monitoring yetarli."]


def analyze_signal(payload: PredictionInput) -> PredictionOutput:
    """Deterministic MVP AI engine; replaceable with a real model later."""
    amplitude_risk = _clamp((payload.amplitude_mm / 5.0) * 100.0)
    frequency_risk = _clamp((payload.frequency_hz / 120.0) * 100.0)
    camera_risk = _clamp(payload.camera_risk)
    total_risk = _clamp(
        amplitude_risk * 0.45 + frequency_risk * 0.30 + camera_risk * 0.25
    )
    health_index = round(100.0 - total_risk, 1)
    anomaly_probability = round(total_risk / 100.0, 3)
    level = _risk_level(total_risk)
    hours = _hours_to_critical(total_risk)

    if level == "CRITICAL":
        verdict = "Kritik holat: darhol aralashuv kerak"
    elif level == "HIGH":
        verdict = f"Yuqori xavf: kritik holatga taxminan {hours:.1f} soat qoldi"
    elif level == "MEDIUM":
        verdict = "O'rtacha anomaliya: trendni yaqindan kuzatish kerak"
    else:
        verdict = "Barqaror holat: jiddiy anomaliya aniqlanmadi"

    now = datetime.now(timezone.utc)
    return PredictionOutput(
        device_id=payload.device_id,
        timestamp=payload.timestamp or now,
        health_index=health_index,
        anomaly_probability=anomaly_probability,
        hours_to_critical=hours,
        risk_level=level,
        verdict=verdict,
        recommendations=_recommendations(level, total_risk),
        created_at=now,
    )


@router.post("", status_code=status.HTTP_201_CREATED, response_model=MeasurementOut)
async def create_measurement(
    payload: MeasurementIn,
    request: Request,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    tenant: Tenant = request.state.tenant
    record = MeasurementRecord(
        tenant_id=tenant.id,
        local_id=payload.local_id,
        device_id=payload.device_id,
        source=_to_source(payload.source),
        timestamp=payload.timestamp,
        risk_percent=payload.risk_percent,
        frequency_hz=payload.frequency_hz,
        amplitude_mm=payload.amplitude_mm,
        risk_level=payload.risk_level,
        frame_count=payload.frame_count,
        duration_seconds=payload.duration_seconds,
        object_label=payload.object_label,
        material_id=payload.material_id,
        lat=payload.lat,
        lng=payload.lng,
        accuracy_m=payload.accuracy_m,
        magnetic_field_ut=payload.magnetic_field_ut,
        magnetic_anomaly=payload.magnetic_anomaly,
        prediction_a=payload.prediction_a,
        prediction_b=payload.prediction_b,
        prediction_c=payload.prediction_c,
        hours_to_critical=payload.hours_to_critical,
        hotspots=payload.hotspots,
        fusion_confidence=payload.fusion_confidence,
        raw_payload=payload.model_dump(mode="json"),
    )
    db.add(record)
    await db.commit()
    await db.refresh(record)
    return MeasurementOut(
        id=str(record.id),
        local_id=record.local_id,
        device_id=record.device_id,
        source=record.source.value,
        timestamp=record.timestamp,
        risk_percent=record.risk_percent,
        frequency_hz=record.frequency_hz,
        amplitude_mm=record.amplitude_mm,
        risk_level=record.risk_level,
        fusion_confidence=record.fusion_confidence,
        received_at=record.received_at,
    )


@router.get("", response_model=list[MeasurementOut])
async def list_measurements(
    request: Request,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    device_id: str | None = Query(None),
    limit: int = Query(50, ge=1, le=500),
):
    tenant: Tenant = request.state.tenant
    stmt = (
        select(MeasurementRecord)
        .where(MeasurementRecord.tenant_id == tenant.id)
        .order_by(desc(MeasurementRecord.received_at))
        .limit(limit)
    )
    if device_id:
        stmt = stmt.where(MeasurementRecord.device_id == device_id)
    rows = (await db.execute(stmt)).scalars().all()
    return [
        MeasurementOut(
            id=str(r.id),
            local_id=r.local_id,
            device_id=r.device_id,
            source=r.source.value,
            timestamp=r.timestamp,
            risk_percent=r.risk_percent,
            frequency_hz=r.frequency_hz,
            amplitude_mm=r.amplitude_mm,
            risk_level=r.risk_level,
            fusion_confidence=r.fusion_confidence,
            received_at=r.received_at,
        )
        for r in rows
    ]


@router.post("/analyze", response_model=PredictionOutput)
async def analyze_measurement(
    payload: PredictionInput,
    request: Request,
    user: User = Depends(get_current_user),
):
    tenant: Tenant = request.state.tenant
    analysis = analyze_signal(payload)
    await ws_manager.broadcast_to_tenant(
        tenant.id,
        {
            "kind": "analysis",
            "data": analysis.model_dump(mode="json"),
        },
    )
    return analysis


@router.get("/{measurement_id}", response_model=MeasurementOut)
async def get_measurement(
    measurement_id: UUID,
    request: Request,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    tenant: Tenant = request.state.tenant
    record = (
        await db.execute(
            select(MeasurementRecord).where(
                MeasurementRecord.id == measurement_id,
                MeasurementRecord.tenant_id == tenant.id,
            )
        )
    ).scalar_one_or_none()
    if record is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Measurement not found")
    return MeasurementOut(
        id=str(record.id),
        local_id=record.local_id,
        device_id=record.device_id,
        source=record.source.value,
        timestamp=record.timestamp,
        risk_percent=record.risk_percent,
        frequency_hz=record.frequency_hz,
        amplitude_mm=record.amplitude_mm,
        risk_level=record.risk_level,
        fusion_confidence=record.fusion_confidence,
        received_at=record.received_at,
    )
