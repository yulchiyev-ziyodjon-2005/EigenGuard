import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Joylashuv ma'lumoti — har bir skan uchun geo-tag.
class GeoLocation {
  final double latitude;
  final double longitude;
  /// Aniqlik (metr). Yuqori = yomon.
  final double accuracyMeters;
  /// Balandlik (metr) — agar mavjud
  final double? altitudeMeters;
  final DateTime timestamp;

  const GeoLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    this.altitudeMeters,
    required this.timestamp,
  });

  /// Kompakt matn: "41.3111, 69.2797 (±5m)"
  String get formatted =>
      '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}'
      ' (±${accuracyMeters.toStringAsFixed(0)}m)';
}

/// GeoLocationService — har skan uchun joylashuvni saqlaydi.
///
/// Sanoat va qurilish kontekstida muhim: skan qaerda olinganini bilish
/// (qaysi pol, qaysi devor, qaysi binoda). AI Consult'ga uzatilsa,
/// kontekstda hisobga olishi mumkin (geografik xavflar: zilzilali zona).
class GeoLocationService {
  static final GeoLocationService _instance =
      GeoLocationService._internal();
  factory GeoLocationService() => _instance;
  GeoLocationService._internal();

  final ValueNotifier<GeoLocation?> lastLocation =
      ValueNotifier<GeoLocation?>(null);

  bool _permissionRequested = false;

  /// Joylashuv ruxsatini so'rab, joriy joyni qaytaradi. Ruxsat berilmasa null.
  Future<GeoLocation?> getCurrent({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      // 1) Servis yoqilganmi?
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[Geo] joylashuv xizmati o\'chiq');
        return null;
      }

      // 2) Ruxsat
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        if (_permissionRequested) {
          return null;
        }
        _permissionRequested = true;
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        debugPrint('[Geo] ruxsat berilmadi');
        return null;
      }

      // 3) Joylashuv
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(timeout);

      final loc = GeoLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        altitudeMeters: position.altitude,
        timestamp: DateTime.now(),
      );
      lastLocation.value = loc;
      return loc;
    } catch (e) {
      debugPrint('[Geo] olishda xato: $e');
      return null;
    }
  }
}
