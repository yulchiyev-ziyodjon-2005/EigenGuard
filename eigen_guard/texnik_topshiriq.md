# EIGENGUARD TIZIMI: TO'LIQ TEXNIK TOPSHIRIQ (TZ) VA ARXITEKTURA HUJJATI
**Hujjat versiyasi**: 1.0 (Release Candidate)
**Loyiha nomi**: EigenGuard - Structural Health Monitoring & Predictive Maintenance
**Hujjatning maqsadi**: Loyihaning arxitekturasi, texnologik steki, matematik apparati va funksional qatlamlarini barcha muhandis va dasturchilar uchun mukammal tarzda hujjatlashtirish.

---

## 1. LOYIHA HAQIDA UMUMIY MA'LUMOT (EXECUTIVE SUMMARY)
**EigenGuard** - bu sanoat uskunalari, binolar, transport va boshqa mexanik tuzilmalarning nosozliklarini ularning yuz berishidan oldin (Predictive Maintenance) kashf etuvchi chuqur texnologik (DeepTech) mobil va desktop dasturiy ta'minotidir.
Unda an'anaviy, qimmatbaho, va murakkab o'rnatiluvchi qattiq jism datchiklaridan (IoT Sensors) butunlay voz kechilib, **Smartfonlarning ichki resurslari** (Kamera, IMU, Mikrofon, LiDAR) orqali *Edge-Computing* asosida o'lchovlar olinadi va real vaqtda tahlil qilinadi.

---

## 2. TEXNOLOGIK STACK VA ARXITEKTURA QATLAMLARI

Loyiha qat'iy ravishda Modulli Arxitekturaga (Modular Architecture) asoslangan bo'lib, o'zaro bog'liq 4 ta mustaqil qatlamdan (Layer) iborat.

