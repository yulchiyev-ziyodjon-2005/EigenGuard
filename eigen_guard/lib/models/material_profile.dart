import 'package:flutter/material.dart';

/// EigenGuard — Universal Material Profile
///
/// Har bir material o'ziga xos fizik xususiyatlarga ega:
///   • kritik amplituda (mm) — ApproxProcessor `y_limit`
///   • rezonans diapazoni (Hz) — normal ish chastotalari
///   • xavfli chastota (Hz) — strukturaviy rezonans
///   • damping (zaiflashuv koeffitsienti) — material qattiqligi
///   • risk og'irliklari (amplitud vs chastota nisbati)
///
/// Manbalar:
///   ISO 10816-3 (sanoat mashinalari)
///   ISO 4866 (binolar va inshootlar)
///   EN 1992 (beton konstruksiyalar)
///   ASHRAE (mexanik tizimlar)
class MaterialProfile {
  /// Unik identifikator ('steel', 'concrete', ...)
  final String id;

  /// Foydalanuvchi ko'radigan nom (O'zbek tilida)
  final String displayName;

  /// Texnik / Inglizcha nom (Gemini AI uchun)
  final String technicalName;

  /// Kritik amplituda chegarasi (mm) — ApproxProcessor `y_limit`
  /// Bu chegaradan oshganda obyekt buzilishi yaqin
  final double criticalAmplitudeMm;

  /// Ogohlantirish amplituda chegarasi (mm) — kuzatuv talab qiladi
  final double warningAmplitudeMm;

  /// Tabiiy rezonans chastota diapazoni (Hz, min)
  final double resonanceMinHz;

  /// Tabiiy rezonans chastota diapazoni (Hz, max)
  final double resonanceMaxHz;

  /// Xavfli rezonans chastota (Hz) — strukturaviy buzilish mumkin
  final double dangerFrequencyHz;

  /// Damping ratio (zaiflashuv koeffitsienti, 0.0 — 1.0)
  /// Yuqori damping = energiya tez yo'qoladi (yog'och)
  /// Past damping = uzoq tebranadi (shisha, po'lat)
  final double dampingRatio;

  /// Risk formulasidagi amplitud og'irligi (0.0 — 1.0)
  final double weightAmplitude;

  /// Risk formulasidagi chastota og'irligi (0.0 — 1.0)
  /// weightAmplitude + weightFrequency = 1.0
  final double weightFrequency;

  /// Asosiy nosozlik turlari (AI consult va diagnostika uchun)
  final List<String> failureModes;

  /// UI rangi (3D Twin, HUD chip, indikator)
  final Color color;

  /// Material ikoni
  final IconData icon;

  /// Material zichligi (kg/m³) — Active acoustic probing uchun (Phase 2)
  final double densityKgM3;

  /// Young's Modulus (GPa) — qattiqlik (Phase 2 da ishlatiladi)
  final double youngsModulusGPa;

  const MaterialProfile({
    required this.id,
    required this.displayName,
    required this.technicalName,
    required this.criticalAmplitudeMm,
    required this.warningAmplitudeMm,
    required this.resonanceMinHz,
    required this.resonanceMaxHz,
    required this.dangerFrequencyHz,
    required this.dampingRatio,
    required this.weightAmplitude,
    required this.weightFrequency,
    required this.failureModes,
    required this.color,
    required this.icon,
    required this.densityKgM3,
    required this.youngsModulusGPa,
  });

  /// Joriy amplituda va chastotaga ko'ra normallashtirilgan xavf foizi (0 — 100)
  double calculateRisk(double currentAmpMm, double currentFreqHz) {
    // Amplituda xavfi: kritik chegaraga nisbati
    final ampRisk = (currentAmpMm / criticalAmplitudeMm).clamp(0.0, 1.0);

    // Chastota xavfi: rezonans yaqinligi (dangerFreqHz ga qancha yaqin — shuncha xavfli)
    double freqRisk;
    if (dangerFrequencyHz <= 0) {
      // Chastota muhim emas — ampDan to'liq
      freqRisk = 0.0;
    } else {
      final delta = (currentFreqHz - dangerFrequencyHz).abs();
      // ±20% diapazonda 100%, undan tashqarida 0 ga keskin tushadi
      final tolerance = dangerFrequencyHz * 0.2;
      if (delta < tolerance) {
        freqRisk = 1.0 - (delta / tolerance);
      } else {
        freqRisk = 0.0;
      }
    }

    return ((weightAmplitude * ampRisk + weightFrequency * freqRisk) * 100.0)
        .clamp(0.0, 100.0);
  }

