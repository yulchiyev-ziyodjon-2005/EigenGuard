"""Devices REST API — list, register, view detail."""
from __future__ import annotations

from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel
from sqlalchemy import desc, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..core.database import get_db
from ..core.deps import get_current_user
from ..core.ws_manager import ws_manager
from ..models.device import Device
from ..models.measurement import MeasurementRecord
from ..models.tenant import Tenant
from ..models.user import User

router = APIRouter(prefix="/api/v1/devices", tags=["devices"])


class DeviceOut(BaseModel):
    id: str
    device_identifier: str
    platform: str
    device_name: str | None
    user_id: str | None
    is_active: bool
    is_online: bool  # WebSocket holatda ulanganmi
    measurement_count: int
    last_seen_at: datetime
    last_risk_percent: float | None = None
    last_risk_level: str | None = None
    last_source: str | None = None
    created_at: datetime


class DeviceRegister(BaseModel):
    device_identifier: str
    platform: str = "android"
    device_name: str | None = None
    push_token: str | None = None
    app_version: str | None = None


@router.get("", response_model=list[DeviceOut])
async def list_devices(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
):
    tenant: Tenant = request.state.tenant
    devices = (
        await db.execute(
            select(Device)
            .where(Device.tenant_id == tenant.id)
            .order_by(desc(Device.last_seen_at))
        )
    ).scalars().all()

    out: list[DeviceOut] = []
    for d in devices:
        mc = (
            await db.execute(
                select(func.count(MeasurementRecord.id)).where(
                    MeasurementRecord.tenant_id == tenant.id,
                    MeasurementRecord.device_id == d.device_identifier,
                )
            )
        ).scalar_one()
        last = (
            await db.execute(
                select(MeasurementRecord)
                .where(
                    MeasurementRecord.tenant_id == tenant.id,
                    MeasurementRecord.device_id == d.device_identifier,
                )
                .order_by(desc(MeasurementRecord.received_at))
                .limit(1)
            )
        ).scalar_one_or_none()
        out.append(
            DeviceOut(
                id=str(d.id),
                device_identifier=d.device_identifier,
                platform=d.platform,
                device_name=d.device_name,
                user_id=str(d.user_id) if d.user_id else None,
                is_active=d.is_active,
                is_online=ws_manager.is_connected(d.id),
                measurement_count=mc,
                last_seen_at=d.last_seen_at,
                last_risk_percent=last.risk_percent if last else None,
                last_risk_level=last.risk_level if last else None,
                last_source=last.source.value if last else None,
                created_at=d.created_at,
            )
        )
    return out


@router.post("/register", status_code=status.HTTP_201_CREATED, response_model=DeviceOut)
async def register_device(
    payload: DeviceRegister,
    request: Request,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Mobile birinchi marta launch'da chaqiradi — yoki upsert."""
    tenant: Tenant = request.state.tenant
    device = (
        await db.execute(
            select(Device).where(
                Device.tenant_id == tenant.id,
                Device.device_identifier == payload.device_identifier,
            )
        )
    ).scalar_one_or_none()
    if device is None:
        device = Device(
            tenant_id=tenant.id,
            user_id=user.id,
            device_identifier=payload.device_identifier,
            platform=payload.platform,
            device_name=payload.device_name,
            push_token=payload.push_token,
            app_version=payload.app_version,
        )
        db.add(device)
    else:
        device.user_id = user.id
        device.platform = payload.platform
        if payload.device_name:
            device.device_name = payload.device_name
        if payload.push_token:
            device.push_token = payload.push_token
        if payload.app_version:
            device.app_version = payload.app_version
        from datetime import timezone as _tz
        device.last_seen_at = datetime.now(_tz.utc)
        device.is_active = True
    await db.commit()
    await db.refresh(device)
    return DeviceOut(
        id=str(device.id),
        device_identifier=device.device_identifier,
        platform=device.platform,
        device_name=device.device_name,
        user_id=str(device.user_id) if device.user_id else None,
        is_active=device.is_active,
        is_online=ws_manager.is_connected(device.id),
        measurement_count=0,
        last_seen_at=device.last_seen_at,
        created_at=device.created_at,
    )


@router.delete("/{device_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_device(
    device_id: UUID,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
):
    tenant: Tenant = request.state.tenant
    device = (
        await db.execute(
            select(Device).where(Device.id == device_id, Device.tenant_id == tenant.id)
        )
    ).scalar_one_or_none()
    if device is None:
        raise HTTPException(404, "Device not found")
    await db.delete(device)
    await db.commit()
