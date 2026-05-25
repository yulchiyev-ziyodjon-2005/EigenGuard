"""EigenGuard Nexus — Pure REST + WebSocket API (Vue SPA frontend alohida)."""
from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .api import audit_logs as audit_logs_router
from .api import auth as auth_router
from .api import commands as commands_router
from .api import devices as devices_router
from .api import licenses as licenses_router
from .api import measurements as measurements_router
from .api import tenants as tenants_router
from .api import users as users_router
from .api import ws as ws_router
from .core.config import settings
from .core.database import Base, engine, ensure_compat_schema
from .core.license import periodic_license_check
from .middleware.tenant import tenant_middleware

logging.basicConfig(
    level=logging.DEBUG if settings.debug else logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
)
log = logging.getLogger("nexus")


@asynccontextmanager
async def lifespan(app: FastAPI):
    log.info(
        "Nexus starting — env=%s, mode=%s",
        settings.environment,
        settings.deployment_mode,
    )
    # TEMP: auto-create tables. Sprint 18'da Alembic migration'lariga o'tiladi.
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    await ensure_compat_schema()

    license_task = asyncio.create_task(periodic_license_check(), name="license_check")

    try:
        yield
    finally:
        license_task.cancel()
        try:
            await license_task
        except asyncio.CancelledError:
            pass
        await engine.dispose()
        log.info("Nexus shutdown complete")


app = FastAPI(
    title="EigenGuard Nexus",
    description=(
        "Hybrid B2G SaaS Command Center — cloud multi-tenant + on-premise + "
        "air-gapped. Mobile WebSocket + REST API for the Vue 3 SPA frontend."
    ),
    version="0.2.0",
    lifespan=lifespan,
)

# ── CORS ──────────────────────────────────────────────────────────────
# Dev: SPA frontend localhost:5173 (Vite) ham talab qiladi credentials.
# Production: tenant subdomain'lari ro'yxati env orqali konfiguratsiya qilinadi.
_cors_origins = (
    [
        "http://localhost:5173",
        "http://localhost:8080",
        "http://127.0.0.1:5173",
        "http://127.0.0.1:8080",
    ]
    if settings.environment == "development"
    else []
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["X-EigenGuard-Tenant"],
)

# ── Tenant resolution middleware ──────────────────────────────────────
app.middleware("http")(tenant_middleware)

# ── Routers ───────────────────────────────────────────────────────────
app.include_router(auth_router.router)
app.include_router(tenants_router.router)
app.include_router(licenses_router.router)
app.include_router(audit_logs_router.router)
app.include_router(users_router.router)
app.include_router(devices_router.router)
app.include_router(measurements_router.router)
app.include_router(commands_router.router)
app.include_router(ws_router.router)


@app.get("/")
async def root() -> dict:
    """Service info — no tenant required."""
    return {
        "name": "EigenGuard Nexus",
        "version": "0.2.0",
        "environment": settings.environment,
        "deployment_mode": settings.deployment_mode,
        "docs": "/docs",
    }


@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}
