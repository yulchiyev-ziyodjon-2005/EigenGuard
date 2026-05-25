# EigenGuard Nexus — Web Command Center

Hybrid B2G SaaS backend for EigenGuard structural health monitoring ecosystem.

## Deployment modes

| Mode | Use case | License validation |
|------|----------|-------------------|
| **Cloud** | `clientA.eigenguard.uz` multi-tenant SaaS on our infra | Auto (DB-internal) |
| **On-premise** | Government client's private servers, has internet | Periodic HTTP check to Superadmin |
| **Air-gapped** | Strictly isolated intranet, no outbound traffic | Static Ed25519 certificate, offline verify |

## Quick start (development)

```bash
cd nexus
cp .env.example .env
# .env ni tahrirlang — POSTGRES_PASSWORD va JWT_SECRET ni o'zgartiring
docker compose up -d
# Backend: http://localhost:8000
# OpenAPI: http://localhost:8000/docs
```

## Tenant routing

Subdomain-based (cloud):
```
GET https://clientA.eigenguard.uz/api/v1/me/tenant
```

Header-based (on-premise, API clients):
```
GET http://nexus.local:8000/api/v1/me/tenant
Header: X-EigenGuard-Tenant: clientA
```

On-premise/air-gapped single-tenant: `subdomain="default"` ishlatiladi.

## Structure

```
nexus/
├── docker-compose.yml         # FastAPI + PostgreSQL + Redis + (Vue/ONNX placeholders)
├── .env.example               # Copy to .env
└── backend/
    ├── Dockerfile             # Python 3.12-slim
    ├── requirements.txt
    └── app/
        ├── main.py            # FastAPI app + lifespan + tenant middleware
        ├── core/
        │   ├── config.py      # Pydantic Settings
        │   ├── database.py    # Async SQLAlchemy 2.x
        │   └── license.py     # Ed25519 cert + online validation + periodic task
        ├── middleware/
        │   └── tenant.py      # Subdomain extraction + header fallback
        └── models/
            ├── tenant.py
            ├── license.py
            └── measurement.py
```

## Air-gapped deployment

1. Superadmin generates Ed25519 keypair (`openssl genpkey -algorithm Ed25519`)
2. Issues signed certificate per air-gapped tenant
3. Public key delivered with the deployment package to `backend/keys/superadmin_public.pem`
4. Set `DEPLOYMENT_MODE=air_gapped` in `.env`
5. License periodically re-verified locally (no network calls)

## Next sprints

- Sprint 17: ESP32 firmware + first end-to-end pilot
- Sprint 18: Auth (JWT), Vue.js frontend skeleton, mobile uploader → Nexus integration test
- Sprint 19: Custom AI training pipeline, multi-site dashboard
- Sprint 20: Production hardening, first paying customer deployment
