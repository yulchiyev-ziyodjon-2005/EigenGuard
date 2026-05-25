"""Async SQLAlchemy 2.x engine + session factory + Base."""
from collections.abc import AsyncIterator

from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase
from sqlalchemy.sql import text

from .config import settings


engine = create_async_engine(
    settings.database_url,
    echo=settings.debug,
    pool_pre_ping=True,
    pool_size=10,
    max_overflow=20,
)

AsyncSessionLocal = async_sessionmaker(
    engine,
    expire_on_commit=False,
    class_=AsyncSession,
)


class Base(DeclarativeBase):
    """Base class for all SQLAlchemy models."""


async def get_db() -> AsyncIterator[AsyncSession]:
    """FastAPI dependency — yields an async session per request."""
    async with AsyncSessionLocal() as session:
        try:
            yield session
        except Exception:
            await session.rollback()
            raise


async def ensure_compat_schema() -> None:
    """Small startup migration until Alembic migrations are wired into dev flow."""
    async with engine.begin() as conn:
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS username VARCHAR(80)"))
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS role VARCHAR(30)"))
        await conn.execute(
            text(
                """
                WITH candidates AS (
                    SELECT
                        id,
                        COALESCE(
                            NULLIF(
                                trim(both '-' from lower(regexp_replace(split_part(email, '@', 1), '[^a-z0-9_-]+', '-', 'g'))),
                                ''
                            ),
                            'user'
                        ) AS base_username,
                        row_number() OVER (
                            PARTITION BY tenant_id, COALESCE(
                                NULLIF(
                                    trim(both '-' from lower(regexp_replace(split_part(email, '@', 1), '[^a-z0-9_-]+', '-', 'g'))),
                                    ''
                                ),
                                'user'
                            )
                            ORDER BY created_at, id
                        ) AS rn
                    FROM users
                    WHERE username IS NULL OR username = ''
                )
                UPDATE users AS u
                SET username = CASE
                    WHEN c.rn = 1 THEN c.base_username
                    ELSE c.base_username || '-' || c.rn::text
                END
                FROM candidates AS c
                WHERE u.id = c.id
                """
            )
        )
        await conn.execute(
            text(
                """
                UPDATE users AS u
                SET role = CASE
                    WHEN u.role IS NOT NULL AND u.role <> '' THEN u.role
                    WHEN t.deployment_mode = 'superadmin' AND u.is_admin IS TRUE THEN 'superadmin'
                    WHEN u.is_admin IS TRUE THEN 'tenant_admin'
                    ELSE 'engineer'
                END
                FROM tenants AS t
                WHERE u.tenant_id = t.id
                """
            )
        )
        await conn.execute(text("ALTER TABLE users ALTER COLUMN username SET NOT NULL"))
        await conn.execute(text("ALTER TABLE users ALTER COLUMN role SET NOT NULL"))
        await conn.execute(
            text(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS uq_users_tenant_username
                ON users (tenant_id, username)
                """
            )
        )