  /// Risk darajasi (matn)
  String riskLevelLabel(double riskPercent) {
    if (riskPercent < 25) return 'NORMAL';
    if (riskPercent < 50) return 'KUZATUV';
    if (riskPercent < 75) return 'OGOHLANTIRISH';
    return 'KRITIK';
  }

  @override
  String toString() => '$displayName ($technicalName)';
}

/// ════════════════════════════════════════════════════════════════════════════
/// 12 ta UNIVERSAL MATERIAL PRESETI
/// ════════════════════════════════════════════════════════════════════════════
class MaterialPresets {
  MaterialPresets._();

  // ─── METALLAR ──────────────────────────────────────────────────────────────

  /// Po'lat — sanoat mashinalari, podshipniklar, valar
  /// ISO 10816-3 Class III: 2.8mm RMS = boundary
  static const steel = MaterialProfile(
    id: 'steel',
    displayName: 'Po\'lat',
    technicalName: 'Steel (Carbon/Stainless)',
    criticalAmplitudeMm: 2.8,
    warningAmplitudeMm: 1.4,
    resonanceMinHz: 10.0,
    resonanceMaxHz: 2000.0,
    dangerFrequencyHz: 1000.0,
    dampingRatio: 0.001,
    weightAmplitude: 0.6,
    weightFrequency: 0.4,
    failureModes: [
      'Metall charchog\'i (fatigue)',
      'Podshipnik buzilishi',
      'Korroziya',
      'Disbalans',
      'Misalignment',
    ],
    color: Color(0xFF78909C),
    icon: Icons.settings,
    densityKgM3: 7850,
    youngsModulusGPa: 200,
  );

  /// Alyuminiy — yengil mashinasozlik, aviatsiya
  static const aluminum = MaterialProfile(
    id: 'aluminum',
    displayName: 'Alyuminiy',
    technicalName: 'Aluminum',
    criticalAmplitudeMm: 4.5,
    warningAmplitudeMm: 2.0,
    resonanceMinHz: 20.0,
    resonanceMaxHz: 3000.0,
    dangerFrequencyHz: 1500.0,
    dampingRatio: 0.002,
    weightAmplitude: 0.55,
    weightFrequency: 0.45,
    failureModes: [
      'Charchog\' yorig\'i',
      'Oksid plyonkasi',
      'Termal kengayish',
      'Galvanik korroziya',
    ],
    color: Color(0xFFB0BEC5),
    icon: Icons.layers,
    densityKgM3: 2700,
    youngsModulusGPa: 70,
  );

  // ─── QURILISH MATERIALLARI ─────────────────────────────────────────────────

  /// Beton — bino konstruksiyalari, ko'priklar, ustunlar
  /// EN 1992: 0.3-0.5 mm = mikro-tirqish chegarasi
  static const concrete = MaterialProfile(
    id: 'concrete',
    displayName: 'Beton',
    technicalName: 'Concrete (Reinforced)',
    criticalAmplitudeMm: 0.5,
    warningAmplitudeMm: 0.2,
    resonanceMinHz: 5.0,
    resonanceMaxHz: 50.0,
    dangerFrequencyHz: 20.0,
    dampingRatio: 0.05,
    weightAmplitude: 0.7,
    weightFrequency: 0.3,
    failureModes: [
      'Mikro va makro tirqishlar',
      'Armatura korroziyasi',
      'Karbonizatsiya',
      'Sulfat hujumi',
      'Yuk ostida deformatsiya',
    ],
    color: Color(0xFFBDBDBD),
    icon: Icons.foundation,
    densityKgM3: 2400,
    youngsModulusGPa: 30,
  );

