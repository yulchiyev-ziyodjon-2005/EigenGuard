"""Tenant resolution middleware.

Resolves the active tenant for every request:

1. **Cloud (subdomain-based)**: `clientA.eigenguard.uz` → looks up Tenant
   where `subdomain == "clientA"`.

2. **On-premise / API client (header-based)**: `X-EigenGuard-Tenant: clientA`
   header — used when DNS isn't configured for subdomains.

3. **On-premise single-tenant fallback**: if neither subdomain nor header is
   present AND `DEPLOYMENT_MODE` is `on_premise` or `air_gapped`, resolves to
   tenant with `subdomain == "default"`.

Resolved tenant is attached to `request.state.tenant` for downstream handlers.

Public paths (`/`, `/health`, `/docs`, etc.) bypass tenant resolution.
"""
from __future__ import annotations

import logging
from typing import Awaitable, Callable

from fastapi import HTTPException, Request, Response, status
from sqlalchemy import select

from ..core.config import settings
from ..core.database import AsyncSessionLocal
from ..models.tenant import Tenant

log = logging.getLogger("nexus.middleware.tenant")

# Paths that don't require tenant resolution
PUBLIC_PATHS: set[str] = {
    "/",
    "/health",
    "/healthz",
    "/docs",
    "/redoc",
    "/openapi.json",
    "/favicon.ico",
    "/api/v1/auth/login",
    "/api/v1/auth/superadmin/login",
    "/api/v1/auth/logout",
    "/api/v1/auth/me",
    "/api/v1/license/validate",  # Superadmin endpoint (called by other Nexus instances)
}
# WS handles its own auth (JWT in query string), tenant resolution skipped
PUBLIC_PREFIXES: tuple[str, ...] = ("/static/", "/api/v1/ws/")


def _extract_subdomain(host: str | None) -> str | None:
    """Strip port + root domain, return leftmost label as subdomain."""
    if not host:
        return None
    host = host.split(":", 1)[0].lower()
    root = settings.tenant_subdomain_root.lower()
    if not host.endswith(root) or host == root:
        return None
    prefix = host[: -len(root) - 1]
    if not prefix:
        return None
    # Multi-level subdomain — take leftmost label
    return prefix.split(".")[0]


async def tenant_middleware(
    request: Request, call_next: Callable[[Request], Awaitable[Response]]
) -> Response:
    path = request.url.path
    if path in PUBLIC_PATHS or any(path.startswith(p) for p in PUBLIC_PREFIXES):
        return await call_next(request)

    # 1) Try subdomain (cloud routing)
    subdomain = _extract_subdomain(request.headers.get("host"))
    # 2) Try explicit header (on-premise / API clients / SPA frontend)
    header_tenant = request.headers.get(settings.tenant_header, "").strip().lower()
    tenant_key = subdomain or header_tenant or None

    # 3) Fallback'lar
    if tenant_key is None:
        if settings.deployment_mode in ("on_premise", "air_gapped"):
            tenant_key = "default"
        elif settings.environment == "development":
            # Dev'da localhost:8000 → superadmin tenant ga tushadi
            tenant_key = "superadmin"

    if tenant_key is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                "Tenant not specified — use subdomain "
                f"(e.g. clientA.{settings.tenant_subdomain_root}) "
                f"or '{settings.tenant_header}' header."
            ),
        )

    # Resolve from DB
    async with AsyncSessionLocal() as session:
        result = await session.execute(
            select(Tenant).where(Tenant.subdomain == tenant_key)
        )
        tenant = result.scalar_one_or_none()
        if tenant is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Tenant '{tenant_key}' not found",
            )
        if not tenant.is_active:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Tenant '{tenant_key}' is inactive",
            )

    request.state.tenant = tenant
    return await call_next(request)
