import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vibration/vibration.dart';

import '../models/material_profile.dart';

/// EigenGuard — Vibration Motor Probing.
///
/// **Texnika:**
/// 1. Telefon foydalanuvchi tomonidan obyekt (devor, taxta, val) ga qattiq tiraladi.
/// 2. Telefon o'z vibratsiya motorini qisqa impuls bilan ishga tushiradi.
/// 3. Impuls energiyasi qisman obyektga uzatiladi va aks etadi.
/// 4. Telefondagi accelerometer reaksiyani yozib oladi.
/// 5. Reaksiyaning **decay (susayish) vaqti** va **peak amplituda** material
///    qattiqligi va damping ratio'sini ko'rsatadi.
///
/// **Material signaturasi:**
/// - Po'lat / shisha (past damping)    → uzoq ringing, peak juda baland
/// - Yog'och / plastik (yuqori damping) → tez susayadi, peak past
/// - Beton (o'rta-past damping)         → o'rtacha ringing
///
/// **Cheklov:** telefon motori va sensori kalibrlanmagan; qo'lda tutish bosimi
/// variatsiyasi natijani buzadi. Natija — qiyosiy (relativ).
class VibrationProbeService {
  bool _isProbing = false;
  bool get isProbing => _isProbing;

  /// Vibrator mavjudligini tekshirish (telefon vibrator'siz bo'lishi mumkin)
  static Future<bool> hasVibrator() async {
    try {
      return await Vibration.hasVibrator();
    } catch (_) {
      return false;
    }
  }

