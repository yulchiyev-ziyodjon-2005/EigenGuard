# EigenGuard

EigenGuard is a DeepTech structural health monitoring and predictive maintenance platform for industrial equipment and public infrastructure.

The project combines a Flutter field-engineer app, an Edge sensor ingestion layer, and the Nexus web command center. It is designed for B2G and industrial deployments where early fault detection, auditability, tenant isolation, and offline/on-premise operation matter.

## What It Does

- Detects vibration and visual anomalies from a phone camera using YOLO segmentation and optical-flow analysis.
- Uses phone sensors and external Edge sensors together: camera, IMU, microphone, GPS, BLE, MQTT, and optional ESP32 telemetry.
- Computes risk, dominant frequency, amplitude, material-aware thresholds, and remaining useful life estimates.
- Builds 3D digital twin style point-cloud visualizations with hotspot heatmaps.
- Syncs field measurements into Nexus for multi-tenant dashboards, device tracking, alerts, and audit-ready workflows.

## Architecture

```text
Edge Sensors / BYOD IoT
  ESP32, vibration, temperature, acoustic, BLE, MQTT
          |
          v
Mobile App / Field Engineer
  Flutter, YOLO ONNX, C++ FFI, Kalman, FFT, prediction math
          |
          v
Nexus Command Center
  FastAPI, PostgreSQL, Redis, Vue, WebSocket, tenant and license management
```

## Key Modules

- `eigen_guard/` - Flutter mobile app with camera analysis, sensor fusion, 3D twin, local history, and Nexus sync.
- `eigen_guard/native/` - C++17 native engine for optical flow, FFT, Kalman filtering, spline interpolation, and approximation.
- `nexus/backend/` - FastAPI backend for authentication, tenants, users, devices, measurements, commands, licenses, audit logs, and WebSocket events.
- `nexus/frontend/` - Vue 3 command center for superadmin, tenant admin, dashboard, camera test, users, devices, and AI analysis.

## MVP Capabilities

- Superadmin creates tenants and tenant admins.
- Tenant admins create employees with roles and login credentials.
- Field employees log into the mobile app and upload measurements.
- Dashboard shows devices, live measurement history, AI analysis, risk trends, and command delivery.
- Deployment modes include cloud SaaS, on-premise, and air-gapped license validation.

## Technology

- Flutter / Dart
- C++17 native processing via FFI
- YOLO segmentation through ONNX Runtime
- FastAPI + SQLAlchemy async
- PostgreSQL + Redis
- Vue 3 + TailwindCSS
- MQTT and BYOD JSON ingestion
- Google Gemini integration for engineering AI consult

## Development Quick Start

### Nexus

```bash
cd nexus
cp .env.example .env
docker compose up -d --build
docker compose exec backend python -m scripts.seed
```

Open:

- Backend: `http://localhost:8000`
- OpenAPI: `http://localhost:8000/docs`
- Frontend: `http://localhost:8080`

### Frontend Only

```bash
cd nexus/frontend
npm install
npm run dev
```

### Mobile

```bash
cd eigen_guard
flutter pub get
flutter run
```

## Current Focus

The current MVP focus is an end-to-end flow:

1. Superadmin creates a tenant.
2. Tenant admin creates employees and roles.
3. Employee logs into the mobile app.
4. Camera and sensor data are analyzed locally.
5. Measurement and prediction data are sent to Nexus.
6. Nexus dashboard shows risk, devices, alerts, and AI recommendations.

## Pitch Summary

EigenGuard reduces the cost and friction of structural health monitoring by turning standard smartphones and low-cost Edge sensors into an AI-assisted predictive maintenance network for factories, utilities, buildings, bridges, and smart city infrastructure.
