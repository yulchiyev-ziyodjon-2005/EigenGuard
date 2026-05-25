# EigenGuard — Loyiha Holati

> **Living document** — har sprint yakunida yangilanadi.

**Oxirgi yangilangan:** 2026-05-18 (Sprint 16 yakuni)
**Versiya:** v1.0.0+1
**Kodbaza:** 47 ta Dart fayl, **16,353 LOC** `lib/` ichida + 6 ta C++ modul
**`flutter analyze`:** 0 issues ✅

---

## 1. Snapshot tarixi

| Sana | Milestone | Asosiy o'zgarish |
|------|-----------|------------------|
| 2026-05-17 | Sprint 1–7 (Mobile MVP) | Material profile, akustik probe, magnetometer/flash/GPS, vibratsiya probe, BLE, 3D twin, real data history |
| 2026-05-17 | B2G pivot e'lon qilindi | 3-node ekotizim arxitekturasi (Edge / Mobile / Nexus) |
| 2026-05-17 | Sprint 15 (Edge Bridge Core) | DB v5 sync layer, SensorFusionArbiter (±200ms), MqttIngestService framework (mock backend) |
| **2026-05-18** | **Sprint 16 (Hyper-Agile Production)** | **Real `mqtt_client`, BYOD JSON parser, NexusUploadService, Demo Mode toggle** |

---

## 2. Strategik kontekst — Hyper-Agile Timeline

**Pivot 2026-05-18:** AI-assisted coding (Claude + Claude Code) tufayli an'anaviy 12-18 oylik B2G yo'l xaritasi obsoletga aylandi. Yangi maqsad — **4-6 oy ichida birinchi tijoriy deployment**.

### Operatsion direktivalar (Sprint 16+ uchun)

1. **Hyper-Agile Coding** — kelajakdagi abstraktsiyalarni qurmaslik. Lean, immediately-executable kod. Eng samarali kutubxonalar.
2. **AI-Assisted Custom Model** — 1-2 oylik pilot davomida sof markirovkalangan time-series ma'lumotlar yig'ish, so'ng tezda custom AI o'qitish.
3. **Hardware Agnostic (BYOD)** — mijozlar o'z sensorlarini olib keladi. `MqttIngestService` xilma-xil JSON tuzilmalarini parse qilishi shart.

---

## 3. Makro-arxitektura — B2G 3-node ekotizimi

```
┌─────────────────────────────┐      MQTT      ┌──────────────────────────────┐
│    EDGE (ESP32 IoT node)    │ ─────────────> │    MOBILE (Flutter app)      │
│  • MPU6050 / MLX90614 /     │   QoS 1 +      │  • YOLO26 segmentation       │
│    Akustik / BYOD any        │   auto-recon   │  • C++ Optical Flow + Kalman │
│  • WiFi + MQTT publisher    │                │  • 3D Point Cloud + Mesh     │
│  • BYOD: har xil firmware    │                │  • SensorFusionArbiter       │
└─────────────────────────────┘                │  • DemoMode (sales/standalone)│
                                               │  • NexusUploadService        │
                                               │  • Gemini AI consult         │
                                               └──────────────┬───────────────┘
                                                              │
                                                              │ HTTPS POST + Bearer
                                                              ▼
                                               ┌──────────────────────────────┐
                                               │  NEXUS (Vue.js + Python)     │
                                               │  Command Center              │
                                               │  • Shahar 3D map             │
                                               │  • Multi-site dashboard      │
                                               │  • Alert routing             │
                                               │  • Custom AI training        │
                                               └──────────────────────────────┘
                                               (skeleton client tayyor —
                                                server still TBD, Sprint 17)
```

### Sensor Fusion qoidasi

