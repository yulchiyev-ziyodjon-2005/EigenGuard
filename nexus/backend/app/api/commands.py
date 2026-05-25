"""Commands API — tenant admin telefonga buyruq yuboradi.

Flow:
  1. Admin POST /api/v1/commands {device_id, command_type, payload}
  2. Server saves command (status=pending)
  3. Server tries WebSocket delivery; if delivered → status=delivered
  4. Mobile executes command → POST /api/v1/commands/{id}/ack {result}
  5. Mobile periodically GET /api/v1/commands/pending on app start / reconnect
"""
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
from ..models.command import Command, CommandStatus, CommandType
from ..models.device import Device
from ..models.tenant import Tenant
from ..models.user import User

router = APIRouter(prefix="/api/v1/commands", tags=["commands"])


class CommandOut(BaseModel):
    id: str
    device_id: str
    command_type: str
    payload: dict[str, Any] | None
    status: str
    error_message: str | None
    result_payload: dict[str, Any] | None
    created_at: datetime
    delivered_at: datetime | None
    acknowledged_at: datetime | None
    expires_at: datetime


class CommandCreate(BaseModel):
    device_id: UUID
    command_type: str
    payload: dict[str, Any] | None = None
    ttl_hours: int = Field(default=24, ge=1, le=720)


class CommandAck(BaseModel):
    success: bool = True
    error_message: str | None = None
    result_payload: dict[str, Any] | None = None


def _ser(c: Command) -> CommandOut:
    return CommandOut(
        id=str(c.id),
        device_id=str(c.device_id),
        command_type=c.command_type.value,
        payload=c.payload,
        status=c.status.value,
        error_message=c.error_message,
        result_payload=c.result_payload,
        created_at=c.created_at,
        delivered_at=c.delivered_at,
        acknowledged_at=c.acknowledged_at,
        expires_at=c.expires_at,
    )


def _parse_type(value: str) -> CommandType:
    try:
        return CommandType(value)
    except ValueError:
        raise HTTPException(400, f"Unknown command_type: {value}")


@router.post("", status_code=status.HTTP_201_CREATED, response_model=CommandOut)
async def create_command(
    payload: CommandCreate,
    request: Request,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    tenant: Tenant = request.state.tenant
    # Verify device belongs to this tenant
    device = (
        await db.execute(
            select(Device).where(
                Device.id == payload.device_id,
                Device.tenant_id == tenant.id,
                Device.is_active.is_(True),
            )
        )
    ).scalar_one_or_none()
    if device is None:
        raise HTTPException(404, "Device not found in this tenant")

    from datetime import timedelta

    cmd = Command(
        tenant_id=tenant.id,
        device_id=device.id,
        issued_by_user_id=user.id,
        command_type=_parse_type(payload.command_type),
        payload=payload.payload,
        status=CommandStatus.pending,
        expires_at=datetime.now(timezone.utc) + timedelta(hours=payload.ttl_hours),
    )
    db.add(cmd)
    await db.commit()
    await db.refresh(cmd)

    # Try immediate WebSocket delivery
    delivered = await ws_manager.send(device.id, {"kind": "command", "data": cmd.to_wire()})
    if delivered:
        cmd.status = CommandStatus.delivered
        cmd.delivered_at = datetime.now(timezone.utc)
        await db.commit()
        await db.refresh(cmd)

    return _ser(cmd)


@router.get("", response_model=list[CommandOut])
async def list_commands(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
    device_id: UUID | None = Query(None),
    status_filter: str | None = Query(None, alias="status"),
    limit: int = Query(50, ge=1, le=500),
):
    tenant: Tenant = request.state.tenant
    stmt = (
        select(Command)
        .where(Command.tenant_id == tenant.id)
        .order_by(desc(Command.created_at))
        .limit(limit)
    )
    if device_id:
        stmt = stmt.where(Command.device_id == device_id)
    if status_filter:
        try:
            stmt = stmt.where(Command.status == CommandStatus(status_filter))
        except ValueError:
            raise HTTPException(400, f"Invalid status: {status_filter}")
    rows = (await db.execute(stmt)).scalars().all()
    return [_ser(c) for c in rows]


@router.get("/pending", response_model=list[CommandOut])
async def get_pending_for_my_device(
    request: Request,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    device_identifier: str = Query(..., description="Mobile's hardware identifier"),
):
    """Mobile boot/reconnect time: get queued commands for this device."""
    tenant: Tenant = request.state.tenant
    device = (
        await db.execute(
            select(Device).where(
                Device.tenant_id == tenant.id,
                Device.device_identifier == device_identifier,
            )
        )
    ).scalar_one_or_none()
    if device is None:
        return []
    rows = (
        await db.execute(
            select(Command)
            .where(
                Command.tenant_id == tenant.id,
                Command.device_id == device.id,
                Command.status == CommandStatus.pending,
            )
            .order_by(Command.created_at)
        )
    ).scalars().all()
    return [_ser(c) for c in rows]


@router.post("/{command_id}/ack", response_model=CommandOut)
async def acknowledge_command(
    command_id: UUID,
    payload: CommandAck,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
):
    """Mobile bajarilganini bildiradi."""
    tenant: Tenant = request.state.tenant
    cmd = (
        await db.execute(
            select(Command).where(
                Command.id == command_id, Command.tenant_id == tenant.id
            )
        )
    ).scalar_one_or_none()
    if cmd is None:
        raise HTTPException(404, "Command not found")
    if cmd.status in (CommandStatus.acknowledged, CommandStatus.expired):
        return _ser(cmd)
    cmd.status = (
        CommandStatus.acknowledged if payload.success else CommandStatus.failed
    )
    cmd.acknowledged_at = datetime.now(timezone.utc)
    cmd.error_message = payload.error_message
    cmd.result_payload = payload.result_payload
    await db.commit()
    await db.refresh(cmd)
    return _ser(cmd)
