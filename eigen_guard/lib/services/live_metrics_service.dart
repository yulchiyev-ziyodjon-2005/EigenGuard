import 'package:flutter/foundation.dart';

/// Trend yo'nalishi — C++ ApproximationProcessor dan keladi.
enum TrendDir { falling, stable, rising }

/// Bitta "live" jonli o'lchov snapshot'i — C++ engine + YOLO dan keladigan
/// joriy holatni boshqa ekranlar (DigitalTwin, History) tinglashi uchun.
class LiveMetrics {
  final String? objectLabel;
  final double riskPercent;
  final double frequencyHz;
  final double amplitudeMm;
  final DateTime updatedAt;
  final bool isMonitoring;
  final int pointCount;

  // ── §6.4 Predictive (RUL) ────────────────────────────────────────────────
  /// Kritik chegaraga qancha vaqt qoldi (soat). <0 — bashorat yo'q yoki barqaror.
  final double hoursToCritical;
  /// Tendentsiya yo'nalishi (oshmoqda / barqaror / kamaymoqda).
  final TrendDir trend;
  /// Parabolik koeffitsiyentlar (y = a + b·t + c·t²) — diagnostika uchun.
  final double trendA;
  final double trendB;
  final double trendC;
  /// Bashorat hisoblanganmi (kamida 3 ta nuqta to'plangan).
  final bool hasPrediction;

  // ── Material profili (Phase 1) ────────────────────────────────────────────
  /// Joriy material id ('steel', 'concrete', 'wood', ...)
  final String materialId;
  /// Foydalanuvchi ko'rinishi uchun nom
  final String materialName;
  /// Kritik amplituda chegarasi (mm) — material profilidan
  final double criticalAmpMm;

  const LiveMetrics({
    this.objectLabel,
    this.riskPercent = 0,
    this.frequencyHz = 0,
    this.amplitudeMm = 0,
    required this.updatedAt,
    this.isMonitoring = false,
    this.pointCount = 0,
    this.hoursToCritical = -1.0,
    this.trend = TrendDir.stable,
    this.trendA = 0,
    this.trendB = 0,
    this.trendC = 0,
    this.hasPrediction = false,
    this.materialId = 'universal',
    this.materialName = 'Universal',
    this.criticalAmpMm = 3.0,
  });

  factory LiveMetrics.empty() => LiveMetrics(
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

  /// TZ §5 dagi Enum: NORMAL / WARNING / HIGH / CRITICAL
  String get riskLevelLabel {
    if (riskPercent >= 85) return 'CRITICAL';
    if (riskPercent >= 60) return 'HIGH';
    if (riskPercent >= 30) return 'WARNING';
    return 'NORMAL';
  }

  bool get hasData => updatedAt.millisecondsSinceEpoch > 0;

  /// HUD da ko'rsatish uchun matn: "12.4 soat", "8 kun", "Barqaror" ...
  String get rulLabel {
    if (!hasPrediction || hoursToCritical < 0) return '—';
    if (trend == TrendDir.falling || trend == TrendDir.stable) return 'Barqaror';
    if (hoursToCritical < 1) {
      final mins = (hoursToCritical * 60).round();
      return '$mins daq';
    }
    if (hoursToCritical < 48) return '${hoursToCritical.toStringAsFixed(1)} soat';
    final days = hoursToCritical / 24.0;
    if (days < 60) return '${days.toStringAsFixed(1)} kun';
    return '${(days / 30.0).toStringAsFixed(1)} oy';
  }

  String get trendArrow {
    switch (trend) {
      case TrendDir.rising:
        return '↑';
      case TrendDir.falling:
        return '↓';
      case TrendDir.stable:
        return '→';
    }
  }
}

/// LiveMetricsService — Singleton pub/sub bridge.
/// Dashboard har kadrda `push(...)` qiladi, DigitalTwin esa `metrics` ga
/// `ValueListenableBuilder` orqali ulanadi (UI thread bloklanmaydi).
class LiveMetricsService {
  static final LiveMetricsService _instance = LiveMetricsService._();
  factory LiveMetricsService() => _instance;
  LiveMetricsService._();

  final ValueNotifier<LiveMetrics> metrics =
      ValueNotifier<LiveMetrics>(LiveMetrics.empty());

  // ───────────────────────────────────────────────────────────────────────
  // PHASE 7 — Jonli signal bufferlari (Monitoring LIVE tabi uchun)
  // ───────────────────────────────────────────────────────────────────────
  /// Oxirgi ~5 sek amplituda (mm) — Dashboard har frame'da push qiladi
  final ValueNotifier<List<double>> liveAmpWindow =
      ValueNotifier<List<double>>(const []);

  /// Oxirgi FFT spektri (Float64) — Dashboard har 500ms da push qiladi
  final ValueNotifier<Float64List> liveSpectrum =
      ValueNotifier<Float64List>(Float64List(0));

  /// FFT sample rate (Hz) — spektrni Hz ga konvertatsiya uchun
  double liveSpectrumSampleRate = 44100.0;

  void pushAmpWindow(List<double> amp) {
    liveAmpWindow.value = amp;
  }

  void pushSpectrum(Float64List spec, double sampleRate) {
    liveSpectrum.value = spec;
    liveSpectrumSampleRate = sampleRate;
  }

  void push({
    required String? label,
    required double risk,
    required double freq,
    required double ampMm,
    required bool monitoring,
    int pointCount = 0,
    double hoursToCritical = -1.0,
    TrendDir trend = TrendDir.stable,
    double trendA = 0,
    double trendB = 0,
    double trendC = 0,
    bool hasPrediction = false,
    String materialId = 'universal',
    String materialName = 'Universal',
    double criticalAmpMm = 3.0,
  }) {
    metrics.value = LiveMetrics(
      objectLabel: label,
      riskPercent: risk,
      frequencyHz: freq,
      amplitudeMm: ampMm,
      updatedAt: DateTime.now(),
      isMonitoring: monitoring,
      pointCount: pointCount,
      hoursToCritical: hoursToCritical,
      trend: trend,
      trendA: trendA,
      trendB: trendB,
      trendC: trendC,
      hasPrediction: hasPrediction,
      materialId: materialId,
      materialName: materialName,
      criticalAmpMm: criticalAmpMm,
    );
  }

  void reset() {
    metrics.value = LiveMetrics.empty();
    liveAmpWindow.value = const [];
    liveSpectrum.value = Float64List(0);
  }
}
