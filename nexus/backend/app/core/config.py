"""Application settings — loaded from environment / .env."""
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """All runtime configuration. Override via env vars or .env file."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    # Deployment
    environment: str = "development"
    deployment_mode: str = "cloud"  # cloud | on_premise | air_gapped
    debug: bool = False

    # Database + cache
    database_url: str
    redis_url: str = "redis://redis:6379/0"

    # Auth (JWT — wired in next sprint; placeholder secret here)
    jwt_secret: str
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 60 * 24

    # Multi-tenant routing
    tenant_subdomain_root: str = "eigenguard.uz"
    tenant_header: str = "X-EigenGuard-Tenant"

    # License validation
    superadmin_license_server: str = "https://license.eigenguard.uz"
    license_public_key_path: str = "/app/keys/superadmin_public.pem"
    license_check_interval_hours: int = 24
    license_grace_period_days: int = 7


settings = Settings()