  /// G'isht / Tosh / Devor
  /// Tarixiy binolar — ko'p mahalliy konstruksiyalar
  static const brick = MaterialProfile(
    id: 'brick',
    displayName: 'G\'isht / Tosh',
    technicalName: 'Brick / Masonry',
    criticalAmplitudeMm: 1.0,
    warningAmplitudeMm: 0.4,
    resonanceMinHz: 5.0,
    resonanceMaxHz: 30.0,
    dangerFrequencyHz: 15.0,
    dampingRatio: 0.07,
    weightAmplitude: 0.75,
    weightFrequency: 0.25,
    failureModes: [
      'Loy/sement yorig\'i',
      'Tuz kristallanishi',
      'Suv ta\'siri',
      'Asos cho\'kishi',
      'Issiqlik-sovuq sikllari',
    ],
    color: Color(0xFFA1887F),
    icon: Icons.grid_on,
    densityKgM3: 1900,
    youngsModulusGPa: 20,
  );

  /// Granit / Tabiiy tosh — ko'prik tayanchlari, monumental
  static const granite = MaterialProfile(
    id: 'granite',
    displayName: 'Granit / Tabiiy tosh',
    technicalName: 'Granite / Natural Stone',
    criticalAmplitudeMm: 0.8,
    warningAmplitudeMm: 0.3,
    resonanceMinHz: 5.0,
    resonanceMaxHz: 100.0,
    dangerFrequencyHz: 50.0,
    dampingRatio: 0.02,
    weightAmplitude: 0.7,
    weightFrequency: 0.3,
    failureModes: [
      'Tabiiy nurashuv',
      'Tarmoq yorig\'i',
      'Mineral kristal o\'sishi',
      'Termal yorik',
    ],
    color: Color(0xFF607D8B),
    icon: Icons.terrain,
    densityKgM3: 2700,
    youngsModulusGPa: 60,
  );

  /// Asfalt — yo'l qoplamasi
  static const asphalt = MaterialProfile(
    id: 'asphalt',
    displayName: 'Asfalt',
    technicalName: 'Asphalt Pavement',
    criticalAmplitudeMm: 3.0,
    warningAmplitudeMm: 1.0,
    resonanceMinHz: 1.0,
    resonanceMaxHz: 50.0,
    dangerFrequencyHz: 10.0,
    dampingRatio: 0.15,
    weightAmplitude: 0.65,
    weightFrequency: 0.35,
    failureModes: [
      'Yo\'l yoriqlari (rutting)',
      'Krokodil yoriq',
      'Suv eroziyasi',
      'UV degradatsiya',
      'Termal egilish',
    ],
    color: Color(0xFF424242),
    icon: Icons.add_road,
    densityKgM3: 2300,
    youngsModulusGPa: 5,
  );

  // ─── ORGANIK / KOMPOZIT ────────────────────────────────────────────────────

  /// Yog'och — to'sin, mebel, eski binolar
  /// Yuqori damping — tebranishni tez yutadi
  static const wood = MaterialProfile(
    id: 'wood',
    displayName: 'Yog\'och',
    technicalName: 'Wood / Timber',
    criticalAmplitudeMm: 12.0,
    warningAmplitudeMm: 5.0,
    resonanceMinHz: 2.0,
    resonanceMaxHz: 200.0,
    dangerFrequencyHz: 80.0,
    dampingRatio: 0.10,
    weightAmplitude: 0.5,
    weightFrequency: 0.5,
    failureModes: [
      'Chirish (rot)',
      'Qurish yorig\'i',
      'Mikoz (zamburug\')',
      'Termit hujumi',
      'Tola siljishi',
      'Kosmik nam',
    ],
    color: Color(0xFF8D6E63),
    icon: Icons.forest,
    densityKgM3: 700,
    youngsModulusGPa: 12,
  );

  /// Kompozit — uglerod tola, shisha tola
  static const composite = MaterialProfile(
    id: 'composite',
    displayName: 'Kompozit (Karbon/Shisha tola)',
    technicalName: 'Composite (CFRP/GFRP)',
    criticalAmplitudeMm: 6.0,
    warningAmplitudeMm: 2.5,
    resonanceMinHz: 10.0,
    resonanceMaxHz: 500.0,
    dangerFrequencyHz: 250.0,
    dampingRatio: 0.03,
    weightAmplitude: 0.6,
    weightFrequency: 0.4,
    failureModes: [
      'Delaminatsiya',
      'Tola sinishi',
      'Matritsa yorig\'i',
      'Namlik shimishi',
      'UV degradatsiya',
    ],
    color: Color(0xFF455A64),
    icon: Icons.dynamic_form,
    densityKgM3: 1600,
    youngsModulusGPa: 70,
  );

