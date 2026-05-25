# EigenGuard Nexus MVP Kodlash Strategiyasi

Ushbu hujjat `implementation_plan.md` dagi MVP maqsadlarini bajarish uchun amaliy kodlash strategiyasini belgilaydi. Asosiy fokus `nexus` Web Command Center: premium Vue dashboard, FastAPI asosidagi mock AI prediction API va real-time dashboard integratsiyasi.

## MVP Chegarasi

MVP quyidagi natijani berishi kerak:

- Vue.js + TailwindCSS asosida zamonaviy, dark-mode, command-center ko'rinishidagi web panel.
- FastAPI backendda sensor/kamera qiymatlarini qabul qiladigan AI prediction endpoint.
- Haqiqiy ML modeli o'rniga deterministic mock AI engine.
- Prediction natijalarini dashboardda jonli ko'rsatish.
- Mavjud mobile uploader va measurement API oqimini buzmaslik.

## Muhim Arxitektura Qarorlari

### 1. Real ML emas, Mock AI Engine

MVP bosqichida PyTorch, LightGBM yoki alohida model serving kiritilmaydi. Buning o'rniga `amplitude_mm`, `frequency_hz` va `camera_risk` qiymatlaridan deterministic formula orqali quyidagilar hisoblanadi:

- `health_index`
- `anomaly_probability`
- `hours_to_critical`
- `risk_level`
- `verdict`
- `recommendations`

Bu yondashuv Sprint 19 da haqiqiy model ulashga tayyor API contract beradi.

### 2. Measurement API buzilmaydi

Mavjud `POST /api/v1/measurements` endpoint saqlanadi. Yangi tahlil oqimi alohida endpoint orqali kiritiladi:

```http
POST /api/v1/measurements/analyze
```

Keyinchalik oddiy measurement yaratilganda avtomatik analysis qilish mumkin, lekin MVP uchun explicit `analyze` endpoint xavfsizroq.

### 3. WebSocket Ikki Rolga Ajratiladi

Hozirgi websocket mobile device command delivery uchun ishlaydi. MVP uchun dashboard browserlariga ham real-time event yuborish kerak.

Tavsiya:

- mobile websocket: device command va ack uchun qoladi;
- dashboard websocket: tenant bo'yicha analysis eventlarni oladi;
- `ws_manager` ichida device connection va dashboard connection alohida yuritiladi.

Example dashboard event:

```json
{
  "kind": "analysis",
  "data": {
    "health_index": 72,
    "anomaly_probability": 0.87,
    "hours_to_critical": 48,
    "risk_level": "HIGH",
    "verdict": "Anomaliya ehtimoli yuqori"
  }
}
```

## Backend Kodlash Rejasi

### 1. Prediction Schema

`nexus/backend/app/api/measurements.py` ichida yoki yangi `predict.py` faylda Pydantic schemalar yaratiladi.

Input:

```python
class PredictionInput(BaseModel):
    device_id: str | None = None
    timestamp: datetime | None = None
    amplitude_mm: float
    frequency_hz: float
    camera_risk: float = Field(ge=0, le=100)
```

Output:

```python
class PredictionOutput(BaseModel):
    health_index: float
    anomaly_probability: float
    hours_to_critical: float | None
    risk_level: str
    verdict: str
    recommendations: list[str]
    created_at: datetime
```

### 2. Mock AI Formula

Formula sodda, tushunarli va keyin almashtirish oson bo'lishi kerak.

Tavsiya etilgan signal vaznlari:

- amplitude risk: 45%
- frequency risk: 30%
- camera risk: 25%

Natijadan:

- `health_index = 100 - total_risk`
- `anomaly_probability = total_risk / 100`
- `risk_level` threshold orqali belgilanadi:
  - `0-34`: `LOW`
  - `35-59`: `MEDIUM`
  - `60-79`: `HIGH`
  - `80-100`: `CRITICAL`

### 3. Analyze Endpoint

Endpoint vazifalari:

1. Auth va tenant contextni tekshiradi.
2. Payloadni validatsiya qiladi.
3. Mock AI engine orqali analysis hisoblaydi.
4. Dashboard websocketlariga `analysis` event broadcast qiladi.
5. Analysis javobini REST response sifatida qaytaradi.

### 4. WebSocket Manager Kengaytmasi

`nexus/backend/app/core/ws_manager.py` quyidagicha kengaytiriladi:

- mavjud `device_id -> websocket` mapping saqlanadi;
- yangi `tenant_id -> set[websocket]` mapping qo'shiladi;
- `connect_dashboard(tenant_id, websocket)`;
- `disconnect_dashboard(tenant_id, websocket)`;
- `broadcast_to_tenant(tenant_id, message)`.

