# Web MVP va AI Bashoratlash Arxitekturasi (Implementation Plan)

Ushbu reja Web Command Center (Nexus) ni eng yuqori darajadagi (premium) dizaynga o'tkazish va real vaqtda kamera/datchik ma'lumotlarini AI modeli orqali bashorat qilish qismini arxitekturaga mos ravishda qurishga qaratilgan.

## Asosiy Maqsadlar
1. **Mukammal Dizayn**: Vue.js va TailwindCSS yordamida zamonaviy, animatsiyalarga boy, shaffof (glassmorphism) va "Wow" effektini beradigan qorong'i (dark mode) dizaynni yaratish.
2. **AI Bashorat (Prediction) API**: Datchik va kameradan keladigan ma'lumotlarni qabul qilib, anomaliyalarni tahlil qiladigan va xavfni bashorat qiladigan backend mexanizmini qurish.
3. **Jonli Integratsiya**: Backend orqali olingan xulosalarni (Verdict) Web Dashboard'da real vaqtda chiroyli grafiklar bilan ko'rsatish.

---

## 🛑 User Review Required (Tasdiqlashingiz kerak bo'lgan qismlar)

> [!IMPORTANT]
> **Dizayn Estetikasi:** Hozirgi dizayn tizimi TailwindCSS orqali qilingan, ammo uni yanada "premium" qilish uchun biz murakkab animatsiyalar, neon ranglar va maxsus grafik komponentlar (masalan, CSS jadvallar yoki Chart.js) qo'shamiz. Bunga rozimisiz?

> [!TIP]
> **AI Modeli (Mock vs Real):** Hozirgi MVP uchun haqiqiy o'qitilgan neyron tarmoq o'rniga, kelayotgan (vibratsiya va harorat) ma'lumotlari asosida algoritmik tahlil qilib, **AI bashoratini simulyatsiya qiluvchi (Mock AI)** modul yoziladi. Keyinchalik Sprint 19 da bu o'ringa haqiqiy Python (PyTorch/LightGBM) modeli ulanadi. Shu yondashuv ma'qulmi?

---

## O'zgartiriladigan va Yangi Fayllar

Yangi kodlar Frontend (Vue.js) va Backend (FastAPI) qismlariga qo'shiladi.

### 1. Frontend: Mukammal UI va Dashboard

- #### [MODIFY] `nexus/frontend/src/views/Login.vue`
  - Neon gradientlar, shisha effekti (backdrop-blur) va maydonlar uchun silliq animatsiyalar qo'shish.
  - "Premium SaaS" loyihalariga mos keladigan qiziqarli ko'rinishga keltirish.

- #### [MODIFY] `nexus/frontend/src/views/Dashboard.vue`
  - Oddiy jadval va bloklar o'rniga haqiqiy Command Center yaratish.
  - **Live Data Stream:** Datchiklardan kelayotgan oxirgi ma'lumotlarni doimiy yangilanib turadigan grafik (bar/line chart) ko'rinishida chiqarish.
  - **AI Analysis Panel:** AI tomonidan berilgan bashorat (masalan, "Kritik holatga 48 soat qoldi" yoki "Anomaliya ehtimoli: 87%") ni ko'rsatuvchi maxsus blok.

- #### [MODIFY] `nexus/frontend/src/style.css`
  - Loyiha bo'ylab ishlatiladigan global animatsiyalar (`@keyframes`), maxsus scrollbar dizaynlari va qorong'i mavzu (dark theme) o'zgaruvchilarini kiritish.

### 2. Backend: AI Prediction Arxitekturasi

- #### [NEW] `nexus/backend/app/api/predict.py` (yoki `measurements.py` ni kengaytirish)
  - `POST /api/v1/measurements/analyze` API'si yaratiladi.
  - Telefon yoki ESP32 dan kelgan `amplitude_mm`, `frequency_hz`, `camera_risk` ma'lumotlarini qabul qiladi.
  - **AI Mock Engine:** Kiritilgan qiymatlarga asosan kompleks formula orqali tizimning "Sog'lomlik indeksi"ni (Health Index) va qachon buzilishi mumkinligini hisoblaydi.

- #### [MODIFY] `nexus/backend/app/main.py`
  - WebSockets tizimi (`ws.py`) bilan aloqani mustahkamlash, chunki AI analizi javoblari to'g'ridan-to'g'ri Web Dashboard'ga (jonli) uzatilishi kerak.

---

## Verifikatsiya (Qanday tekshiramiz?)

1. **Backend Tekshiruvi:** Swagger UI (`http://localhost:8000/docs`) orqali `analyze` endpointiga test ma'lumot jo'natib, AI xulosasini ko'ramiz.
2. **Frontend Tekshiruvi:** `npm run dev` orqali Vite serverni ko'tarib:
   - Login pageni "Wow" dizaynini ko'ramiz.
   - Dashboard'ga kirib, sun'iy ravishda (mock) yuborilgan datchik signallari AI tomonidan qanday tahlil qilinib, ekranda chiroyli tarzda (grafik va ogohlantirishlar bilan) aks etayotganini tekshiramiz.

Agar ushbu reja sizga ma'qul bo'lsa, **tasdiqlang** va men kodlarni yozishni (Execute) boshlayman.
