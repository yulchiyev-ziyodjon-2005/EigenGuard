"""Mobile WebSocket endpoint — bidirectional real-time channel.

Mobile connects with: ws://nexus/api/v1/ws/mobile?token=<JWT>&device_id=<hw_id>

Server:
  - authenticates JWT
  - registers/upserts Device in DB
  - registers WebSocket in ws_manager
  - delivers any pending commands immediately
  - keeps connection open; pushes new commands as they're issued

Mobile:
  - receives commands via {"kind":"command","data":{...}}
  - sends acks via {"kind":"ack","command_id":"...","success":true,...}
  - sends heartbeats {"kind":"ping"} — server replies {"kind":"pong"}
"""
from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Query, WebSocket, WebSocketDisconnect, status
from sqlalchemy import select

from ..core.database import AsyncSessionLocal
from ..core.security import decode_jwt
from ..core.ws_manager import ws_manager
from ..models.command import Command, CommandStatus
from ..models.device import Device
from ..models.tenant import Tenant
from ..models.user import User

log = logging.getLogger("nexus.ws")

router = APIRouter(tags=["websocket"])


@router.websocket("/api/v1/ws/dashboard")
async def dashboard_ws(
    websocket: WebSocket,
    token: str | None = Query(None),
):
    raw_token = token or websocket.cookies.get("access_token")
    if not raw_token:
        await websocket.close(
            code=status.WS_1008_POLICY_VIOLATION,
            reason="Missing token",
        )
        return

    payload = decode_jwt(raw_token)
    if not payload:
        await websocket.close(
            code=status.WS_1008_POLICY_VIOLATION,
            reason="Invalid token",
        )
        return
    try:
        user_id = UUID(payload["sub"])
        tenant_id = UUID(payload["tenant_id"])
    except (KeyError, ValueError):
        await websocket.close(
            code=status.WS_1008_POLICY_VIOLATION,
            reason="Malformed token",
        )
        return

    async with AsyncSessionLocal() as session:
        tenant = (
            await session.execute(select(Tenant).where(Tenant.id == tenant_id))
        ).scalar_one_or_none()
        user = (
            await session.execute(select(User).where(User.id == user_id))
        ).scalar_one_or_none()
        if tenant is None or not tenant.is_active:
            await websocket.close(
                code=status.WS_1008_POLICY_VIOLATION,
                reason="Tenant inactive",
            )
            return
        if user is None or not user.is_active or user.tenant_id != tenant_id:
            await websocket.close(
                code=status.WS_1008_POLICY_VIOLATION,
                reason="User invalid",
            )
            return

    await websocket.accept()
    await ws_manager.connect_dashboard(tenant_id, websocket)
    try:
        await websocket.send_text(
            json.dumps(
                {
                    "kind": "hello",
                    "channel": "dashboard",
                    "tenant": tenant.subdomain,
                }
            )
        )
        while True:
            raw = await asyncio.wait_for(websocket.receive_text(), timeout=120.0)
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if msg.get("kind") == "ping":
                await websocket.send_text(json.dumps({"kind": "pong"}))
    except (WebSocketDisconnect, asyncio.TimeoutError):
        pass
    except Exception as exc:
        log.warning("Dashboard WS loop error tenant=%s: %s", tenant_id, exc)
    finally:
        await ws_manager.disconnect_dashboard(tenant_id, websocket)


@router.websocket("/api/v1/ws/mobile")
async def mobile_ws(
    websocket: WebSocket,
    token: str = Query(...),
    device_identifier: str = Query(...),
    platform: str = Query("android"),
    device_name: str | None = Query(None),
):
    # 1) JWT auth
    payload = decode_jwt(token)
    if not payload:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="Invalid token")
        return
    try:
        user_id = UUID(payload["sub"])
        tenant_id = UUID(payload["tenant_id"])
    except (KeyError, ValueError):
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="Malformed token")
        return

    # 2) Verify tenant + user + register/upsert device
    async with AsyncSessionLocal() as session:
        tenant = (
            await session.execute(select(Tenant).where(Tenant.id == tenant_id))
        ).scalar_one_or_none()
        if tenant is None or not tenant.is_active:
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="Tenant inactive")
            return
        user = (
            await session.execute(select(User).where(User.id == user_id))
        ).scalar_one_or_none()
        if user is None or not user.is_active or user.tenant_id != tenant_id:
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="User invalid")
            return

        # Upsert device
        device = (
            await session.execute(
                select(Device).where(
                    Device.tenant_id == tenant_id,
                    Device.device_identifier == device_identifier,
                )
            )
        ).scalar_one_or_none()
        if device is None:
            device = Device(
                tenant_id=tenant_id,
                user_id=user_id,
                device_identifier=device_identifier,
                platform=platform,
                device_name=device_name,
            )
            session.add(device)
        else:
            device.user_id = user_id
            device.platform = platform
            if device_name:
                device.device_name = device_name
            device.last_seen_at = datetime.now(timezone.utc)
            device.is_active = True
        await session.commit()
        await session.refresh(device)
        device_db_id = device.id

    # 3) Accept + register
    await websocket.accept()
    await ws_manager.connect(device_db_id, websocket)

    # 4) Push any pending commands
    async with AsyncSessionLocal() as session:
        pending = (
            await session.execute(
                select(Command)
                .where(
                    Command.tenant_id == tenant_id,
                    Command.device_id == device_db_id,
                    Command.status == CommandStatus.pending,
                )
                .order_by(Command.created_at)
            )
        ).scalars().all()
        for cmd in pending:
            try:
                await websocket.send_text(
                    json.dumps({"kind": "command", "data": cmd.to_wire()})
                )
                cmd.status = CommandStatus.delivered
                cmd.delivered_at = datetime.now(timezone.utc)
            except Exception:
                break
        await session.commit()

    # 5) Welcome
    try:
        await websocket.send_text(
            json.dumps({
                "kind": "hello",
                "device_id": str(device_db_id),
                "tenant": tenant.subdomain,
                "pending_count": len(pending),
            })
        )
    except Exception:
        pass

    # 6) Listen for ack / ping
    try:
        while True:
            raw = await asyncio.wait_for(websocket.receive_text(), timeout=120.0)
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                continue
            kind = msg.get("kind")
            if kind == "ping":
                await websocket.send_text(json.dumps({"kind": "pong"}))
            elif kind == "ack":
                cmd_id_raw = msg.get("command_id")
                if not cmd_id_raw:
                    continue
                try:
                    cmd_id = UUID(cmd_id_raw)
                except ValueError:
                    continue
                async with AsyncSessionLocal() as session:
                    cmd = (
                        await session.execute(
                            select(Command).where(
                                Command.id == cmd_id,
                                Command.tenant_id == tenant_id,
                            )
                        )
                    ).scalar_one_or_none()
                    if cmd is None:
                        continue
                    success = msg.get("success", True)
                    cmd.status = (
                        CommandStatus.acknowledged
                        if success
                        else CommandStatus.failed
                    )
                    cmd.acknowledged_at = datetime.now(timezone.utc)
                    cmd.error_message = msg.get("error_message")
                    cmd.result_payload = msg.get("result")
                    await session.commit()
    except (WebSocketDisconnect, asyncio.TimeoutError):
        pass
    except Exception as exc:
        log.warning("WS loop error device=%s: %s", device_db_id, exc)
    finally:
        await ws_manager.disconnect(device_db_id)
