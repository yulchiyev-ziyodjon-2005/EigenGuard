import 'package:camera/camera.dart' as camera;
import 'package:flutter/foundation.dart';
import 'camera_service.dart';

enum AppFlashMode {
  /// O'chirilgan
  off,

  /// Avto — kamera o'zi qaror qiladi (kerak bo'lganda yoqadi)
  auto,

  /// To'liq yoqilgan (torch) — uzluksiz yoritish
  torch,
}

/// Kamera flash/torch boshqarish xizmati.
///
/// Tunda yoki past yorug'likda Optical Flow va YOLO sifatini saqlab qolish
/// uchun foydalanuvchi flash'ni yoqishi mumkin. Torch rejimi uzluksiz
/// yoritadi — video monitoring uchun kerakli.
class FlashService {
  static final FlashService _instance = FlashService._internal();
  factory FlashService() => _instance;
  FlashService._internal();

  /// Joriy rejim — UI ulanadi
  final ValueNotifier<AppFlashMode> mode =
      ValueNotifier<AppFlashMode>(AppFlashMode.off);

  final CameraService _camera = CameraService();

  /// Rejimni o'zgartirish. Kamera tayyor bo'lmasa — foydalanuvchi tanlovi
  /// saqlanadi va keyingi initialize'da qo'llanadi.
  Future<void> setMode(AppFlashMode newMode) async {
    final controller = _camera.controller;
    if (controller == null || !controller.value.isInitialized) {
      mode.value = newMode;
      return;
    }
    try {
      switch (newMode) {
        case AppFlashMode.off:
          await controller.setFlashMode(camera.FlashMode.off);
          break;
        case AppFlashMode.auto:
          await controller.setFlashMode(camera.FlashMode.auto);
          break;
        case AppFlashMode.torch:
          await controller.setFlashMode(camera.FlashMode.torch);
          break;
      }
      mode.value = newMode;
    } catch (e) {
      debugPrint('[Flash] setMode xato: $e');
    }
  }

  /// Keyingi rejimga aylanish — toggle button uchun
  Future<void> cycle() async {
    final next = switch (mode.value) {
      AppFlashMode.off => AppFlashMode.auto,
      AppFlashMode.auto => AppFlashMode.torch,
      AppFlashMode.torch => AppFlashMode.off,
    };
    await setMode(next);
  }
}
