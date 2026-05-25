"""Seed script — bootstrap superadmin tenant + sample tenant + users.

Foydalanish:
    docker compose exec backend python -m scripts.seed
    # yoki lokal:
    python -m scripts.seed
"""
from __future__ import annotations

import asyncio
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import uuid4

# Make sure `app.*` is importable when run as `python -m scripts.seed`
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import select  # noqa: E402

from app.core.database import AsyncSessionLocal, Base, engine, ensure_compat_schema  # noqa: E402
from app.core.security import hash_password  # noqa: E402
from app.models.license import License  # noqa: E402
from app.models.tenant import DeploymentMode, Tenant  # noqa: E402
from app.models.user import User, UserRole  # noqa: E402


SUPERADMIN_EMAIL = os.getenv("SEED_SUPERADMIN_EMAIL", "admin@eigenguard.uz")
SUPERADMIN_USERNAME = os.getenv("SEED_SUPERADMIN_USERNAME", "superadmin")
SUPERADMIN_PASSWORD = os.getenv("SEED_SUPERADMIN_PASSWORD", "ChangeMe123!")

SAMPLE_TENANT_SUBDOMAIN = os.getenv("SEED_TENANT_SUBDOMAIN", "demo")
SAMPLE_TENANT_NAME = os.getenv("SEED_TENANT_NAME", "Demo Tenant (Toshkent Issiqlik)")
SAMPLE_ADMIN_EMAIL = os.getenv("SEED_TENANT_ADMIN_EMAIL", "admin@demo.local")
SAMPLE_ADMIN_USERNAME = os.getenv("SEED_TENANT_ADMIN_USERNAME", "demo-admin")
SAMPLE_ADMIN_PASSWORD = os.getenv("SEED_TENANT_ADMIN_PASSWORD", "DemoAdmin123!")
SAMPLE_FIELD_EMAIL = os.getenv("SEED_TENANT_FIELD_EMAIL", "engineer@demo.local")
SAMPLE_FIELD_USERNAME = os.getenv("SEED_TENANT_FIELD_USERNAME", "demo-engineer")
SAMPLE_FIELD_PASSWORD = os.getenv("SEED_TENANT_FIELD_PASSWORD", "Engineer123!")


async def _upsert_tenant(session, subdomain, name, mode) -> Tenant:
    existing = (
        await session.execute(select(Tenant).where(Tenant.subdomain == subdomain))
    ).scalar_one_or_none()
    if existing:
        return existing
    t = Tenant(name=name, subdomain=subdomain, deployment_mode=mode, is_active=True)
    session.add(t)
    await session.flush()
    return t


async def _upsert_user(
    session, tenant_id, username, email, password, full_name, role
) -> User:
    existing = (
        await session.execute(
            select(User).where(User.tenant_id == tenant_id, User.email == email)
        )
    ).scalar_one_or_none()
    if existing:
        if not existing.username:
            existing.username = username
        existing.role = role
        existing.is_admin = role in (UserRole.superadmin.value, UserRole.tenant_admin.value)
        return existing
    u = User(
        tenant_id=tenant_id,
        username=username,
        email=email,
        password_hash=hash_password(password),
        full_name=full_name,
        role=role,
        is_admin=role in (UserRole.superadmin.value, UserRole.tenant_admin.value),
        is_active=True,
    )
    session.add(u)
    await session.flush()
    return u


async def _ensure_license(session, tenant_id) -> License:
    existing = (
        await session.execute(select(License).where(License.tenant_id == tenant_id).limit(1))
    ).scalar_one_or_none()
    if existing:
        return existing
    lic = License(
        tenant_id=tenant_id,
        key=uuid4().hex + uuid4().hex,
        issued_at=datetime.now(timezone.utc),
        expires_at=datetime.now(timezone.utc) + timedelta(days=365),
        max_devices=100,
        max_users=20,
        features={"custom_ai": False, "multi_site": False, "alert_routing": True},
    )
    session.add(lic)
    await session.flush()
    return lic


async def main() -> None:
    # 1) Tables
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    await ensure_compat_schema()

    async with AsyncSessionLocal() as session:
        # 2) Superadmin tenant + admin
        sa_tenant = await _upsert_tenant(
            session,
            subdomain="superadmin",
            name="EigenGuard Superadmin",
            mode=DeploymentMode.superadmin,
        )
        sa_admin = await _upsert_user(
            session,
            tenant_id=sa_tenant.id,
            username=SUPERADMIN_USERNAME,
            email=SUPERADMIN_EMAIL,
            password=SUPERADMIN_PASSWORD,
            full_name="Superadmin",
            role=UserRole.superadmin.value,
        )

        # 3) Sample tenant + admin + field engineer
        demo_tenant = await _upsert_tenant(
            session,
            subdomain=SAMPLE_TENANT_SUBDOMAIN,
            name=SAMPLE_TENANT_NAME,
            mode=DeploymentMode.cloud,
        )
        demo_admin = await _upsert_user(
            session,
            tenant_id=demo_tenant.id,
            username=SAMPLE_ADMIN_USERNAME,
            email=SAMPLE_ADMIN_EMAIL,
            password=SAMPLE_ADMIN_PASSWORD,
            full_name="Demo Tenant Admin",
            role=UserRole.tenant_admin.value,
        )
        demo_field = await _upsert_user(
            session,
            tenant_id=demo_tenant.id,
            username=SAMPLE_FIELD_USERNAME,
            email=SAMPLE_FIELD_EMAIL,
            password=SAMPLE_FIELD_PASSWORD,
            full_name="Field Engineer #1",
            role=UserRole.engineer.value,
        )
        await _ensure_license(session, demo_tenant.id)

        await session.commit()

    print("\n" + "=" * 64)
    print("  EigenGuard Nexus — Seed muvaffaqiyatli")
    print("=" * 64)
    print(f"\n  SUPERADMIN (https://superadmin.{os.getenv('TENANT_SUBDOMAIN_ROOT','eigenguard.uz')})")
    print(f"    Username: {SUPERADMIN_USERNAME}")
    print(f"    Email:    {SUPERADMIN_EMAIL}")
    print(f"    Password: {SUPERADMIN_PASSWORD}")
    print(f"\n  TENANT '{SAMPLE_TENANT_SUBDOMAIN}' (admin)")
    print(f"    Username: {SAMPLE_ADMIN_USERNAME}")
    print(f"    Email:    {SAMPLE_ADMIN_EMAIL}")
    print(f"    Password: {SAMPLE_ADMIN_PASSWORD}")
    print(f"\n  TENANT '{SAMPLE_TENANT_SUBDOMAIN}' (mobile field engineer)")
    print(f"    Username: {SAMPLE_FIELD_USERNAME}")
    print(f"    Email:    {SAMPLE_FIELD_EMAIL}")
    print(f"    Password: {SAMPLE_FIELD_PASSWORD}")
    print("\n  Login tenant header talab qilmaydi; tizim user credential orqali tenant/rolni aniqlaydi.")
    print("=" * 64 + "\n")


if __name__ == "__main__":
    asyncio.run(main())
