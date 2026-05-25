# EigenGuard Nexus Backend — Python 3.12 + FastAPI + SQLAlchemy 2.x async
FROM python:3.12-slim AS base

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# System deps for asyncpg / cryptography / healthcheck
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        libpq-dev \
        curl \
    && rm -rf /var/lib/apt/lists/*

# Python deps — separate layer for caching
COPY requirements.txt .
RUN pip install --upgrade pip && pip install -r requirements.txt

# App code (overridden by volume mount in dev)
COPY app ./app

EXPOSE 8000

# Healthcheck — Docker o'zi orqali `service_healthy` uchun
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD curl -fsS http://localhost:8000/health || exit 1

# Dev: --reload faol; Production'da reload'ni olib tashlang yoki gunicorn'ga o'ting
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