  /// To'liq probe operatsiyasi:
  ///   1) baselineMs davomida IMU shovqinini o'lchash
  ///   2) impulseMs davomida vibratsiya
  ///   3) responseMs davomida IMU reaksiyasini yozish
  ///   4) tahlil + material match
  Future<VibrationProbeResult> probe({
    int baselineMs = 400,
    int impulseMs = 120,
    int responseMs = 600,
  }) async {
    if (_isProbing) {
      throw StateError('Vibratsiya probe allaqachon ishlamoqda');
    }
    _isProbing = true;

    try {
      final hasVib = await hasVibrator();
      if (!hasVib) {
        return VibrationProbeResult.empty('Vibratsiya motori mavjud emas');
      }

      // 1) IMU oqimini ochish va barcha samplelarni yig'ish
      final List<_AccelSample> samples = [];
      final start = DateTime.now();
      late StreamSubscription<UserAccelerometerEvent> sub;
      sub = userAccelerometerEventStream().listen((e) {
        final tMs =
            DateTime.now().difference(start).inMicroseconds / 1000.0;
        samples.add(_AccelSample(tMs: tMs, x: e.x, y: e.y, z: e.z));
      });

      // 2) Baseline (sokin holat) — shovqin darajasini topish uchun
      await Future.delayed(Duration(milliseconds: baselineMs));
      final baselineEndIdx = samples.length;

      // 3) Vibratsiya impulsi
      final impulseStartMs =
          DateTime.now().difference(start).inMicroseconds / 1000.0;
      try {
        await Vibration.vibrate(duration: impulseMs, amplitude: 255);
      } catch (e) {
        debugPrint('[VibrationProbe] vibrate xato: $e');
      }

      // 4) Reaksiyani yozish (impuls + post-impulse decay)
      await Future.delayed(Duration(milliseconds: impulseMs + responseMs));

      await sub.cancel();

      if (samples.length < 20) {
        return VibrationProbeResult.empty(
            'IMU samples yetarli emas (telefon sensori sekin?)');
      }

      // 5) Tahlil
      return _analyze(
        samples: samples,
        baselineEndIdx: baselineEndIdx,
        impulseStartMs: impulseStartMs,
        impulseMs: impulseMs,
      );
    } catch (e, st) {
      debugPrint('[VibrationProbe] xato: $e\n$st');
      return VibrationProbeResult.empty('Xatolik: $e');
    } finally {
      _isProbing = false;
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // TAHLIL
  // ═════════════════════════════════════════════════════════════════════════
  VibrationProbeResult _analyze({
    required List<_AccelSample> samples,
    required int baselineEndIdx,
    required double impulseStartMs,
    required int impulseMs,
  }) {
    // 1) Baseline RMS (shovqin)
    double bRms = 0;
    if (baselineEndIdx > 0) {
      for (int i = 0; i < baselineEndIdx; i++) {
        final s = samples[i];
        bRms += s.x * s.x + s.y * s.y + s.z * s.z;
      }
      bRms = math.sqrt(bRms / baselineEndIdx);
    }

    // 2) Time-series magnitude
    final tList = <double>[];
    final mList = <double>[];
    final xList = <double>[];
    final yList = <double>[];
    final zList = <double>[];
    double peak = 0;
    double peakTimeMs = 0;
    for (final s in samples) {
      final m = math.sqrt(s.x * s.x + s.y * s.y + s.z * s.z);
      tList.add(s.tMs);
      mList.add(m);
      xList.add(s.x);
      yList.add(s.y);
      zList.add(s.z);
      if (m > peak) {
        peak = m;
        peakTimeMs = s.tMs;
      }
    }

    // 3) Decay vaqti — peak'dan keyin signal peak/e ga (≈37%) tushish vaqti
    final decayThreshold = peak / math.e;
    double decayTimeMs = 0;
    for (int i = 0; i < mList.length; i++) {
      if (tList[i] > peakTimeMs && mList[i] <= decayThreshold) {
        decayTimeMs = tList[i] - peakTimeMs;
        break;
      }
    }
    // Agar topilmasa — uzoq ringing
    if (decayTimeMs == 0 && tList.isNotEmpty) {
      decayTimeMs = tList.last - peakTimeMs;
    }

    // 4) Damping ratio (taxminiy) — qisqa decay → yuqori damping
    //    Logarifmik decay konvensiyasi: ζ ≈ ln(peak/threshold) / (2π · n_cycles)
    //    Bu yerda biz period'ni bilmaganimiz uchun proxy ishlatamiz:
    double dampingRatio;
    if (decayTimeMs <= 0) {
      dampingRatio = 0.5;
    } else {
      // 50ms = juda yuqori damping (≥0.4), 500ms = juda past (≤0.005)
      dampingRatio =
          (0.5 - (decayTimeMs / 500.0) * 0.49).clamp(0.001, 0.5);
    }

    // 5) Peak SNR (qancha baland baseline shovqinidan)
    final snr = bRms > 1e-6 ? peak / bRms : peak * 1000;

    // 6) Material match
    final rawRanks = _rankMaterials(
      peakAccel: peak,
      dampingRatio: dampingRatio,
      snr: snr,
    );
    final ranks = rawRanks.toSimpleList();
    final best = rawRanks.isNotEmpty ? rawRanks.first : null;

    return VibrationProbeResult(
      timeSeriesMs: tList,
      magnitude: mList,
      accelX: xList,
      accelY: yList,
      accelZ: zList,
      baselineRms: bRms,
      peakAccel: peak,
      peakTimeMs: peakTimeMs,
      decayTimeMs: decayTimeMs,
      dampingRatio: dampingRatio,
      snr: snr,
      bestMatch: best?.profile ?? MaterialPresets.universal,
      matchConfidence: best?.confidence ?? 0.0,
      rankedCandidates: ranks,
      impulseStartMs: impulseStartMs,
      impulseMs: impulseMs,
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // MATERIAL MATCHING — damping ratio asosida
  // ═════════════════════════════════════════════════════════════════════════
  static List<_VibRank> _rankMaterials({
    required double peakAccel,
    required double dampingRatio,
    required double snr,
  }) {
    final List<_VibRank> ranks = [];

    // Agar SNR juda past bo'lsa — natija ishonchsiz, lekin baribir hisoblaymiz
    final snrWeight = (snr / 5.0).clamp(0.1, 1.0); // 5x SNR ≈ ishonchli

    for (final mat in MaterialPresets.all) {
      if (mat.id == 'universal') continue;

      // Damping yaqinligi (logarifmik masofa, chunki diapazon 0.001..0.5)
      final logDelta =
          (math.log(dampingRatio) - math.log(mat.dampingRatio)).abs();
      // logDelta 0..7 oraliqda — 0 = mos, 7 = juda uzoq
      final dampingScore = (1.0 - logDelta / 6.0).clamp(0.0, 1.0);

      ranks.add(_VibRank(profile: mat, score: dampingScore * snrWeight));
    }

    ranks.sort((a, b) => b.score.compareTo(a.score));

    if (ranks.length >= 2) {
      final gap = ranks[0].score - ranks[1].score;
      ranks[0] = ranks[0].copyWith(confidence: gap.clamp(0.0, 1.0));
    } else if (ranks.length == 1) {
      ranks[0] = ranks[0].copyWith(
          confidence: ranks[0].score.clamp(0.0, 1.0));
    }

    return ranks;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MA'LUMOT MODELLARI
// ═══════════════════════════════════════════════════════════════════════════

class _AccelSample {
  final double tMs;
  final double x;
  final double y;
  final double z;
  const _AccelSample({
    required this.tMs,
    required this.x,
    required this.y,
    required this.z,
  });
}

class _VibRank {
  final MaterialProfile profile;
  final double score;
  final double confidence;
  const _VibRank({
    required this.profile,
    required this.score,
    this.confidence = 0.0,
  });
  _VibRank copyWith({double? confidence}) => _VibRank(
        profile: profile,
        score: score,
        confidence: confidence ?? this.confidence,
      );
}

/// VibrationProbeService natijasi — UI ga uzatiladi
class VibrationProbeResult {
  /// Time series (ms dan boshlanib)
  final List<double> timeSeriesMs;
  final List<double> magnitude;
  final List<double> accelX;
  final List<double> accelY;
  final List<double> accelZ;

  /// Baseline (sokin holat) RMS shovqini
  final double baselineRms;

  /// Eng baland accelerometer magnitudasi (m/s²)
  final double peakAccel;

  /// Peak qaysi vaqtda bo'lgan (ms)
  final double peakTimeMs;

  /// Peak'dan peak/e (≈37%) ga tushish vaqti — exponential decay konstantasi
  final double decayTimeMs;

  /// Taxminiy damping ratio (0.001 — 0.5)
  final double dampingRatio;

  /// Signal/Noise Ratio (peak / baseline RMS)
  final double snr;

  /// Eng yaxshi mos material
  final MaterialProfile bestMatch;
  final double matchConfidence;
  final List<MaterialRankSimple> rankedCandidates;

  /// Vibratsiya impulsi boshlangan vaqt (ms — time series boshidan)
  final double impulseStartMs;
  final int impulseMs;

  /// Xato matni — agar muvaffaqiyatsiz bo'lsa
  final String? error;

  const VibrationProbeResult({
    required this.timeSeriesMs,
    required this.magnitude,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.baselineRms,
    required this.peakAccel,
    required this.peakTimeMs,
    required this.decayTimeMs,
    required this.dampingRatio,
    required this.snr,
    required this.bestMatch,
    required this.matchConfidence,
    required this.rankedCandidates,
    required this.impulseStartMs,
    required this.impulseMs,
    this.error,
  });

  factory VibrationProbeResult.empty(String err) => VibrationProbeResult(
        timeSeriesMs: const [],
        magnitude: const [],
        accelX: const [],
        accelY: const [],
        accelZ: const [],
        baselineRms: 0,
        peakAccel: 0,
        peakTimeMs: 0,
        decayTimeMs: 0,
        dampingRatio: 0,
        snr: 0,
        bestMatch: MaterialPresets.universal,
        matchConfidence: 0,
        rankedCandidates: const [],
        impulseStartMs: 0,
        impulseMs: 0,
        error: err,
      );

  bool get isValid => error == null && magnitude.isNotEmpty;
}

/// AcousticProbeService dagi MaterialRank ga o'xshash, lekin alohida turi
/// (turli probe'larni alohida ko'rsatish uchun)
class MaterialRankSimple {
  final MaterialProfile profile;
  final double score;
  final double confidence;
  const MaterialRankSimple({
    required this.profile,
    required this.score,
    this.confidence = 0.0,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// _VibRank → MaterialRankSimple konversiya (qaytarish uchun)
// ═══════════════════════════════════════════════════════════════════════════
extension on List<_VibRank> {
  List<MaterialRankSimple> toSimpleList() => map((r) => MaterialRankSimple(
        profile: r.profile,
        score: r.score,
        confidence: r.confidence,
      )).toList();
}