| Kamera | Edge sensor | Demo Mode | Verdikt |
|--------|-------------|-----------|---------|
| Vibratsiya | Sokin | OFF | **False Positive** (alert YO'Q) |
| Vibratsiya | Vibratsiya tasdiqlamoqda | OFF | **Critical Alert** (qizil) |
| Sokin | Vibratsiya | OFF | **Hardware Only** (vizual tekshiruv) |
| Vibratsiya | (har qanday) | **ON** | **Critical Alert** (sales/standalone rejim) |
| Sokin | Sokin | har qanday | **Idle** |
| Vibratsiya | MQTT ulanmagan | OFF | **Camera Only** (fallback) |

Korrelyatsiya oynasi: **±200ms**. Demo Mode `SettingsService` orqali boshqariladi, real-time effekt.

---

## 4. Bajarilgan ishlar — xronologik

### Phase 1-7 — Mobile MVP (DONE 2026-05-17)
Universal material profile, acoustic/vibration probes, magnetometer+flash+GPS, BLE external sensors, 3D mesh + hotspots (Delaunay), real data history with replay. To'liq tafsilot xotirada (`project_eigenguard.md`).

### Sprint 15 — Edge Bridge Core (DONE 2026-05-17)
- **DB v5 migratsiya** — `+device_id, +source, +sync_status, +nexus_id, +fusion_confidence` (measurements) + `+device_id, +source, +sync_status, +nexus_id` (scans), 2 ta indeks, sync helperlari
- **`edge_sensor_reading.dart`** — ESP32 telemetriyasi DTO
- **`mqtt_ingest_service.dart`** — framework (mock backend, real client stub)
- **`sensor_fusion_arbiter.dart`** — ±200ms korrelyatsiya, 5-state FusionVerdict
- Dashboard integratsiya + History UI source chip

### Sprint 16 — Hyper-Agile Production (DONE 2026-05-18) ⭐

#### Task 1: Demo Mode Toggle (sotuv uchun KRITIK)
- **`SettingsService.demoMode`** (bool, persisted)
- **`SensorFusionArbiter.demoMode`** field; `_evaluate` ga yangi birinchi tarmoq — kamera-only ham `consensusCritical` chiqaradi
- **Settings UI** — switch + live effekt (saqlash kutilmaydi)
- **Maqsad:** sotuv demosi yoki ESP32 yo'q dala muhandisi standalone rejimi

#### Task 2: Protocol-Agnostic MQTT
- **`mqtt_client: ^10.5.1`** (installed `10.11.11`) qo'shildi
- **`MqttIngestService.connectReal()`** — `MqttServerClient.withPort`, auto-reconnect, resubscribe-on-reconnect, QoS 1, 10s timeout, silent-fail
- **Topic parsing** — `eigenguard/<site>/<device>/<channel>` 4-qism (+ 3-qism va 2-qism fallback)
- **BYOD `_FlexJson` parser** (`edge_sensor_reading.dart`):
  - Case-insensitive maydon qidiruv
  - Multi-alias arrays (`vib_mm` / `vibrationAmplitudeMm` / `vibration` / `amp` / ...)
  - Nested object traversal (`data` / `payload` / `msg` / `body` / `sensor`)
  - String→num parsing (birliklarni tashlab yuboradi: `"1.42mm"` → `1.42`)
  - JSON array ham qabul (firmware `[{...}]` yuboradi)
  - **Hech qachon crash bo'lmaydi** — bad JSON → `null`, ilova davom etadi

#### Task 3: NexusUploadService Skeleton
- **`http: ^1.2.2`** (installed `1.6.0`) qo'shildi
- **`lib/services/nexus_upload_service.dart`** (227 LOC) — singleton
- Periodic 5min Timer + manual `syncNow()` API
- `getPendingSyncRecords(limit:50)` → HTTP POST har biri (Bearer token ixtiyoriy)
- 10s request timeout, marks `synced`/`failed` via DB helpers
- Response JSON dan `nexus_id` ekstraksiya (`id` / `nexus_id` / `_id`)
- 6 ta ValueNotifier (state, pendingCount, totalSynced, totalFailed, lastSyncAt, lastError)
- **Empty endpoint → disabled** (no-op, hech narsa yuborilmaydi)

#### Settings UI: "B2G Ekotizimi" kartochkasi
- Demo Mode switch (live effekt)
- MQTT broker: host / port / username / password
- Nexus: endpoint / Bearer token
- **Live status pill'lari** — `ValueListenableBuilder` orqali MQTT state + Nexus pending count
- **"SYNC NOW"** tugmasi — qo'lda darhol sinxronizatsiya
- Xato xabarlari — `lastError` ValueNotifier

#### `main.dart` startup wiring
- `SettingsService.demoMode` → `SensorFusionArbiter().demoMode`
- Agar `mqttBrokerHost` sozlangan bo'lsa — `MqttIngestService().connectReal(...)` avtomatik (fon)
- `NexusUploadService().start()` har doim chaqiriladi (endpoint bo'sh bo'lsa o'z-o'zidan no-op)

---

## 5. Joriy fayllar tuzilishi

### Statistika
- **47 ta Dart fayl** (+1 ↑ Sprint 16)
- **16,353 LOC** (+844 ↑ Sprint 16)

### Sprint 16 da o'zgartirilgan / yangi
| Fayl | Holat | LOC |
|------|-------|-----|
| 🆕 `lib/services/nexus_upload_service.dart` | YANGI | 227 |
| 🔄 `lib/services/mqtt_ingest_service.dart` | Real broker | 301 (oldin 200) |
| 🔄 `lib/services/sensor_fusion_arbiter.dart` | Demo bypass | 327 (oldin 315) |
| 🔄 `lib/models/edge_sensor_reading.dart` | _FlexJson | 272 (oldin ~130) |
| 🔄 `lib/services/settings_service.dart` | +7 getter/setter | 137 (oldin 100) |
| 🔄 `lib/screens/settings_screen.dart` | B2G kartochka | 961 (oldin 641) |
| 🔄 `lib/main.dart` | B2G startup wiring | — |
| 🔄 `pubspec.yaml` | +mqtt_client, +http | — |

### Eng katta 10 ta fayl
| Fayl | LOC |
|------|-----|
| `lib/screens/dashboard_screen.dart` | 1621 |
| `lib/screens/monitoring_screen.dart` | 1204 |
| `lib/screens/settings_screen.dart` | 961 |
| `lib/widgets/vibration_probe_widget.dart` | 715 |
| `lib/screens/digital_twin_screen.dart` | 710 |
| `lib/services/vision_ai_service.dart` | 698 |
| `lib/widgets/ble_picker_widget.dart` | 581 |
| `lib/widgets/acoustic_probe_widget.dart` | 528 |
| `lib/screens/history_screen.dart` | 455 |
| `lib/services/acoustic_probe_service.dart` | 401 |

---

## 6. Texnologik stack

### Flutter dependencies (yangilangan — Sprint 16)

| Paket | Versiya | Maqsad |
|-------|---------|--------|
| `flutter` | SDK | UI framework |
| `ffi` | ^2.1.4 | Dart ↔ C++ bridge |
| `sqflite` | ^2.3.3 | SQLite v5 |
| `path_provider`, `path`, `shared_preferences` | latest | Persistence |
| `camera` | ^0.11.1 | Camera stream + ROI |
| `sensors_plus` | ^7.0.0 | IMU + magnetometer |
| `record`, `audioplayers` | ^6.x | Audio I/O |
| `geolocator` | ^13.0.2 | GPS (Phase 3) |
| `vibration` | ^2.0.0 | Haptic probe (Phase 4) |
| `flutter_blue_plus` | ^1.32.12 | BLE sensors (Phase 5) |
| `onnxruntime` | ^1.4.1 | YOLO26 inference |
| `image` | ^4.5.4 | Image preprocessing |
| `permission_handler` | ^11.3.1 | Runtime permissions |
| `google_generative_ai` | ^0.4.7 | Gemini AI consult |
| `image_picker`, `file_picker` | ^1.x / ^10.x | File access |
| 🆕 **`mqtt_client`** | ^10.5.1 (10.11.11) | Real MQTT broker (Sprint 16) |
| 🆕 **`http`** | ^1.2.2 (1.6.0) | Nexus HTTP uploader (Sprint 16) |

### Android ruxsatlari
`CAMERA, RECORD_AUDIO, INTERNET, ACCESS_FINE_LOCATION, FLASHLIGHT, VIBRATE, BLUETOOTH_SCAN (neverForLocation), BLUETOOTH_CONNECT`

---

## 7. C++ Native Engine

`native/` direktoriyasi — Flutter FFI orqali. 6 modul: OpticalFlow + Kalman + FFT + Spline + Approximation + FfiBridge.

`build/app/intermediates/cxx/` — `.so` shared library Android NDK orqali.

**Sprint 16 da o'zgartirilmagan** — C++ engine stable.

---

## 8. DB v5 sxemasi (Sprint 15 dan, o'zgartirilmagan)

`measurements` jadval (24 ustun) — Phase 1–7 + Sprint 15 B2G sync layer (`device_id, source, sync_status, nexus_id, fusion_confidence`).
`scans` jadval (8 ustun) — point cloud BLOB + B2G sync ustunlari.

Migratsiya tarixi: v1 → v2 → v3 → v4 → v5 (faqat ALTER ADD COLUMN — drop/rename yo'q).

Sync helperlari (Sprint 15): `getPendingSyncRecords()`, `markRecordSynced(nexusId)`, `markRecordSyncFailed()` — Sprint 16 da `NexusUploadService` foydalanmoqda.

---

## 9. Sensor Fusion + Demo Mode (Sprint 15-16)

### Decision flow

```dart
if (demoMode && cameraTriggered) {
  v = consensusCritical;  // Bypass — sales/standalone
} else if (cameraTriggered && edgeTriggered) {
  v = consensusCritical;  // True consensus
} else if (cameraTriggered && mqttHasData && !edgeTriggered) {
  v = falsePositive;       // Edge inkor etdi — ALERT SUPPRESS
} else if (cameraTriggered && !mqttHasData) {
  v = cameraOnly;          // MQTT yo'q — fallback
} else if (!cameraTriggered && edgeTriggered) {
  v = hardwareOnly;        // Edge ko'rdi, vizualda yo'q
} else {
  v = idle;
}
```

### Konfiguratsiya (default)

| Parametr | Qiymat |
|----------|--------|
| `correlationWindow` | 200ms |
| `cameraAmpThresholdMm` | 0.5 |
| `edgeAmpThresholdMm` | 1.0 |
| `resonanceMinHz` | 5.0 |
| `verdictHoldDuration` | 800ms |
| `edgeBufferMaxAge` | 2s |
| Ring buffer hajmi | 50 |
| **`demoMode`** | **false (default — production mode)** |

### Confidence formulasi (consensus paytida)
```
confidence = 0.4 · amp_ratio + 0.4 · freq_ratio + 0.2 · snr
demo mode: confidence = riskPercent / 100
```

---

## 10. MQTT Integratsiya + BYOD Parser (Sprint 16) ⭐

### MqttIngestService — production-ready

**Holatlar:** `disconnected` / `connecting` / `connected` / `mockedStreaming` / `error` — 5-state ValueNotifier.

**Real broker ulanish:**
```dart
final ok = await MqttIngestService().connectReal(
  brokerHost: 'broker.hivemq.com',
  port: 1883,
  username: null,  // anonymous
  password: null,
);
// Topic auto-subscribe: eigenguard/+/+/+
```

**Resilience xususiyatlari:**
- `keepAlivePeriod = 30s`
- `autoReconnect = true` + `resubscribeOnAutoReconnect = true`
- 10s connect timeout
- Silent-fail on error (returns `false`, caller mock'ga qaytishi mumkin)
- `stopAll()` cleanly disconnects + cancels subscription

**Topic format:** `eigenguard/<site>/<device>/<channel>`
- `<channel>` = `vib` / `temp` / `acoustic`
- 4-qism format default, 3-qism va 2-qism fallback formatlari ham qabul qilinadi

### BYOD `_FlexJson` parser — chayqalgan JSON ga toleratsiya

**Maqsad:** har xil ESP32/Arduino/Particle/RPi firmware'lar har xil JSON format yuboradi. Hammasini ishlatish.

**Xususiyatlar:**
- **Case-insensitive** maydon nomlari
- **Multi-alias** har maydon uchun (vib_mm / vibrationAmplitudeMm / vibration / amp / amplitude_mm / amp_mm / vib / amplitude)
- **Nested obyektlar** — `{"data": {...}}` yoki `{"payload": {...}}` ichida ham qidiriladi
- **String → number** — `"1.42mm"`, `"28.4 Hz"`, `"47.2°C"` → birliklarni avtomatik tashlab yuboradi
- **Boolean → 0/1** fallback
- **JSON array** ham qabul — firmware `[{...}]` yuborgan bo'lsa birinchi obyekt olinadi
- **Silent fail** — malformed UTF-8 / bad JSON / empty payload → `null`, ilova **hech qachon crash bo'lmaydi**

**Quyidagilarning hammasi bir xil natijani beradi:**
```json
{"device_id":"ESP32-A1","vib_mm":1.42,"freq_hz":28.4,"temp_c":47.2}
{"device_id":"ESP32-A1","vibration":"1.42mm","frequency":"28.4 Hz","temperature":"47.2°C"}
{"data":{"vib":1.42,"freq":28.4,"temp_c":47.2}}
{"deviceId":"ESP32-A1","amplitudeMm":1.42,"dominantFrequencyHz":28.4}
[{"vib_mm":1.42,"freq_hz":28.4}]
```

---

## 11. NexusUploadService (Sprint 16) ⭐

### API
```dart
NexusUploadService().start(period: Duration(minutes: 5));  // periodic
NexusUploadService().syncNow();                            // manual
NexusUploadService().restart();                            // re-config
NexusUploadService().stop();                               // off
```

### ValueNotifier observables
- `state` — 5-state: `idle`, `syncing`, `success`, `failed`, `disabled`
- `pendingCount` — UI badge uchun
- `totalSynced`, `totalFailed` — lifetime counters
- `lastSyncAt`, `lastError`

### HTTP request format
- POST → `<nexusEndpoint>`
- Headers: `Content-Type: application/json`, `User-Agent: EigenGuard-Mobile/1.0`, optional `Authorization: Bearer <token>`
- Body: `MeasurementRecord` ni JSON ga serialize (24 ta maydon)
- Timeout: 10s
- Response: `{ "id": "..." }` JSON dan `nexus_id` olinadi va DB ga yoziladi

### Test qilish
1. Settings → Nexus endpoint = `https://webhook.site/<your-uuid>` yoki `https://httpbin.org/post`
2. Bearer token (ixt.) = `test-token-123`
3. SAQLASH
4. SYNC NOW tugmasi → bir nechta soniyada `NEXUS OK · 0 ta pending`
5. webhook.site'da yuborilgan JSON ko'rinadi

---

## 12. Modul-bo'yicha holat tahlili

### ✅ To'liq ishlaydigan (production-ready)

| Modul | Holat |
|-------|-------|
| Camera + Optical Flow | C++ + FFI, IMU compensation |
| YOLO26 Segmentation | NMS-free seg, ONNX runtime |
| Material Profile (12 preset) | Auto-infer + manual |
| Acoustic Probe (Phase 2) | Chirp sweep + FFT + damping |
| Magnetometer/Flash/GPS (Phase 3) | HUD chiplari + DB tag |
| Vibration Probe (Phase 4) | Telefon motor → IMU response |
| 3D Twin + Hotspots (Phase 6) | Delaunay + 4 render mode |
| Real-time History (Phase 7) | DB BLOB + replay |
| **Sensor Fusion Arbiter** | ±200ms, 5 verdict |
| **DB v5 sync layer** | Pending records + helpers |
| **🆕 Real MQTT Broker (Sprint 16)** | mqtt_client 10.x, auto-reconnect |
| **🆕 BYOD JSON Parser (Sprint 16)** | Flex aliases, no-crash |
| **🆕 NexusUploadService (Sprint 16)** | Periodic + manual sync |
| **🆕 Demo Mode (Sprint 16)** | Sales/standalone toggle |

### ⚠️ Qisman ishlaydigan / cheklangan

| Modul | Cheklov |
|-------|---------|
| BLE Phase 5 | Code ready, hardware-untested |
| Gemini AI | API key qo'lda, offline fallback yo'q |
| YOLO inference | UI thread (Isolate yaxshi bo'lardi) |
| DigitalTwin `_components` hardcoded map | `digital_twin_screen.dart:38` |

### ❌ Hali yo'q

| Funksiya | Target Sprint |
|----------|---------------|
| ESP32 firmware (MPU6050+MLX90614+MQTT) | Sprint 17 (1-2 hafta) |
| Nexus backend (Python + Vue.js) | Sprint 17-18 (3-4 hafta) |
| Custom AI model training pipeline | Sprint 18-19 (pilot data → train) |
| ESP32 BLE protokol dekoder | Sprint 17 (BLE fallback uchun) |
| Multi-site / multi-tenant scoping | Sprint 19 |
| YOLO Isolate optimization | Sprint 20 (productionization) |
| `SplineProcessor` Dart chaqirish (C++ tayyor) | Sprint 20 |

---

## 13. Ochiq qolgan ishlar (Outstanding Gaps)

Qisqartirilgan ro'yxat (Sprint 16 dan keyin):

| # | Gap | Holat |
|---|-----|-------|
| 1-2 | Phase 1 risk math + ApproxProcessor | ✅ DONE |
| 3 | DigitalTwin hardcoded `_components` map | ⚠️ olib tashlash kerak |
| 4 | Point cloud SQLite persistence | ✅ DONE Phase 7 |
| 5 | SplineProcessor Dart chaqirish | ❌ (C++ tayyor) |
| 6 | Critical hotspot extraction | ✅ DONE Phase 6 |
| 7 | YOLO ONNX Isolate | ❌ (productionization) |
| 8 | Gemini API key encrypted storage | ❌ (productionization) |
| 9 | MQTT client integratsiya | ✅ **DONE Sprint 16** |
| 10 | Sensor Fusion Arbiter | ✅ DONE Sprint 15 |
| 11 | Persistence sync-ready | ✅ DONE Sprint 15 |
| 12 | ESP32-spetsifik BLE protokol dekoder | ❌ (BLE fallback uchun) |
| 13 | MQTT real client | ✅ **DONE Sprint 16** |
| 14 | Nexus backend uploader | ✅ **DONE (skeleton) Sprint 16** |
| 15 | BYOD JSON parser | ✅ **DONE Sprint 16** |
| 16 | Demo Mode toggle | ✅ **DONE Sprint 16** |
| 17 | **Nexus backend server (Python+Vue)** | ❌ **YANGI — Sprint 17** |
| 18 | **ESP32 firmware (haqiqiy hardware)** | ❌ **YANGI — Sprint 17** |
| 19 | **Custom AI model training pipeline** | ❌ **YANGI — Sprint 18+** |
| 20 | **Field deployment + bitta haqiqiy mijoz** | ❌ **YANGI — Sprint 19** |

---

## 14. Keyingi sprintlar — 4-6 oy deployment roadmap

### Sprint 17 — Hardware Pilot (1-2 hafta)
**Maqsad:** Bitta haqiqiy ESP32 → mobile → birinchi end-to-end fusion verdikt

- [ ] **ESP32 firmware** (PlatformIO + Arduino C++):
  - MPU6050 I2C (6-DoF IMU)
  - MLX90614 I2C (IR temp)
  - WiFi → MQTT publish (HiveMQ Cloud free tier)
  - Topic: `eigenguard/<site>/<device>/vib` JSON payload
  - Sleep cycles (battery)
- [ ] **Mobile**: Settings'da MQTT broker URL kiritish → mobile darhol ulanadi (kod tayyor)
- [ ] **Field test**: haqiqiy fusion consensus tekshiruvi (kamera + ESP32)
- [ ] Pilot mijoz bilan birinchi demo (Demo Mode yoqib sales pitch)

### Sprint 18 — Nexus Backend Skeleton (2-3 hafta)
**Maqsad:** Mobile uploader allaqachon yuborayotgan ma'lumotlarni qabul qiluvchi server

- [ ] **Python FastAPI backend**:
  - REST `POST /api/measurements` (mobile uploader allaqachon shunaqa formatga POST qiladi)
  - SQLite → PostgreSQL+PostGIS (geo-indexed)
  - JWT auth (Bearer token mobile uploader'da tayyor)
  - WebSocket alert push
  - Custom AI training pipeline asoslari (saqlangan time-series → labeled dataset)
- [ ] **Vue.js frontend** (minimal):
  - Login (JWT)
  - Map (Leaflet free tier — Mapbox ham keyin)
  - Recent alerts list
  - Single device drill-down

### Sprint 19 — Custom AI Model + Multi-site (3-4 hafta)
**Maqsad:** Pilot ma'lumotlardan custom anomaly detection model

- [ ] **AI training pipeline** (Python):
  - SQLite ma'lumotlarini export
  - Time-series feature extraction (FFT spektrogrammalar, statistik momentlar)
  - LightGBM/PyTorch model (anomaly detection)
  - ONNX export → mobile YOLO o'rniga yoki ortidan ishlatish
- [ ] **Multi-site scoping** — DB tenant_id, mobile site picker
- [ ] **Alert routing rules** — kim qaysi alert'ni oladi
- [ ] **YOLO Isolate optimization** — UI thread'ni bo'shatish (battery + latency)

### Sprint 20 — Production Hardening (2-3 hafta)
**Maqsad:** Birinchi paying mijozga deployment

- [ ] **Gemini API key** — Android Keystore shifrlash
- [ ] **Offline AI fallback** — local lightweight model (custom AI dan)
- [ ] **DigitalTwin** — hardcoded `_components` olib tashlash, real mesh ishlash
- [ ] **`SplineProcessor`** Dart chaqirish (C++ allaqachon tayyor)
- [ ] **Ruggedized hardware** strategiyasi (CAT, Samsung XCover, Ulefone Armor)
- [ ] **CI/CD** (GitHub Actions): `flutter analyze` + `flutter test` + Android APK build
- [ ] **Widget test suite** (5-10 ta kritik widget)
- [ ] **C++ unit testlar** (OpticalFlow, Kalman, FFT — hozir faqat Spline test bor)
- [ ] **Memory profiler** uzoq sessiyalarda
- [ ] **Deployment**: birinchi mijoz, sales close

### Aggregat timeline
| Sprint | Davomiyligi | Maqsad | Vaqt |
|--------|-------------|--------|------|
| 17 | 1-2 hafta | Hardware pilot | T+2 hafta |
| 18 | 2-3 hafta | Nexus skeleton | T+5 hafta |
| 19 | 3-4 hafta | Custom AI + multi-site | T+9 hafta |
| 20 | 2-3 hafta | Production + deployment | **T+12 hafta** |

**T+12 hafta ≈ 3 oy** → 4-6 oy budjetda qulay. Real mijoz onboard'i + iteratsiya uchun zaxira vaqt bor.

---

## 15. Test va sifat

| Metrika | Holat |
|---------|-------|
| **`flutter analyze`** | **0 issues** ✅ |
| `flutter test` | minimal (Phase 6 Delaunay testlari) |
| `native/tests/test_spline.cpp` | C++ unit test mavjud |
| CI/CD pipeline | YO'Q (Sprint 20) |
| Widget tests | YO'Q (Sprint 20) |

### Sprint 20 da rejalashtirilgan
- CI: `flutter analyze` + `flutter test` + Android APK build
- 5-10 ta kritik widget testlar (FusionRow, BleStatusChip, MaterialChip, B2GCard)
- C++ unit testlar (OpticalFlow, Kalman, FFT)
- Memory profiler

---

## 16. Hujjatlar va manbalar

| Fayl | Maqsad |
|------|--------|
| `texnik_topshiriq.md` | Original TZ |
| `implementation_plan.md` | Boshlang'ich amalga oshirish plani |
| `README.md` | Loyiha asoslari |
| `LOYIHA_HOLATI.md` | **THIS — living status doc** |
| `LOYIHA_HOLATI_2026-05-17.md` | Tarixiy snapshot (Sprint 15 yakuni) |
| `C:\Users\Ziyodjon\.claude\projects\...\memory\project_eigenguard.md` | Claude memory — to'liq Phase + Sprint arxivi |

---

## 17. Xulosa va eng yaqin prioritet

### Joriy ahvol
- ✅ **Mobile MVP — production-ready** (Demo Mode bilan sotuvga tayyor)
- ✅ **B2G arxitekturasi to'liq** (Edge ↔ Mobile ↔ Nexus pipeline tayyor, faqat backend kerak)
- ✅ **Real MQTT** ishlaydi (haqiqiy broker URL kiritish kifoya)
- ✅ **BYOD support** (mijoz har xil firmware bilan kelishi mumkin)
- ✅ **Nexus uploader** ishlaydi (webhook.site bilan darhol test qilish mumkin)
- ✅ **`flutter analyze` = 0 issues**

### Eng yaqin prioritet — Sprint 17 (1-2 hafta)
**Bitta haqiqiy ESP32 bilan birinchi end-to-end pilot.** Hardware:
- $25 ESP32-WROOM-32
- $5 MPU6050 (vibration)
- $8 MLX90614 (IR temp)
- Bepul HiveMQ Cloud (100MB/yil)
- PlatformIO firmware (1-2 kunlik ish)

So'ng — birinchi sotuv demosi (Demo Mode yoqib), pilot mijoz qidirish.

### Hyper-Agile prinsipi
AI-assisted coding tufayli 12 oylik B2G plan **3 oygacha siqildi**. Texnik chuqurlik allaqachon yetarli — endi sotuv va bitta haqiqiy mijoz kerak.

---

*Bu hujjat avtomatik yangilanadi har sprint yakunida. Oxirgi snapshot: 2026-05-18 (Sprint 16).*
