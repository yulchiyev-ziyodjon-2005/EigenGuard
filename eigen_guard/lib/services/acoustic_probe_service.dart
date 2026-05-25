import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import '../ffi/native_engine.dart';
import '../models/material_profile.dart';
import 'chirp_generator.dart';

/// EigenGuard — Active Acoustic Probe.
///
/// **Texnika:**
/// 1. Spikerdan 100 Hz → 5000 Hz logarifmik chirp yuboramiz.
/// 2. Aynan shu vaqtda mikrofon yozib oladi.
/// 3. Yozilgan signal → C++ FFT → rezonans peaklari va damping.
/// 4. Peaklarni har bir [MaterialProfile] ning rezonans diapazoni bilan
///    solishtirib, eng yaxshi mos materialni topamiz.
///
/// **Cheklovlar:**
/// - Telefon spikeri va mikrofoni kalibrlanmagan (frequency response notekis).
/// - Atrof-muhit shovqini xato kiritishi mumkin.
/// - Natija — qiyosiy ("eng o'xshash material"), absolyut emas.
class AcousticProbeService {
  AcousticProbeService(this._engine);

  final NativeEngine _engine;
  final AudioPlayer _player = AudioPlayer();
  final AudioRecorder _recorder = AudioRecorder();
  bool _isProbing = false;

  bool get isProbing => _isProbing;

  // ═════════════════════════════════════════════════════════════════════════
  // ASOSIY PROBE OPERATSIYASI
  // ═════════════════════════════════════════════════════════════════════════

