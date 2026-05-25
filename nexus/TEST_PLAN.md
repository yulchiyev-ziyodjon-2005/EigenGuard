# EigenGuard Nexus — MVP Test Plan

End-to-end MVP test ssenariysi: Superadmin → Tenant → Web (camera test) → Mobile.

## 1. Boshlang'ich setup

```bash
cd nexus
cp .env.example .env
# .env'da POSTGRES_PASSWORD va JWT_SECRET ni o'zgartiring
docker compose up -d --build
docker compose logs -f backend       # status kuzatib turing
```

Kutiladigan natija:
- `nexus_postgres` healthy
- `nexus_redis` healthy
- `nexus_backend` "Nexus starting — env=development, mode=cloud"
- `nexus_frontend` nginx ishlamoqda

## 2. Seed (birinchi marta)

```bash
docker compose exec backend python -m scripts.seed
```

Bu yaratadi:
- **superadmin** tenant + admin user (`admin@eigenguard.uz` / `ChangeMe123!`)
- **demo** tenant + admin (`admin@demo.local` / `DemoAdmin123!`)
- **demo** tenant + mobile xodim (`engineer@demo.local` / `Engineer123!`)
- License (demo tenant uchun 365 kun)

## 3. Backend API verify (curl)

```bash
# Service info — public
curl http://localhost:8000/

# Health
curl http://localhost:8000/health

# OpenAPI docs (brauzerda)
open http://localhost:8000/docs

# Login as superadmin (header bilan tenant tanlaymiz)
curl -X POST http://localhost:8000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -H "X-EigenGuard-Tenant: superadmin" \
  -c cookies.txt \
  -d '{"email":"admin@eigenguard.uz","password":"ChangeMe123!"}'

# Get me
curl http://localhost:8000/api/v1/auth/me \
  -H "X-EigenGuard-Tenant: superadmin" \
  -b cookies.txt

# List tenants (superadmin only)
curl http://localhost:8000/api/v1/superadmin/tenants \
  -H "X-EigenGuard-Tenant: superadmin" \
  -b cookies.txt
```

## 4. Web SPA — to'liq ssenariy

### Hisob 1: SUPERADMIN

1. `http://localhost:8080/login` oching
2. **Tenant**: `superadmin` · **Email**: `admin@eigenguard.uz` · **Parol**: `ChangeMe123!`
3. ◆ Tenants menyusiga o'ting
4. "+ Yangi Tenant" tugmasini bosing
5. Yangi tenant yarating:
   - Nomi: `Toshkent Energetika`
   - Subdomain: `toshkent-energ`
   - Mode: cloud
   - Admin email: `bekzod@energ.local`
   - Admin password: `Energ12345!`
   - FIO: `Bekzod Toshmatov`
6. Tenants ro'yxatida yangi tenant paydo bo'lganini ko'ring
7. Chiqing

### Hisob 2: YANGI TENANT ADMIN

1. Qaytadan kiring:
   - **Tenant**: `toshkent-energ`
   - **Email**: `bekzod@energ.local` · **Parol**: `Energ12345!`
2. Dashboard'da hozircha qurilmalar/o'lchovlar yo'q
3. **Users** menyusiga o'ting
4. "+ Yangi xodim" qo'shing:
   - Email: `dilshod@energ.local`
   - Parol: `Field12345!`
   - FIO: `Dilshod Karimov`
   - Tenant admin: false (oddiy xodim)
5. **Camera Test** menyusiga o'ting
6. ▶ Boshlash → brauzer kameraga ruxsat so'raydi
7. Kamera oldida qo'lingiz bilan harakatlaning — motion va Risk % o'zgarishini kuzating
8. "Nexus'ga yuborish" checkbox ON — har 2 sek o'lchov POST qilinadi
9. Dashboard'ga qaytib qurilma `browser-...` paydo bo'lganini va o'lchovlarni ko'ring

### Mobile bilan integratsiya (mobile kod o'zgartirilgandan keyin)

1. Mobile app Settings'da:
   - Nexus endpoint: `http://<your-laptop-ip>:8000/api/v1/measurements`
   - Bearer token: mobile login qilgach JWT'ni ishlatadi (auth ekran qo'shilgandan keyin)
2. Mobile login: `engineer@demo.local` / `Engineer123!` (`demo` tenant)
3. Mobile o'lchov yuboradi → Nexus Dashboard'da `engineer@demo.local`ning telefoni paydo bo'ladi
4. Web admin **Commands** menyusi orqali shu telefonga `notify` yuboradi
5. Mobile WebSocket orqali real-time qabul qiladi

> ⚠ **Mobile auth + WebSocket integratsiyasi keyingi sprintda** (mobile kod o'zgartiriladi).
> Hozir mobile faqat Bearer token bilan POST qila oladi — Nexus'da `engineer@demo.local`
> ga login qilib JWT olib, qo'lda Settings'ga kiritish kifoya.

## 5. WebSocket test (curl/wscat)

```bash
# wscat o'rnatish: npm install -g wscat
# Avval JWT oling:
TOKEN=$(curl -sX POST http://localhost:8000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -H "X-EigenGuard-Tenant: demo" \
  -d '{"email":"engineer@demo.local","password":"Engineer123!"}' \
  | python -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# Mobile WebSocket'ga ulanish (engineer sifatida)
wscat -c "ws://localhost:8000/api/v1/ws/mobile?token=$TOKEN&device_identifier=test-phone-001&platform=android&device_name=Test%20Phone"
# Welcome message + pending commands olinadi

# Boshqa terminal'da web admin orqali notify yuboring:
# Web'da `demo` tenant'ga `admin@demo.local`/`DemoAdmin123!` login qiling
# Commands → device tanlang → notify yuboring
# wscat terminal'ida real-time {"kind":"command",...} keladi
```

## 6. Production checklist (Railway / mijoz serveri)

- [ ] `.env` da `JWT_SECRET=$(openssl rand -hex 32)` + `POSTGRES_PASSWORD` o'zgartirilgan
- [ ] `ENVIRONMENT=production` — CORS qatag'an, cookie `Secure`
- [ ] `TENANT_SUBDOMAIN_ROOT` real domain (`eigenguard.uz`)
- [ ] HTTPS sertifikati (Railway avtomatik beradi, on-premise nginx/traefik)
- [ ] PostgreSQL backup strategiyasi
- [ ] `superadmin` parolini o'zgartiring (Settings'ga keyin reset endpoint kerak)
- [ ] License: HiveMQ Cloud / SendGrid / Sentry kabi external service'lar uchun secret'lar

## 7. Sprint 18 (keyingi) — mobile integratsiya

1. Mobile'da `auth_service.dart` (JWT login screen + secure storage)
2. Mobile'da `nexus_command_service.dart` (WebSocket listener)
3. Command handler'lar: `start_scan`, `notify`, `enable_demo_mode`, etc.
4. Settings'da Nexus URL + auth kalitlari avtomatik (login orqali)
5. CI: GitHub Actions — `npm run build` + `pytest` + Railway deploy
