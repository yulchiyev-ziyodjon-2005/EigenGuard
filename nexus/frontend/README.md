# EigenGuard Nexus Frontend

Vue 3 + Vite + TypeScript + Tailwind + Pinia SPA.

## Dev

```bash
npm install
npm run dev   # http://localhost:5173 (proxies /api → http://localhost:8000)
```

## Build

```bash
npm run build         # dist/ — static SPA
npm run preview       # local preview of build
```

## Tech stack
- **Vue 3** + Composition API + `<script setup>`
- **TypeScript** strict mode
- **Vite 6** — fast dev + production build
- **Vue Router 4** — file-style routes + auth guards
- **Pinia** — state management (auth)
- **Axios** — HTTP client (with cookie credentials + tenant header interceptor)
- **Tailwind CSS 3** — utility-first
- **@vueuse/core** — utility composables

## Routes

| Path | View | Access |
|------|------|--------|
| `/login` | Login | Public |
| `/` | Dashboard (devices + measurements) | Auth |
| `/users` | User management | Tenant admin |
| `/commands` | Send commands to devices | Auth |
| `/camera-test` | Browser webcam vibration test | Auth |
| `/superadmin/tenants` | Tenants CRUD | Superadmin |

## Auth flow

1. User opens `/login`, enters email + password + tenant subdomain.
2. POST `/api/v1/auth/login` — sets `access_token` HttpOnly cookie.
3. Frontend GET `/api/v1/auth/me` — returns user + tenant info.
4. Tenant subdomain stored in localStorage, sent as `X-EigenGuard-Tenant` header.