  // ─── BOSHQA ────────────────────────────────────────────────────────────────

  /// Plastik / Polimer — quvurlar, idishlar
  static const plastic = MaterialProfile(
    id: 'plastic',
    displayName: 'Plastik / Polimer',
    technicalName: 'Plastic / Polymer',
    criticalAmplitudeMm: 8.0,
    warningAmplitudeMm: 3.0,
    resonanceMinHz: 5.0,
    resonanceMaxHz: 1000.0,
    dangerFrequencyHz: 200.0,
    dampingRatio: 0.20,
    weightAmplitude: 0.55,
    weightFrequency: 0.45,
    failureModes: [
      'Mo\'rt yorig\'i',
      'UV degradatsiya',
      'Termal deformatsiya',
      'Kimyoviy ta\'sir',
      'Charchog\'i',
    ],
    color: Color(0xFF26A69A),
    icon: Icons.water_drop,
    densityKgM3: 1200,
    youngsModulusGPa: 3,
  );

  /// Shisha — derazalar, sanoat shishasi
  /// Juda past damping — uzoq tebranadi
  static const glass = MaterialProfile(
    id: 'glass',
    displayName: 'Shisha',
    technicalName: 'Glass',
    criticalAmplitudeMm: 1.5,
    warningAmplitudeMm: 0.5,
    resonanceMinHz: 100.0,
    resonanceMaxHz: 10000.0,
    dangerFrequencyHz: 3000.0,
    dampingRatio: 0.001,
    weightAmplitude: 0.5,
    weightFrequency: 0.5,
    failureModes: [
      'Mikro yorig\'i',
      'Sirt nuqsoni (nick)',
      'Termal shok',
      'Akustik rezonansda sinish',
    ],
    color: Color(0xFF80DEEA),
    icon: Icons.window,
    densityKgM3: 2500,
    youngsModulusGPa: 70,
  );

  /// Ceramic — keramika, kafel, sanoat ceramic
  static const ceramic = MaterialProfile(
    id: 'ceramic',
    displayName: 'Ceramic / Kafel',
    technicalName: 'Ceramic',
    criticalAmplitudeMm: 1.2,
    warningAmplitudeMm: 0.4,
    resonanceMinHz: 50.0,
    resonanceMaxHz: 5000.0,
    dangerFrequencyHz: 1500.0,
    dampingRatio: 0.005,
    weightAmplitude: 0.6,
    weightFrequency: 0.4,
    failureModes: [
      'Mo\'rt yorig\'i',
      'Termal shok',
      'Sirt nuqsoni',
      'Glazura ko\'chishi',
    ],
    color: Color(0xFFFFE0B2),
    icon: Icons.grid_view,
    densityKgM3: 2600,
    youngsModulusGPa: 200,
  );

  /// Universal — material aniqlanmagan yoki aralash
  /// Konservativ chegaralar — eng past kritik amplituda
  static const universal = MaterialProfile(
    id: 'universal',
    displayName: 'Universal (aniqlanmagan)',
    technicalName: 'Generic / Unknown',
    criticalAmplitudeMm: 3.0,
    warningAmplitudeMm: 1.0,
    resonanceMinHz: 1.0,
    resonanceMaxHz: 5000.0,
    dangerFrequencyHz: 500.0,
    dampingRatio: 0.05,
    weightAmplitude: 0.6,
    weightFrequency: 0.4,
    failureModes: [
      'Umumiy mexanik nosozlik',
      'Rezonans rejimi',
      'Charchog\' yorig\'i',
      'Material o\'zgarishi',
    ],
    color: Color(0xFF9E9E9E),
    icon: Icons.help_outline,
    densityKgM3: 2000,
    youngsModulusGPa: 30,
  );

  /// Barcha presetlar
  static const List<MaterialProfile> all = [
    universal,
    steel,
    aluminum,
    concrete,
    brick,
    granite,
    asphalt,
    wood,
    composite,
    plastic,
    glass,
    ceramic,
  ];

  /// id bo'yicha qidirish
  static MaterialProfile byId(String id) {
    return all.firstWhere(
      (m) => m.id == id,
      orElse: () => universal,
    );
  }
}
