import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/edge_sensor_reading.dart';
import 'mqtt_ingest_service.dart';

/// Sprint 15 — True Sensor Fusion Arbiter.
///
/// **Qaror qoidalari (B2G ekotizimi):**
/// - Kamera tebranish ko'rmoqda + Edge sensor sokin → **False Positive**
/// - Kamera + Edge ikkalasi rezonans → **Critical Alert** (consensusCritical)
/// - Faqat Edge → **hardwareOnly** (vizual tasdiqlash kerak)
/// - Faqat kamera (MQTT ulanmagan) → **cameraOnly** (fallback)
/// - Hech narsa → **idle**
///
/// **Korrelyatsiya oynasi:** ±200ms (`Sprint 15` spetsifikatsiyasi).
/// Kamera hodisasi push qilingach, arbiter Edge buferida shu vaqtga
/// yaqin (∆t ≤ 200ms) reading qidiradi va ikkala asbobning amplituda/chastota
/// chegaralaridan o'tganini tekshiradi.
///
/// **Threading:** To'liq ValueNotifier — UI main thread bloklanmaydi.
/// Hisoblashlar yengil (ring buffer scan), Isolate kerak emas.
enum FusionVerdict {
  /// Hech qanday hodisa.
  idle,

  /// Faqat kamera triggeri (MQTT ulanmagan yoki Edge yo'q) — single-source.
  cameraOnly,

  /// Faqat Edge triggeri (vizualda ko'rinmaydi) — single-source.
  hardwareOnly,

  /// Kamera triggeri Edge tomonidan inkor etildi (oynada Edge sokin).
  falsePositive,

  /// Kamera + Edge konsensus — KRITIK ALERT.
  consensusCritical,
}

extension FusionVerdictX on FusionVerdict {
  /// HUD ranglari uchun belgi.
  bool get isCritical => this == FusionVerdict.consensusCritical;
  bool get isSuppressed => this == FusionVerdict.falsePositive;
  bool get isSingleSource =>
      this == FusionVerdict.cameraOnly || this == FusionVerdict.hardwareOnly;

  String get label {
    switch (this) {
      case FusionVerdict.idle:
        return 'IDLE';
      case FusionVerdict.cameraOnly:
        return 'CAM ONLY';
      case FusionVerdict.hardwareOnly:
        return 'HW ONLY';
      case FusionVerdict.falsePositive:
        return 'FALSE POS';
      case FusionVerdict.consensusCritical:
        return 'FUSED CRIT';
    }
  }
}

/// Bitta kamera hodisasi (snapshot).
class _CameraEvent {
  final DateTime t;
  final double ampMm;
  final double freqHz;
  final double riskPercent;
  const _CameraEvent(this.t, this.ampMm, this.freqHz, this.riskPercent);
}

class FusionState {
  final FusionVerdict verdict;
  /// 0.0..1.0 — ikkala manbaning kelishuv darajasi.
  /// consensusCritical: amplituda/chastota yaqinligi + Edge SNR
  /// cameraOnly: kamera risk%; hardwareOnly: edge vib mm
  final double confidence;
  /// Konsensus paytida ishtirok etgan Edge reading (mavjud bo'lsa).
  final EdgeSensorReading? matchedEdgeReading;
  /// Konsensus paytida ishtirok etgan kamera amplitudasi.
  final double? cameraAmpMm;
  final double? cameraFreqHz;
  /// Verdikt qachon emitted bo'lgani.
  final DateTime updatedAt;

  const FusionState({
    required this.verdict,
    required this.confidence,
    required this.updatedAt,
    this.matchedEdgeReading,
    this.cameraAmpMm,
    this.cameraFreqHz,
  });

