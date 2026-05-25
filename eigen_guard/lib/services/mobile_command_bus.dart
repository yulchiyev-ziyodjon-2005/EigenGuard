import 'package:flutter/foundation.dart';

/// Sprint 18 — In-app command bus.
///
/// Nexus'dan kelgan buyruqlarni qabul qiluvchi service'lar (Dashboard,
/// MaterialService, va h.k.) shu bus ga subscribe bo'ladi. Bus'ning o'zi
/// hech qanday ish bajarmaydi — faqat trigger signal yetkazadi. Buyruq
/// haqiqiy bajarilishi qabul qiluvchi widget'da yuz beradi.
///
/// Trigger counter'lar incremental — Dashboard `ValueListenableBuilder`
/// orqali har incrementni bitta xodisa sifatida qayta ishlaydi.
class MobileCommandBus {
  static final MobileCommandBus _instance = MobileCommandBus._();
  factory MobileCommandBus() => _instance;
  MobileCommandBus._();

  /// Skanerlash boshlash (start_scan).
  final ValueNotifier<int> startScanTrigger = ValueNotifier(0);

  /// Skanerlash to'xtatish (stop_scan).
  final ValueNotifier<int> stopScanTrigger = ValueNotifier(0);

  /// Snapshot olish (take_snapshot — joriy o'lchovni saqlash).
  final ValueNotifier<int> snapshotTrigger = ValueNotifier(0);

  /// Notify message (string).
  /// Dashboard `ValueListenableBuilder` orqali snackbar/dialog ko'rsatadi.
  final ValueNotifier<NotifyEvent?> notifyEvent = ValueNotifier(null);

  void requestStartScan() => startScanTrigger.value++;
  void requestStopScan() => stopScanTrigger.value++;
  void requestSnapshot() => snapshotTrigger.value++;
  void showNotify({required String title, required String message, double? riskPercent}) {
    notifyEvent.value = NotifyEvent(
      title: title,
      message: message,
      riskPercent: riskPercent,
      timestamp: DateTime.now(),
    );
  }

  void dispose() {
    startScanTrigger.dispose();
    stopScanTrigger.dispose();
    snapshotTrigger.dispose();
    notifyEvent.dispose();
  }
}

class NotifyEvent {
  final String title;
  final String message;
  final double? riskPercent;
  final DateTime timestamp;

  const NotifyEvent({
    required this.title,
    required this.message,
    this.riskPercent,
    required this.timestamp,
  });

  bool get isCritical => (riskPercent ?? 0) >= 75;
}
