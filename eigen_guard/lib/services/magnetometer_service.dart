import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Magnitometr o'qishi.
class MagneticReading {
  /// X, Y, Z komponentalar (µT, mikroTesla)
  final double x;
  final double y;
  final double z;
  /// Total magnit maydon kuchi (µT) = √(x² + y² + z²)
  final double magnitudeUt;
  /// Hozirgi taxminiy fon (EMA) — Yer maydoni odatda 25-65 µT
  final double baselineUt;
  /// Fon dan og'ish (anomaliya)
  final double deltaUt;
  /// Anomaliya aniqlandi (temir/po'lat yaqin)
  final bool isAnomalous;

  const MagneticReading({
    required this.x,
    required this.y,
    required this.z,
    required this.magnitudeUt,
    required this.baselineUt,
    required this.deltaUt,
    required this.isAnomalous,
  });

  factory MagneticReading.empty() => const MagneticReading(
        x: 0,
        y: 0,
        z: 0,
        magnitudeUt: 0,
        baselineUt: 0,
        deltaUt: 0,
        isAnomalous: false,
      );
}

/// Magnetometer xizmati — temir/po'lat materiallar yaqinligini aniqlaydi.
///
/// **Fizik asos:** Yer magnit maydoni ~25-65 µT (geografiyaga bog'liq).
/// Ferromagnit metallar (temir, po'lat, nikel) bu maydonni mahalliy
/// buzadi. Telefon o'lchaganda 10+ µT og'ish odatda yaqin metall belgisi.
///
/// **Cheklov:** Telefon o'zi (ramka, batareya) ham noise beradi.
/// Shu sababli statik kalibratsiya (baseline EMA) ishlatamiz.
class MagnetometerService {
  static final MagnetometerService _instance =
      MagnetometerService._internal();
  factory MagnetometerService() => _instance;
  MagnetometerService._internal();

  /// Joriy o'qish — UI ulanadi
  final ValueNotifier<MagneticReading> reading =
      ValueNotifier<MagneticReading>(MagneticReading.empty());

  /// Anomaliya chegarasi (µT). 15+ ≈ yaqin metall.
  static const double anomalyThresholdUt = 15.0;

  /// EMA baseline koeffitsienti (yangi qiymat ulushi)
  /// Past = baseline sekin o'zgaradi (anomaliyani uzoq tutadi)
  static const double _baselineAlpha = 0.02;

  StreamSubscription<MagnetometerEvent>? _sub;
  double _baseline = 0;
  bool _baselineInitialized = false;

  /// Stream'ni boshlash. Asosan main() da yoki Dashboard initState'da chaqiriladi.
  void start() {
    if (_sub != null) return;
    _sub = magnetometerEventStream().listen(
      _handleEvent,
      onError: (e) {
        debugPrint('[Magnetometer] xato: $e');
      },
    );
  }

  void _handleEvent(MagnetometerEvent e) {
    final mag = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);

    // Baseline EMA — birinchi qiymat to'liq qabul qilinadi
    if (!_baselineInitialized) {
      _baseline = mag;
      _baselineInitialized = true;
    } else {
      _baseline = _baseline * (1 - _baselineAlpha) + mag * _baselineAlpha;
    }

    final delta = (mag - _baseline).abs();
    final anomalous = delta > anomalyThresholdUt;

    // Agar anomaliya — baselineni yangilashni sekinlashtirish
    // (anomaliyaning o'zi yangi baseline bo'lib qolmasligi uchun)
    if (anomalous) {
      // Oxirgi yangilashni qaytarib oladigan trik
      _baseline =
          _baseline * (1 - _baselineAlpha) / (1 - _baselineAlpha * 0.1) +
              0.01 * (mag - _baseline);
    }

    reading.value = MagneticReading(
      x: e.x,
      y: e.y,
      z: e.z,
      magnitudeUt: mag,
      baselineUt: _baseline,
      deltaUt: delta,
      isAnomalous: anomalous,
    );
  }

  /// Baseline'ni qo'lda qayta kalibrlash — atrof-muhit o'zgargan bo'lsa
  /// (foydalanuvchi boshqa joyga ko'chgan)
  void recalibrate() {
    _baselineInitialized = false;
    _baseline = 0;
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  void dispose() {
    stop();
  }
}