  /// To'liq probe sikli:
  ///   chirp gen → record start → play chirp → record stop → FFT → match
  Future<ProbeResult> probe({
    double startHz = 100.0,
    double endHz = 5000.0,
    int chirpMs = 2000,
    int tailMs = 800,
    int sampleRate = 44100,
  }) async {
    if (_isProbing) {
      throw StateError('Akustik probe allaqachon ishlamoqda');
    }
    _isProbing = true;

    try {
      // 1) Mikrofon huquqi tekshiruvi
      if (!await _recorder.hasPermission()) {
        throw StateError('Mikrofon ruxsati berilmagan');
      }

      // 2) Chirp WAV generatsiyasi (xotirada)
      final chirpWav = ChirpGenerator.generateChirpWav(
        startHz: startHz,
        endHz: endHz,
        durationMs: chirpMs,
        sampleRate: sampleRate,
        chirpType: ChirpType.exponential,
        amplitude: 0.55,
      );

      // 3) Rekorder oqimini boshlash
      final pcmBuffer = BytesBuilder();
      final recStream = await _recorder.startStream(RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
      ));
      final recSub = recStream.listen(pcmBuffer.add);

      // 4) Rekorder "ilingani"ga qisqa kechikish (qurilmaga qarab)
      await Future.delayed(const Duration(milliseconds: 80));

      // 5) Chirp ni o'ynatish (BytesSource)
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.play(BytesSource(chirpWav));

      // 6) Chirp + quyruq (decay tail) tugagunga qadar kutish
      await Future.delayed(Duration(milliseconds: chirpMs + tailMs));

      // 7) Rekorder oqimini to'xtatish
      await recSub.cancel();
      await _recorder.stop();
      try {
        await _player.stop();
      } catch (_) {}

      // 8) PCM (Int16) → Float64 normalize qilingan signal
      final raw = pcmBuffer.toBytes();
      if (raw.length < 2) {
        return ProbeResult.empty('PCM ma\'lumot yo\'q');
      }
      final i16 = Int16List.view(raw.buffer, raw.offsetInBytes, raw.length ~/ 2);
      final signal = Float64List(i16.length);
      for (int i = 0; i < i16.length; i++) {
        signal[i] = i16[i] / 32768.0;
      }

      // 9) FFT spektri (C++ engine)
      final fft = _engine.createFftProcessor();
      Float64List magnitudes;
      try {
        final spec = fft.computeSpectrum(signal, sampleRate.toDouble());
        magnitudes = spec.magnitudes;
      } finally {
        fft.dispose();
      }

      // 10) Rezonans peaklari (top-N lokal maksimum)
      final peaks = _findPeaks(magnitudes, sampleRate.toDouble(), topN: 8);

      // 11) Damping baholash (signal quyrug'idagi exponential decay)
      final damping = _estimateDamping(signal, sampleRate.toDouble(),
          chirpEndMs: chirpMs);

      // 12) Material matching
      final ranked = _rankMaterials(peaks);
      final bestMatch = ranked.isNotEmpty ? ranked.first : null;

      return ProbeResult(
        peaks: peaks,
        dampingRatio: damping,
        bestMatch: bestMatch?.profile ?? MaterialPresets.universal,
        matchConfidence: bestMatch?.confidence ?? 0.0,
        rankedCandidates: ranked,
        spectrum: magnitudes,
        sampleRate: sampleRate.toDouble(),
        chirpStartHz: startHz,
        chirpEndHz: endHz,
        recordedDurationMs:
            (signal.length / sampleRate * 1000).round(),
      );
    } catch (e, st) {
      debugPrint('[AcousticProbe] xato: $e\n$st');
      return ProbeResult.empty('Xatolik: $e');
    } finally {
      _isProbing = false;
    }
  }

  void dispose() {
    try {
      _player.dispose();
    } catch (_) {}
    try {
      _recorder.dispose();
    } catch (_) {}
  }

  // ═════════════════════════════════════════════════════════════════════════
  // PEAK DETECTION
  // ═════════════════════════════════════════════════════════════════════════
  /// FFT spektridan eng yuqori `topN` ta rezonans peak'ni topadi.
  /// Algoritm:
  ///   1. Lokal maksimumlar (chap va o'ng qo'shni bin'lardan baland)
  ///   2. Magnitude bo'yicha tartiblash
  ///   3. Yon-yondagi peaklarni birlashtirish (minimum 10 Hz oraliq)
  static List<ResonancePeak> _findPeaks(
    Float64List spectrum,
    double sampleRate, {
    int topN = 8,
  }) {
    final n = spectrum.length;
    if (n < 4) return const [];

    final binHz = sampleRate / (2.0 * n); // ko'rilayotgan max freq = nyquist
    final List<ResonancePeak> candidates = [];

    // Lokal maks topish (3-bin window)
    for (int i = 2; i < n - 2; i++) {
      final m = spectrum[i];
      if (m > spectrum[i - 1] &&
          m > spectrum[i + 1] &&
          m > spectrum[i - 2] &&
          m > spectrum[i + 2]) {
        candidates.add(ResonancePeak(
          freqHz: i * binHz,
          magnitude: m,
          binIndex: i,
        ));
      }
    }

    // Magnitude bo'yicha tartiblash
    candidates.sort((a, b) => b.magnitude.compareTo(a.magnitude));

    // Yaqin peaklarni birlashtirish (10 Hz dan yaqin bo'lsa balandini saqlab)
    final List<ResonancePeak> filtered = [];
    for (final c in candidates) {
      bool tooClose = false;
      for (final f in filtered) {
        if ((f.freqHz - c.freqHz).abs() < 10.0) {
          tooClose = true;
          break;
        }
      }
      if (!tooClose) filtered.add(c);
      if (filtered.length >= topN) break;
    }
    return filtered;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // DAMPING ESTIMATE
  // ═════════════════════════════════════════════════════════════════════════
  /// Quyruq (tail) qismi RMS energiyasining exponential decay sur'atidan
  /// damping ratio'sini taxminlaydi. Yuqori damping → tez susayadi (yog'och,
  /// plastik). Past damping → uzoq tebranadi (shisha, metall).
  static double _estimateDamping(
    Float64List signal,
    double sampleRate, {
    required int chirpEndMs,
  }) {
    final chirpEndIdx = (chirpEndMs / 1000.0 * sampleRate).round();
    if (chirpEndIdx >= signal.length - 100) return 0.05;

    // Tail qismi 5 ta segmentga bo'lib RMS hisoblash
    const segments = 5;
    final tailLen = signal.length - chirpEndIdx;
    final segLen = tailLen ~/ segments;
    if (segLen < 50) return 0.05;

    final rms = List<double>.filled(segments, 0.0);
    for (int s = 0; s < segments; s++) {
      double sum = 0;
      final start = chirpEndIdx + s * segLen;
      for (int i = 0; i < segLen; i++) {
        final v = signal[start + i];
        sum += v * v;
      }
      rms[s] = math.sqrt(sum / segLen);
    }

    // Eng katta va eng kichik RMS nisbati → decay
    if (rms.first <= 1e-9) return 0.05;
    final ratio = rms.last / rms.first;
    if (ratio >= 1.0) return 0.001; // umuman susaymadi (shisha kabi)
    if (ratio <= 1e-4) return 0.5; // o'ta tez (yog'och, foam)

    // Logarifmik decay → damping ratio'ga taxminiy konversiya
    // Bu universal proxy — kalibratsiyasiz absolyut emas, lekin tartibi to'g'ri
    final decay = -math.log(ratio) / (tailLen / sampleRate);
    return (decay / 100.0).clamp(0.001, 0.5);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // MATERIAL MATCHING
  // ═════════════════════════════════════════════════════════════════════════
  /// Topilgan peaklar va damping ratio asosida har bir MaterialProfile uchun
  /// "o'xshashlik" balli hisoblab, kamayish tartibida qaytaradi.
  ///
  /// Ball formulasi:
  ///   resonanceScore = peaklarning material diapazoniga tushish ulushi
  ///                    (magnitude bilan o'lchanadi)
  ///   dangerScore    = eng kuchli peak material.dangerFrequencyHz ga qancha
  ///                    yaqin (±20% diapazonda 1.0, undan tashqari 0)
  ///   dampingScore   = topilgan damping va material.dampingRatio yaqinligi
  ///
  ///   total = 0.55·resonance + 0.25·danger + 0.20·damping
  ///
  /// Confidence — eng yaxshi bilan ikkinchining farqi (0..1).
  static List<MaterialRank> _rankMaterials(List<ResonancePeak> peaks) {
    if (peaks.isEmpty) return const [];

    final totalEnergy = peaks.fold<double>(0, (s, p) => s + p.magnitude);
    if (totalEnergy <= 0) return const [];

    final List<MaterialRank> ranks = [];

    for (final mat in MaterialPresets.all) {
      if (mat.id == 'universal') continue; // Universal — fallback, ranking emas

      // 1) Rezonans ulushi
      double inRangeEnergy = 0;
      for (final p in peaks) {
        if (p.freqHz >= mat.resonanceMinHz && p.freqHz <= mat.resonanceMaxHz) {
          inRangeEnergy += p.magnitude;
        }
      }
      final resonanceScore = inRangeEnergy / totalEnergy;

      // 2) Danger freq yaqinligi
      double dangerScore = 0;
      if (mat.dangerFrequencyHz > 0) {
        final tol = mat.dangerFrequencyHz * 0.3;
        for (final p in peaks) {
          final d = (p.freqHz - mat.dangerFrequencyHz).abs();
          if (d < tol) {
            final w = 1.0 - d / tol;
            dangerScore = math.max(dangerScore, w);
          }
        }
      }

      // 3) Hozircha damping ni rank ga ko'shmaymiz — sof rezonans + danger.
      //    (Damping baholash kalibratsiyasiz noaniq, false-negative beradi.)
      final total = 0.7 * resonanceScore + 0.3 * dangerScore;
      ranks.add(MaterialRank(profile: mat, score: total));
    }

    ranks.sort((a, b) => b.score.compareTo(a.score));

    // Confidence: birinchi va ikkinchi orasidagi farq
    if (ranks.length >= 2) {
      final gap = ranks[0].score - ranks[1].score;
      ranks[0] = ranks[0].copyWith(confidence: gap.clamp(0.0, 1.0));
    } else if (ranks.length == 1) {
      ranks[0] = ranks[0].copyWith(confidence: ranks[0].score.clamp(0.0, 1.0));
    }

    return ranks;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MA'LUMOT MODELLARI
// ═══════════════════════════════════════════════════════════════════════════

class ResonancePeak {
  final double freqHz;
  final double magnitude;
  final int binIndex;

  const ResonancePeak({
    required this.freqHz,
    required this.magnitude,
    required this.binIndex,
  });

  @override
  String toString() =>
      '${freqHz.toStringAsFixed(1)} Hz @ ${magnitude.toStringAsFixed(3)}';
}

class MaterialRank {
  final MaterialProfile profile;
  final double score;
  final double confidence;

  const MaterialRank({
    required this.profile,
    required this.score,
    this.confidence = 0.0,
  });

  MaterialRank copyWith({double? confidence}) => MaterialRank(
        profile: profile,
        score: score,
        confidence: confidence ?? this.confidence,
      );
}

class ProbeResult {
  final List<ResonancePeak> peaks;
  final double dampingRatio;
  final MaterialProfile bestMatch;
  final double matchConfidence; // 0..1
  final List<MaterialRank> rankedCandidates;
  final Float64List spectrum;
  final double sampleRate;
  final double chirpStartHz;
  final double chirpEndHz;
  final int recordedDurationMs;
  final String? error;

  const ProbeResult({
    required this.peaks,
    required this.dampingRatio,
    required this.bestMatch,
    required this.matchConfidence,
    required this.rankedCandidates,
    required this.spectrum,
    required this.sampleRate,
    required this.chirpStartHz,
    required this.chirpEndHz,
    required this.recordedDurationMs,
    this.error,
  });

  factory ProbeResult.empty(String err) => ProbeResult(
        peaks: const [],
        dampingRatio: 0,
        bestMatch: MaterialPresets.universal,
        matchConfidence: 0,
        rankedCandidates: const [],
        spectrum: Float64List(0),
        sampleRate: 44100,
        chirpStartHz: 0,
        chirpEndHz: 0,
        recordedDurationMs: 0,
        error: err,
      );

  bool get isValid => error == null && peaks.isNotEmpty;
}
