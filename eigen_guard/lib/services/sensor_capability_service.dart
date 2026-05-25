import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Qurilma sensorlari va kanallari haqida ma'lumot.
/// Phase 2+ (active probing, sensor fusion) shu xizmat orqali nimaning
/// mavjudligini biladi.
class SensorCapabilities {
  final bool hasAccelerometer;
  final bool hasGyroscope;
  final bool hasMagnetometer;
  final bool hasBarometer;
  final bool hasCamera;
  final bool hasMicrophone;
  final bool hasFlashlight;
  final bool hasVibrationMotor;
  final bool hasGps;
  final bool hasBle;
  final bool hasNfc;
  final bool hasToFLidar;

  const SensorCapabilities({
    this.hasAccelerometer = false,
    this.hasGyroscope = false,
    this.hasMagnetometer = false,
    this.hasBarometer = false,
    this.hasCamera = false,
    this.hasMicrophone = false,
    this.hasFlashlight = false,
    this.hasVibrationMotor = false,
    this.hasGps = false,
    this.hasBle = false,
    this.hasNfc = false,
    this.hasToFLidar = false,
  });

  /// Qisqa ko'rinish (UI debug paneli uchun)
  String get summary {
    final available = <String>[];
    if (hasAccelerometer) available.add('Accel');
    if (hasGyroscope) available.add('Gyro');
    if (hasMagnetometer) available.add('Mag');
    if (hasBarometer) available.add('Baro');
    if (hasCamera) available.add('Cam');
    if (hasMicrophone) available.add('Mic');
    if (hasFlashlight) available.add('Flash');
    if (hasVibrationMotor) available.add('Vibro');
    if (hasGps) available.add('GPS');
    if (hasBle) available.add('BLE');
    if (hasNfc) available.add('NFC');
    if (hasToFLidar) available.add('LiDAR');
    return available.join(' · ');
  }
}

/// SensorCapabilityService — qurilma imkoniyatlarini bir martalik tekshiruvchi
/// Singleton. Ishga tushganda asinxron yo'l bilan barcha sensorlarni
/// "probe" qiladi va `current` ga yozadi.
class SensorCapabilityService {
  static final SensorCapabilityService _instance =
      SensorCapabilityService._internal();
  factory SensorCapabilityService() => _instance;
  SensorCapabilityService._internal();

  final ValueNotifier<SensorCapabilities> current =
      ValueNotifier<SensorCapabilities>(const SensorCapabilities());

  bool _probed = false;

  /// `main()` da bir marta chaqiriladi. Sensorlarni 1.5 sek davomida tinglab,
  /// qaysilari ishlayotganini aniqlaydi.
  Future<void> probe() async {
    if (_probed) return;
    _probed = true;

    bool accel = false;
    bool gyro = false;
    bool mag = false;
    bool baro = false;

    final futures = <Future<void>>[];

    // Accelerometer
    futures.add(_probeStream<UserAccelerometerEvent>(
      userAccelerometerEventStream(),
      onAlive: () => accel = true,
    ));
    // Gyroscope
    futures.add(_probeStream<GyroscopeEvent>(
      gyroscopeEventStream(),
      onAlive: () => gyro = true,
    ));
    // Magnetometer
    futures.add(_probeStream<MagnetometerEvent>(
      magnetometerEventStream(),
      onAlive: () => mag = true,
    ));
    // Barometer — `sensors_plus` da mavjud emas (Q4 2025 holatiga).
    // Kelajakda `flutter_barometer` yoki platform channel orqali.
    baro = false;

    // 1.5 sek kutish — agar shu vaqtda hech qanday hodisa kelmasa, sensor yo'q.
    await Future.any([
      Future.wait(futures),
      Future.delayed(const Duration(milliseconds: 1500)),
    ]);

    current.value = SensorCapabilities(
      hasAccelerometer: accel,
      hasGyroscope: gyro,
      hasMagnetometer: mag,
      hasBarometer: baro,
      // Kameralar/mikrofon/flash — runtime permission orqali aniqlanadi
      // (CameraService.initialize ga ulanadi). Bu yerda optimistik true.
      hasCamera: true,
      hasMicrophone: true,
      hasFlashlight: true,
      hasVibrationMotor: true, // ~barcha telefonlarda bor
      hasGps: false, // Phase 3 da geolocator bilan tekshiriladi
      hasBle: false, // Phase 5 da flutter_blue_plus bilan
      hasNfc: false, // ixtiyoriy kelajak
      hasToFLidar: false, // Pro qurilmalar — arcore plugin bilan
    );

    debugPrint('[SensorCapability] ${current.value.summary}');
  }

  /// Yordamchi — birinchi event kelsa, alive deb belgilab oqimni yopadi.
  Future<void> _probeStream<T>(Stream<T> stream,
      {required void Function() onAlive}) async {
    final completer = Completer<void>();
    StreamSubscription<T>? sub;
    sub = stream.listen((_) {
      onAlive();
      sub?.cancel();
      if (!completer.isCompleted) completer.complete();
    }, onError: (_) {
      sub?.cancel();
      if (!completer.isCompleted) completer.complete();
    });

    // 1.4 sek timeout (umumiy probe 1.5 sek dan kichikroq)
    Future.delayed(const Duration(milliseconds: 1400), () {
      sub?.cancel();
      if (!completer.isCompleted) completer.complete();
    });

    return completer.future;
  }
}
