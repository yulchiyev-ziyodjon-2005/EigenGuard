import 'dart:math' as math;
import 'dart:typed_data';

/// EigenGuard — Active Acoustic Probe uchun chirp/sweep generator.
///
/// Spikerdan yuboriladigan signal: chiziqli yoki eksponensial chastota sweep.
/// Mikrofonda qabul qilingan javob = obyekt akustik transfer funksiyasi.
/// Bu javobning rezonans peaklari va damping ratio'si materialni aniqlaydi.
class ChirpGenerator {
  ChirpGenerator._();

  /// In-memory WAV bayt qatorini yaratadi. Faylga yozish kerak emas —
  /// `audioplayers` paketi `BytesSource` orqali bevosita o'qiy oladi.
  ///
  /// [startHz]–[endHz] — sweep diapazoni (default 100 → 5000 Hz)
  /// [durationMs] — chirp davomiyligi (default 2000 ms)
  /// [sampleRate] — odatda 44100 Hz
  /// [chirpType] — `linear` (chiziqli) yoki `exponential` (logarifmik)
  /// [amplitude] — 0..1 oralig'ida normallashtirilgan kuch (0.5 — speaker ni
  /// haddan tashqari qiynamaslik uchun)
  /// [fadeMs] — boshlangich/oxiri yumshoq o'tish (speaker "click" ni oldini olish)
  static Uint8List generateChirpWav({
    double startHz = 100.0,
    double endHz = 5000.0,
    int durationMs = 2000,
    int sampleRate = 44100,
    ChirpType chirpType = ChirpType.linear,
    double amplitude = 0.5,
    int fadeMs = 30,
  }) {
    final samples = _generateChirpPcm(
      startHz: startHz,
      endHz: endHz,
      durationMs: durationMs,
      sampleRate: sampleRate,
      chirpType: chirpType,
      amplitude: amplitude,
      fadeMs: fadeMs,
    );
    return _pcmToWav(samples, sampleRate: sampleRate);
  }

  /// Faqat raw PCM (Int16) — testlar va FFT input uchun
  static Int16List generatePcm({
    double startHz = 100.0,
    double endHz = 5000.0,
    int durationMs = 2000,
    int sampleRate = 44100,
    ChirpType chirpType = ChirpType.linear,
    double amplitude = 0.5,
    int fadeMs = 30,
  }) {
    return _generateChirpPcm(
      startHz: startHz,
      endHz: endHz,
      durationMs: durationMs,
      sampleRate: sampleRate,
      chirpType: chirpType,
      amplitude: amplitude,
      fadeMs: fadeMs,
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // PCM (Int16) Chirp generation
  // ═════════════════════════════════════════════════════════════════════════
  static Int16List _generateChirpPcm({
    required double startHz,
    required double endHz,
    required int durationMs,
    required int sampleRate,
    required ChirpType chirpType,
    required double amplitude,
    required int fadeMs,
  }) {
    final n = (sampleRate * durationMs / 1000).round();
    final pcm = Int16List(n);
    final dt = 1.0 / sampleRate;
    final tEnd = durationMs / 1000.0;
    final fadeSamples = (sampleRate * fadeMs / 1000).round();

    // Faza integratsiyasi — phase(t) = 2π·∫f(τ)dτ
    // Linear:        f(t) = f0 + (f1 - f0)·(t/T)
    //                phase(t) = 2π·(f0·t + 0.5·(f1-f0)·t²/T)
    // Exponential:   f(t) = f0·(f1/f0)^(t/T)
    //                phase(t) = 2π·f0·T/ln(f1/f0)·((f1/f0)^(t/T) - 1)
    final f0 = startHz;
    final f1 = endHz;

    for (int i = 0; i < n; i++) {
      final t = i * dt;
      double phase;
      if (chirpType == ChirpType.linear) {
        phase = 2.0 * math.pi * (f0 * t + 0.5 * (f1 - f0) * t * t / tEnd);
      } else {
        final ratio = f1 / f0;
        phase = 2.0 *
            math.pi *
            f0 *
            tEnd /
            math.log(ratio) *
            (math.pow(ratio, t / tEnd) - 1);
      }

      double envelope = 1.0;
      if (i < fadeSamples) {
        envelope = i / fadeSamples;
      } else if (i > n - fadeSamples) {
        envelope = (n - i) / fadeSamples;
      }

      final sample = math.sin(phase) * amplitude * envelope;
      // Int16 ga konversiya: −32768..32767
      pcm[i] = (sample * 32767).round().clamp(-32768, 32767);
    }
    return pcm;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // PCM → WAV bayt qator (16-bit mono RIFF konteyner)
  // ═════════════════════════════════════════════════════════════════════════
  static Uint8List _pcmToWav(Int16List pcm, {required int sampleRate}) {
    const int numChannels = 1;
    const int bitsPerSample = 16;
    final int byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    const int blockAlign = numChannels * bitsPerSample ~/ 8;
    final int dataSize = pcm.lengthInBytes;
    final int fileSize = 36 + dataSize;

    final wav = BytesBuilder();

    // RIFF header
    wav.add(_ascii('RIFF'));
    wav.add(_uint32Le(fileSize));
    wav.add(_ascii('WAVE'));

    // fmt sub-chunk
    wav.add(_ascii('fmt '));
    wav.add(_uint32Le(16)); // PCM uchun fmt chunk hajmi
    wav.add(_uint16Le(1)); // AudioFormat = 1 (PCM)
    wav.add(_uint16Le(numChannels));
    wav.add(_uint32Le(sampleRate));
    wav.add(_uint32Le(byteRate));
    wav.add(_uint16Le(blockAlign));
    wav.add(_uint16Le(bitsPerSample));

    // data sub-chunk
    wav.add(_ascii('data'));
    wav.add(_uint32Le(dataSize));
    wav.add(pcm.buffer.asUint8List(pcm.offsetInBytes, dataSize));

    return wav.toBytes();
  }

  static List<int> _ascii(String s) => s.codeUnits;

  static List<int> _uint16Le(int v) => [v & 0xFF, (v >> 8) & 0xFF];

  static List<int> _uint32Le(int v) => [
        v & 0xFF,
        (v >> 8) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 24) & 0xFF,
      ];
}

enum ChirpType {
  /// Chiziqli sweep — f(t) = f0 + (f1-f0)·t/T. Past chastotalarda yaxshi.
  linear,

  /// Eksponensial (logarifmik) sweep — har oktava bo'yicha teng vaqt.
  /// Akustik tahlil uchun yaxshiroq (har oktava bir xil energiya).
  exponential,
}