  factory FusionState.idle() => FusionState(
        verdict: FusionVerdict.idle,
        confidence: 0,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class SensorFusionArbiter {
  static final SensorFusionArbiter _instance = SensorFusionArbiter._();
  factory SensorFusionArbiter() => _instance;
  SensorFusionArbiter._();

  // ── Konfiguratsiya (sprint qoidalari) ───────────────────────────────
  /// Korrelyatsiya oynasi (±). Sprint 15 spetsifikatsiyasi.
  Duration correlationWindow = const Duration(milliseconds: 200);

  /// Kamera tebranish hodisasi sifatida hisoblanishi uchun min amplituda (mm).
  double cameraAmpThresholdMm = 0.5;

  /// Edge sensor "trigger" sifatida hisoblanishi uchun min amplituda (mm).
  double edgeAmpThresholdMm = 1.0;

  /// Rezonans deb hisoblash uchun min chastota (Hz) — ikkala manba uchun.
  double resonanceMinHz = 5.0;

  /// Verdiktni qancha vaqt aktiv saqlash (timeout). So'ng `idle` ga qaytadi.
  Duration verdictHoldDuration = const Duration(milliseconds: 800);

  /// Edge buferida saqlash uchun maksimal yosh.
  Duration edgeBufferMaxAge = const Duration(seconds: 2);

  /// **Sprint 16 — Demo Mode.** ON bo'lsa fusion qoidasini chetlab o'tadi:
  /// kamera triggeri bo'lganda darhol `consensusCritical` verdikt chiqaradi
  /// (Edge sensor talab qilinmaydi). Sotuv demosi va field engineer
  /// standalone rejimi uchun. SettingsService dan boshqariladi.
  bool demoMode = false;

  // ── Public observables ──────────────────────────────────────────────
  final ValueNotifier<FusionState> verdict =
      ValueNotifier<FusionState>(FusionState.idle());

  /// Hisobchilar — diagnostika va dashboard "fusion metrics" uchun.
  int totalCameraEvents = 0;
  int totalEdgeReadings = 0;
  int totalConsensusCritical = 0;
  int totalFalsePositives = 0;
  int totalCameraOnly = 0;
  int totalHardwareOnly = 0;

  // ── Internal buferlar ───────────────────────────────────────────────
  final List<_CameraEvent> _cameraBuffer = [];
  final List<EdgeSensorReading> _edgeBuffer = [];
  static const int _maxBufferSize = 50;

  StreamSubscription<EdgeSensorReading>? _mqttSub;
  Timer? _verdictDecayTimer;

  // ────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ────────────────────────────────────────────────────────────────────

  /// MqttIngestService bilan bog'lanish — Edge reading'lar avtomatik
  /// arbiter buferiga tushadi.
  void bindToMqtt(MqttIngestService mqtt) {
    _mqttSub?.cancel();
    _mqttSub = mqtt.readings.listen(pushEdgeReading);
  }

  /// Kamera optical-flow pipeline har frame'da chaqiradi.
  /// `_processCameraFrame` ichidan ulanishi kerak.
  void pushCameraEvent({
    required double amplitudeMm,
    required double frequencyHz,
    required double riskPercent,
    DateTime? timestamp,
  }) {
    final t = timestamp ?? DateTime.now();
    final event = _CameraEvent(t, amplitudeMm, frequencyHz, riskPercent);
    _cameraBuffer.add(event);
    while (_cameraBuffer.length > _maxBufferSize) {
      _cameraBuffer.removeAt(0);
    }
    totalCameraEvents++;
    _evaluate(triggerEvent: event);
  }

  /// MqttIngestService dan kelgan reading (yoki BLE bridge'dan).
  void pushEdgeReading(EdgeSensorReading reading) {
    _edgeBuffer.add(reading);
    _pruneEdgeBuffer();
    totalEdgeReadings++;
    // Edge yangi keldi — eski kamera hodisasi bilan ham re-evaluate qil
    _evaluate();
  }

  /// Buferlarni va verdiktni tozalash.
  void reset() {
    _cameraBuffer.clear();
    _edgeBuffer.clear();
    verdict.value = FusionState.idle();
  }

  void dispose() {
    _mqttSub?.cancel();
    _verdictDecayTimer?.cancel();
    verdict.dispose();
  }

  // ────────────────────────────────────────────────────────────────────
  // FUSION LOGIC
  // ────────────────────────────────────────────────────────────────────

  void _pruneEdgeBuffer() {
    final cutoff = DateTime.now().subtract(edgeBufferMaxAge);
    _edgeBuffer.removeWhere((e) => e.receivedAt.isBefore(cutoff));
    while (_edgeBuffer.length > _maxBufferSize) {
      _edgeBuffer.removeAt(0);
    }
  }

  /// Asosiy qaror algoritmi.
  void _evaluate({_CameraEvent? triggerEvent}) {
    final cam = triggerEvent ??
        (_cameraBuffer.isEmpty ? null : _cameraBuffer.last);
    if (cam == null) {
      _emitVerdict(FusionState.idle());
      return;
    }

    final cameraTriggered = cam.ampMm >= cameraAmpThresholdMm &&
        cam.freqHz >= resonanceMinHz;

    // Edge bog'lanishi mavjudmi? — MqttIngestService stream ishlamoqda bo'lsa
    // _edgeBuffer to'lib turadi. Bo'sh bo'lsa — fusion yo'q.
    final mqttHasData =
        _edgeBuffer.isNotEmpty &&
        _edgeBuffer.last.receivedAt
                .isAfter(DateTime.now().subtract(const Duration(seconds: 3)));

    // Camera hodisasi vaqti atrofida Edge reading qidiramiz (±200ms)
    EdgeSensorReading? matched;
    double bestDelta = double.infinity;
    for (final e in _edgeBuffer) {
      final delta = e.receivedAt.difference(cam.t).inMilliseconds.abs();
      if (delta <= correlationWindow.inMilliseconds && delta < bestDelta) {
        bestDelta = delta.toDouble();
        matched = e;
      }
    }

    final edgeTriggered = matched != null &&
        matched.isVibrationEvent(
          ampThresholdMm: edgeAmpThresholdMm,
          freqMinHz: resonanceMinHz,
        );

    FusionVerdict v;
    double confidence;
    // Sprint 16 — Demo Mode: hardware tekshiruvini chetlab o'tish.
    // Kamera triggeri bo'lsa darhol consensusCritical → red alert.
    if (demoMode && cameraTriggered) {
      v = FusionVerdict.consensusCritical;
      confidence = (cam.riskPercent / 100.0).clamp(0.0, 1.0);
      totalConsensusCritical++;
    } else if (cameraTriggered && edgeTriggered) {
      v = FusionVerdict.consensusCritical;
      confidence = _consensusConfidence(cam, matched);
      totalConsensusCritical++;
    } else if (cameraTriggered && mqttHasData && !edgeTriggered) {
      // Kamera ko'rdi, Edge oynada sokin → False Positive
      v = FusionVerdict.falsePositive;
      confidence = 0.7; // Edge mavjud bo'lib, hech narsa demoqda — ishonchli
      totalFalsePositives++;
    } else if (cameraTriggered && !mqttHasData) {
      // MQTT yo'q — faqat kamera asosida ishlash (fallback)
      v = FusionVerdict.cameraOnly;
      confidence = (cam.riskPercent / 100.0).clamp(0.0, 1.0);
      totalCameraOnly++;
    } else if (!cameraTriggered && edgeTriggered) {
      v = FusionVerdict.hardwareOnly;
      final amp = matched.vibrationAmplitudeMm ?? 0;
      confidence = (amp / 3.0).clamp(0.0, 1.0);
      totalHardwareOnly++;
    } else {
      v = FusionVerdict.idle;
      confidence = 0;
    }

    _emitVerdict(FusionState(
      verdict: v,
      confidence: confidence,
      updatedAt: DateTime.now(),
      matchedEdgeReading: matched,
      cameraAmpMm: cam.ampMm,
      cameraFreqHz: cam.freqHz,
    ));
  }

  /// Konsensus paytida ikkala manbaning kelishuv darajasi.
  double _consensusConfidence(_CameraEvent cam, EdgeSensorReading edge) {
    final edgeAmp = edge.vibrationAmplitudeMm ?? 0;
    final edgeFreq = edge.dominantFrequencyHz ?? 0;

    // Amplituda yaqinligi (mm) — log scale
    final ampRatio = (cam.ampMm > 0 && edgeAmp > 0)
        ? (cam.ampMm < edgeAmp ? cam.ampMm / edgeAmp : edgeAmp / cam.ampMm)
        : 0.0;

    // Chastota yaqinligi (5%-20% tolerans)
    final freqRatio = (cam.freqHz > 0 && edgeFreq > 0)
        ? (cam.freqHz < edgeFreq
            ? cam.freqHz / edgeFreq
            : edgeFreq / cam.freqHz)
        : 0.5;

    final snr = edge.signalQuality.clamp(0.0, 1.0);
    // Weighted: amplituda 40%, chastota 40%, SNR 20%
    final c = 0.4 * ampRatio + 0.4 * freqRatio + 0.2 * snr;
    return c.clamp(0.0, 1.0);
  }

  void _emitVerdict(FusionState s) {
    verdict.value = s;
    _verdictDecayTimer?.cancel();
    if (s.verdict != FusionVerdict.idle) {
      _verdictDecayTimer = Timer(verdictHoldDuration, () {
        if (verdict.value.verdict == s.verdict &&
            verdict.value.updatedAt == s.updatedAt) {
          verdict.value = FusionState.idle();
        }
      });
    }
  }
}
