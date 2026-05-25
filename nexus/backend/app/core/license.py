"""License validation — hybrid cloud + on-premise + air-gapped.

Three modes (decided by `settings.deployment_mode`):
  * cloud / on_premise  → periodic HTTPS POST to Superadmin license server
  * air_gapped          → offline Ed25519 signature verification against bundled public key

A background task (started in main.py lifespan) re-checks every active license
once per `license_check_interval_hours`. If validation fails for longer than
`license_grace_period_days`, the license is marked revoked → tenant goes
read-only / degraded.
"""
from __future__ import annotations

import asyncio
import base64
import json
import logging
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import httpx
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from sqlalchemy import select

from ..models.license import License
from .config import settings
from .database import AsyncSessionLocal

log = logging.getLogger("nexus.license")

_public_key_cache: Ed25519PublicKey | None = None


def _load_public_key() -> Ed25519PublicKey | None:
    """Load + cache Superadmin's Ed25519 public key (air-gapped offline verify)."""
    global _public_key_cache
    if _public_key_cache is not None:
        return _public_key_cache
    path = Path(settings.license_public_key_path)
    if not path.exists():
        log.warning("Superadmin public key not found at %s", path)
        return None
    try:
        pem = path.read_bytes()
        key = serialization.load_pem_public_key(pem)
        if isinstance(key, Ed25519PublicKey):
            _public_key_cache = key
            return key
        log.error("Public key at %s is not Ed25519", path)
    except Exception as exc:
        log.error("Failed to load public key: %s", exc)
    return None


def verify_offline_certificate(
    license_key: str, certificate: str
) -> dict[str, Any] | None:
    """Validate an Ed25519-signed cert (format: ``<payload_b64>.<signature_b64>``).

    Returns the decoded payload dict if valid, else None.
    """
    key = _load_public_key()
    if key is None or not certificate:
        return None
    try:
        payload_b64, sig_b64 = certificate.split(".", 1)
        payload = base64.urlsafe_b64decode(payload_b64.encode() + b"==")
        signature = base64.urlsafe_b64decode(sig_b64.encode() + b"==")
        key.verify(signature, payload)
        data = json.loads(payload)
        if data.get("license_key") != license_key:
            log.warning("Cert payload license_key mismatch")
            return None
        # Expiry check (cert payload should carry its own expiry)
        exp_iso = data.get("expires_at")
        if exp_iso:
            try:
                exp = datetime.fromisoformat(exp_iso.replace("Z", "+00:00"))
                if datetime.now(timezone.utc) >= exp:
                    log.warning("Cert payload expired at %s", exp_iso)
                    return None
            except ValueError:
                return None
        return data
    except (ValueError, InvalidSignature, json.JSONDecodeError) as exc:
        log.warning("Cert verify failed: %s", exc)
        return None


async def validate_license_online(license_key: str) -> bool:
    """Call Superadmin license server. Returns True if license still valid."""
    url = f"{settings.superadmin_license_server.rstrip('/')}/api/v1/license/validate"
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.post(url, json={"license_key": license_key})
            if resp.status_code != 200:
                log.warning("License server returned %s for %s", resp.status_code, license_key)
                return False
            data = resp.json()
            return bool(data.get("valid"))
    except Exception as exc:
        log.warning("License server unreachable: %s", exc)
        return False


async def _check_one_license(license_obj: License) -> bool:
    """Dispatch validation by deployment mode."""
    if settings.deployment_mode == "air_gapped":
        return verify_offline_certificate(
            license_obj.key, license_obj.signed_certificate or ""
        ) is not None
    return await validate_license_online(license_obj.key)


async def periodic_license_check() -> None:
    """Background loop — re-validate every active license periodically.

    Started by FastAPI lifespan. Cancelled on shutdown.
    """
    interval_seconds = settings.license_check_interval_hours * 3600
    grace = timedelta(days=settings.license_grace_period_days)
    log.info(
        "License checker started (mode=%s, interval=%dh, grace=%dd)",
        settings.deployment_mode,
        settings.license_check_interval_hours,
        settings.license_grace_period_days,
    )
    while True:
        try:
            async with AsyncSessionLocal() as session:
                rows = await session.execute(
                    select(License).where(License.is_revoked.is_(False))
                )
                licenses = rows.scalars().all()
                now = datetime.now(timezone.utc)
                for lic in licenses:
                    ok = await _check_one_license(lic)
                    if ok:
                        lic.last_validated_at = now
                    else:
                        last = lic.last_validated_at
                        if last is None or (now - last) > grace:
                            lic.is_revoked = True
                            lic.revocation_reason = (
                                "Failed periodic validation beyond grace period"
                            )
                            log.warning(
                                "License %s revoked (grace exhausted)", lic.key
                            )
                await session.commit()
        except asyncio.CancelledError:
            log.info("License checker cancelled")
            raise
        except Exception as exc:
            # Don't crash background task — log and retry next cycle
            log.error("License check cycle failed: %s", exc)
        await asyncio.sleep(interval_seconds)