MVP uchun in-memory manager yetarli. Multi-worker production uchun keyin Redis pub/sub kerak bo'ladi.

## Frontend Kodlash Rejasi

### 1. TypeScript Types

`nexus/frontend/src/lib/types.ts` ichiga prediction uchun tiplar qo'shiladi:

```ts
export interface PredictionAnalysis {
  health_index: number
  anomaly_probability: number
  hours_to_critical: number | null
  risk_level: string
  verdict: string
  recommendations: string[]
  created_at: string
}
```

### 2. Dashboard WebSocket Client

Yangi composable yoki `Dashboard.vue` ichida websocket ulanishi yoziladi.

Vazifalar:

- tenant context bilan dashboard websocketga ulanadi;
- `analysis` eventni qabul qiladi;
- latest AI panelni yangilaydi;
- live chart data arrayga yangi nuqta qo'shadi;
- reconnect mexanizmini MVP darajada qo'llaydi.

### 3. Dashboard Command Center UI

`nexus/frontend/src/views/Dashboard.vue` quyidagi bloklarga ajratiladi:

- yuqori status row: devices, online, critical, latest AI verdict;
- live signal chart: amplitude, frequency va risk trend;
- AI Analysis Panel: health index, anomaly probability, hours to critical;
- recent measurements table;
- devices table.

MVP uchun Chart.js qo'shish shart emas. Hozirgi dependency listda chart kutubxonasi yo'q, shuning uchun Vue + SVG/CSS sparkline yetarli va yengilroq.

### 4. Login Premium Polish

`nexus/frontend/src/views/Login.vue` yangilanadi:

- glassmorphism panel;
- gradient border;
- neon focus states;
- loading disabled state;
- existing seed account information saqlanadi.

### 5. Global Styling

`nexus/frontend/src/style.css` ichiga quyidagilar qo'shiladi:

- global dark theme polish;
- custom scrollbar;
- glow utilities;
- chart pulse animation;
- glass panel classlari;
- dashboard background texture yoki subtle grid.

Muhim: UI "wow" ko'rinsin, lekin command-center workflowga xalaqit bermasin. Jadval va indikatorlar tez skan qilinadigan bo'lishi kerak.

## Ish Ketma-ketligi

1. Backend prediction schema va mock AI formula.
2. `POST /api/v1/measurements/analyze` endpoint.
3. `ws_manager`ga tenant dashboard broadcast qo'shish.
4. Dashboard websocket endpoint qo'shish.
5. Frontend prediction types va websocket client.
6. Dashboard live analysis panel va SVG/CSS chart.
7. Login va global style polish.
8. Build va manual verification.

## Verifikatsiya

### Backend

- Swagger UI orqali `POST /api/v1/measurements/analyze` tekshiriladi.
- Valid payload prediction response qaytarishi kerak.
- Invalid `camera_risk`, `amplitude_mm` yoki `frequency_hz` qiymatlari validation error berishi kerak.
- Analyze chaqirilganda dashboard websocketga `analysis` event ketishi kerak.

### Frontend

- `npm run build` muvaffaqiyatli o'tishi kerak.
- Login page premium ko'rinishda render bo'lishi kerak.
- Dashboard REST orqali devices va measurementsni yuklashi kerak.
- Dashboard websocket orqali latest analysis panelni yangilashi kerak.
- Live chart yangi analysis eventlarda siljib borishi kerak.

## Risklar va Tavsiyalar

- WebSocket auth cookie bilan ishlashi kerak; agar cookie bilan murakkablashsa, MVP uchun token query param ishlatilishi mumkin.
- Chart.js kabi yangi dependency faqat zarurat bo'lsa qo'shilsin; MVPda SVG/CSS chart yetarli.
- Mock AI engine alohida helper funksiyada yozilsin, keyin real model bilan almashtirish oson bo'ladi.
- Existing mobile uploader flow buzilmasin; yangi endpoint alohida saqlansin.
- `ws_manager` in-memory bo'lgani uchun production multi-worker scale uchun Redis pub/sub keyingi sprintga qoldiriladi.

## Definition of Done

MVP bajarilgan hisoblanadi, agar:

- login va dashboard premium dark command-center ko'rinishga ega bo'lsa;
- backend `analyze` endpoint sensor/kamera inputlardan AI verdict qaytarsa;
- dashboard REST data va websocket analysis eventlarni ko'rsatsa;
- frontend build xatosiz o'tsa;
- mavjud auth, tenant va measurement oqimlari regressiyaga uchramasa.
