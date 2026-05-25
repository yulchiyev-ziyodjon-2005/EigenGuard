import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';

/// IMU Service — Qurilma Giroskop va Akselerometri (Sensor Fusion)
class ImuService {
  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  double _accelX = 0, _accelY = 0, _accelZ = 0;
  double _gyroX = 0, _gyroY = 0, _gyroZ = 0;

  bool _isListening = false;

  void startListening() {
    if (_isListening) return;

    _accelSub = userAccelerometerEventStream().listen((event) {
      _accelX = event.x;
      _accelY = event.y;
      _accelZ = event.z;
    });

    _gyroSub = gyroscopeEventStream().listen((event) {
      _gyroX = event.x;
      _gyroY = event.y;
      _gyroZ = event.z;
    });

    _isListening = true;
  }

  void stopListening() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _isListening = false;
  }

  /// Kameradan farqli o'laroq, IMU tezligi millisekund uchun bir nechta marotaba.
  /// U kamera freymi chaqirilgan vaqtda so'ngi holatini olish orqali KalmanGa beriladi.
  List<double> getRecentImuData() {
    return [_accelX, _accelY, _accelZ, _gyroX, _gyroY, _gyroZ];
  }

  void dispose() {
    stopListening();
  }
}