### 2.1. Presentation Layer (Frontend & UI)
*   **Framerwork**: Flutter (Dart) — SDK >=3.5.0.
*   **UI/UX Paradigma**: Sanoat va harbiylashtirilgan "Glassmorphism HUD" (Heads-Up Display) dizayni. Dark mode (Qorong'u mavzu) asosida `AppTheme` yordamida markazlashgan dizayn-tizim.
*   **State Management**: Hozircha Local State (`setState` va `ValueNotifier`) orqali UI renderini yuqori FPS (60+) da ushlab turish mexanizmi qo'llaniladi (kameralar oqimini bloklamaslik uchun `Stack` qatlamida alohida izolyatsiya qilingan).

### 2.2. Processing Layer (Native C++ Engine - FFI)
Dasturning asosiy hisoblash mantiqi Dart'da emas, balki to'g'ridan-to'g'ri CPU reestrlarida ishlovchi C++ yadrosida yozilgan.
*   **Til**: C++17 (`CMakeLists.txt` orqali ulangan).
*   **Bog'liqlik (Bridge)**: `dart:ffi` yordamida asinxron chaqiruvlar.
*   **Asosiy Modullar**:
    *   `optical_flow.cpp` (Lukas-Kanade algoritmi: Kadrlar orasida piksellar yerdan siljishini hisoblaydi).
    *   `fft_processor.cpp` (Ovoz to'lqinlarini Fast Fourier Transform yordamida garmonik chastotalarga (Hz) ajratadi).
    *   `kalman_filter.cpp` (Telefonning o'zidagi tabiiy titrash va inson qo'lining qaltirash shovqinlarini o'lchov ma'lumotlaridan tozalaydi).
    *   `spline_processor.cpp` (Trendlarni o'rganish va signallarni chiziqli interpolyatsiya qilish).

### 2.3. AI va Machine Learning Layer
*   **Computer Vision (Ko'rish tizimi)**: Ultralytics YOLO2026 Nano Segmentation (`yolo26n-seg.onnx`, 11 MB). NMS (Non-Maximum Suppression) arxitekturasisiz, End-to-End optimizatsiyalangan, GPU va CPU ustida ishlay oladigan ONNX modeli.
*   **LLM (Generative AI)**: Google Gemini (`google_generative_ai`). C++ dan kelgan matematik qiymatlarni qabul qilib, ularga muhandislik xulosasi beradi (Troubleshooting).

### 2.4. Hardware & Sensor Layer
*   **Camera API**: Tasvir oqimini (YUV formatda) o'qish va YOLO ga uzatish.
*   **IMU Service**: Akselerometr (m/s²) va Giroskop (rad/s) o'lchovlari orqali qurilmaning xususiy o'rnini (Drift) hisoblash.
*   **Microphone (AudioService)**: 44.1kHz diskret chastotada Raw PCM tovush to'lqinini o'qish (Mikro-darzketish, sirpanish ovozlarini aniqlash).

---

## 3. ASOSIY FUNKSIONAL TALABLAR (CORE WORKFLOW)

### 3.1. Obyektni Tanish va Interaktiv Tanlov (Segmentation)
1.  **Dasturga kirish**: Kamera ishga tushadi, YOLO kadrni skanerlashni boshlaydi.
2.  **Lokalizatsiya**: Obyekt (masalan, motor) atrofida quti (Bounding Box) va murakkab tana qismining chegarasi (Polygon) chiziladi.
3.  **Tap-to-Lock (Tanlash)**: Dasturning aynan kerakli uskuna qismini tahlil qilishi uchun foydalanuvchi ekrandagi poligon ustiga bosadi. Obyekt fokusga qulflanadi (Boshqa yot jismlar hisoblanmaydi).

### 3.2. Skanerlash va "3D Digital Twin" Yaratish (AR-Guided Scan)
1.  **Trigger**: Dashboard ekranida **"3D Maket Yaratish"** (Create 3D Model) tugmasi faqat obyekt tanlangandagina aktivlashadi.
2.  **Guided Navigation (Yo'riqnoma)**: Tugma bosilgach, foydalanuvchiga obyekti atrofida sekin aylanib yurish buyuriladi (UI ko'rsatmalari chiqadi).
3.  **Point Cloud Generation (Nuqtalar Buluti)**: 
    *   Kamera siljigani sari (`IMU` bilan birga) poligon *ichiga* tushuvchi barcha piksellar fazodagi (X, Y, Z) koordinataga ko'chiriladi.
    *   Voxel Grid Downsampling (masalan 1 sm rezolyutsiyada) orqali ortiqcha takroriy nuqtalar o'chirilib, xotira tozalanadi (Max 10 000 - 50 000 nuqta).

### 3.3. Matematik Hisoblash va Bashorat (Predictive Algorithms)
Nuqtalar olinayotgan bir vaqtda fon rejimida jismning **salomatlik (Health) formulasi** hisoblanadi.
*   **Formula Asosi**: $Risk = \alpha \cdot F(x) + \beta \cdot A(x)$ 
    *   Bu yerda $A(x)$ — obyekt tebranishining haqiqiy millimetrlardagi qiymati.
    *   $F(x)$ — dominant audio/vibratsion garmonika (Hz).
*   **Time-To-Failure (Ishdan chiqishgacha qolgan vaqt)**: Agar obyektning vibratsiyasi normadan yuqori bo'lsa, Least Squares (Eng kichik kvadratlar) yoki Eksponensial regressiya usulida chiziq tortilib, obyektning 85% xavf darajasiga qachon yetib borishi (masalan, *48 soatdan keyin*) hisoblanadi.

### 3.4. Diagnostika va Heatmap Ko'rinishi (3D Model Visualizer)
1.  **Raqamli Egizak Oynasi**: Olingan 3D nuqtalar buluti (Point Cloud) qora fonda, sanoat gologrammasi ko'rinishida aylanib turadi.
2.  **Nuqsonni Ko'rsatish (Heatmap)**: C++ yadrosi aynan obyektning qaysi joyida (qaysi poligonida) tebranish eng kuchli ekanligini topgan bo'lsa, o'sha joy 3D maket ustida **Qizil rangda miltillab** (Pulse) ajralib turadi.

### 3.5. AI Konsultant Integratsiyasi (Muhandis Yordamchi)
*   **Trigger**: Diagnostika oynasida "AI bilan hal qilish" tugmasi.
*   **Context Payload**: Tizim Aiga yashirincha quyidagi datani kiritadi: 
    *   *Obyekt*: Sanoat Suv Nasosi.
    *   *Chastota*: 120 Hz (Akkord anomaliyasi).
    *   *Amplituda*: 2.4 mm (Kritik darajada).
    *   *Yashash davri*: ~72 soat.
*   **Chiqish**: AI foydalanuvchiga qaysi ehtiyot qismlarni zudlik bilan almashtirish va mexanik profilaktika qanday amalga oshirilishi kerakligini O'zbek yoki Ingliz tilida tushuntirib beradi.

---

## 4. NO-FUNKSIONAL TALABLAR

| Mezon | Talab | Yechim |
| :--- | :--- | :--- |
| **Tezkorlik (Performance)** | Video va hisoblash kadrni bloklamasligi shart (Min 30 FPS). | Og'ir AI ishlari `Isolate` da ishlaydi. C++ native threadlarda ishlaydi. |
| **Maxfiylik (Privacy)** | Ma'lumot va video internetga yuborilmasligi kerak. | Edge-computing tamoyili: YOLO modeli, SQLite, C++ yadrosi 100% oflayn ishlaydi (faqat matnli maslahat uchun Gemini API internetga ulanadi). |
| **Xotira va RAM** | 3D Maket telefonni qotirib qo'ymasligi lozim. | Point Cloud `Voxel Grid Downsampling` texnikasi orqali zichlik cheklanadi (Ortiqcha nuqtalar ignor qilinadi). |
| **Muvofiqlik (Cross-platform)**| Windows PC va Android OS da ishlashi lozim. | FFI CMake kodlari Android NDK va Windows MSVC ga moslangan. |

---

## 5. MA'LUMOTLAR BAZASI (DATA DICTIONARY)

**Jadval nomi**: `measurements`
SQFlite bazasida saqlanadigan o'lchovlar tarixiy strukturasi:
*   `id` (INTEGER, PK): Unikal identifikator.
*   `timestamp` (TEXT): O'lchov vaqti.
*   `risk_percent` (REAL): Hisoblangan umumiy xavf miqdori (0.0 - 100.0).
*   `frequency` (REAL): Dominant garmonik tebranish (Hz).
*   `amplitude` (REAL): Tebranishning haqiqiy amplitudasi (mm).
*   `spline_error` (REAL): Model xatoligi (Noise margin).
*   `duration_seconds` (INTEGER): Sessiya davomiyligi.
*   `risk_level` (TEXT): Enum holati (NORMAL, WARNING, CRITICAL).
*   `object_label` (TEXT): Tahlil qilingan uskunaning toifasi (YOLO yorlig'i, misol uchun "[MOTOR]").

---

## 6. KELAJAKDAGI MAQSADLAR VA MIQYOS (FUTURE SCOPE)
1.  **Termal Analiz**: Maxsus qurilmalar orqali infraqizil kameralarni ulash va issiqlikni ham 3D maket ustiga qo'yish (Thermal Heatmap).
2.  **Mesh Reconstruction**: Nuqtalar buluti (Point Cloud) ustidan avtomatik triangulyatsiya qilib uni aniq yaxlit Sirtga (Mesh .obj) aylantirish algoritmini C++ ga kiritish.
3.  **To'da Mantiqi (Fleet Management)**: O'nlab zavodlar ma'lumotlarini markaziy serverga yuborish va katta ma'lumotlar tahlilini (Big Data Analytics) amalga oshirish.

---
**Tasdiqlandi**: Antigravity AI  
**Loyiha Muallifi**: Ziyodjon  
**O'zgarishlar statusi**: Ushbu TZ ga asosan 3D Guided Scanning qismi va Matematik AI diagnostika joriy qilinadi.
