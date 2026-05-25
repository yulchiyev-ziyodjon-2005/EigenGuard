"""In-memory WebSocket connection manager — mobile devices ↔ server."""
from __future__ import annotations

import asyncio
import json
import logging
from typing import Any
from uuid import UUID

from fastapi import WebSocket

log = logging.getLogger("nexus.ws")


class WSManager:
    """Singleton: device_id → WebSocket connection map.

    Single-worker setup (MVP). For multi-worker scale, replace internal dict
    with Redis pub/sub channel.
    """

    def __init__(self) -> None:
        self._conns: dict[UUID, WebSocket] = {}
        self._dashboard_conns: dict[UUID, set[WebSocket]] = {}
        self._lock = asyncio.Lock()

    async def connect(self, device_id: UUID, ws: WebSocket) -> None:
        async with self._lock:
            existing = self._conns.get(device_id)
            if existing is not None:
                try:
                    await existing.close(code=1000, reason="superseded")
                except Exception:
                    pass
            self._conns[device_id] = ws
        log.info("WS connected device=%s (total=%d)", device_id, len(self._conns))

    async def disconnect(self, device_id: UUID) -> None:
        async with self._lock:
            self._conns.pop(device_id, None)
        log.info("WS disconnected device=%s (total=%d)", device_id, len(self._conns))

    def is_connected(self, device_id: UUID) -> bool:
        return device_id in self._conns

    async def send(self, device_id: UUID, message: dict[str, Any]) -> bool:
        """Send JSON message to device. Returns False if not connected or send failed."""
        ws = self._conns.get(device_id)
        if ws is None:
            return False
        try:
            await ws.send_text(json.dumps(message))
            return True
        except Exception as exc:
            log.warning("WS send failed device=%s: %s", device_id, exc)
            await self.disconnect(device_id)
            return False

    def connected_device_ids(self) -> list[UUID]:
        return list(self._conns.keys())

    async def connect_dashboard(self, tenant_id: UUID, ws: WebSocket) -> None:
        async with self._lock:
            self._dashboard_conns.setdefault(tenant_id, set()).add(ws)
        log.info(
            "Dashboard WS connected tenant=%s (total=%d)",
            tenant_id,
            len(self._dashboard_conns.get(tenant_id, set())),
        )

    async def disconnect_dashboard(self, tenant_id: UUID, ws: WebSocket) -> None:
        async with self._lock:
            conns = self._dashboard_conns.get(tenant_id)
            if conns is not None:
                conns.discard(ws)
                if not conns:
                    self._dashboard_conns.pop(tenant_id, None)
        log.info(
            "Dashboard WS disconnected tenant=%s (total=%d)",
            tenant_id,
            len(self._dashboard_conns.get(tenant_id, set())),
        )

    async def broadcast_to_tenant(
        self, tenant_id: UUID, message: dict[str, Any]
    ) -> int:
        """Broadcast JSON to all dashboard sockets for a tenant."""
        conns = list(self._dashboard_conns.get(tenant_id, set()))
        if not conns:
            return 0

        sent = 0
        stale: list[WebSocket] = []
        encoded = json.dumps(message)
        for ws in conns:
            try:
                await ws.send_text(encoded)
                sent += 1
            except Exception as exc:
                log.warning("Dashboard WS send failed tenant=%s: %s", tenant_id, exc)
                stale.append(ws)

        if stale:
            async with self._lock:
                active = self._dashboard_conns.get(tenant_id)
                if active is not None:
                    for ws in stale:
                        active.discard(ws)
                    if not active:
                        self._dashboard_conns.pop(tenant_id, None)
        return sent


ws_manager = WSManager()
