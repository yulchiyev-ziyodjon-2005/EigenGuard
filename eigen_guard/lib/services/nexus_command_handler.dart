import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/material_profile.dart';
import 'material_service.dart';
import 'mobile_command_bus.dart';
import 'nexus_auth_service.dart';
import 'nexus_upload_service.dart';
import 'nexus_ws_client.dart';
import 'sensor_fusion_arbiter.dart';

/// Sprint 18 — Nexus'dan kelgan buyruqlarni qayta ishlovchi dispatcher.
///
/// **Ikki yo'l bilan ulanishi mumkin:**
/// 1. **WebSocket (real-time, default)** — `NexusWsClient.commands` stream
/// 2. **HTTP poll (fallback)** — `GET /api/v1/commands/pending` har 60s
///    + `start()` paytida darhol bir marta. WebSocket uzilgan paytda yoki
///    app boshlanishida WS ulanishidan oldin kelgan commandlarni qabul qilish
///    uchun.
///
/// **Dedup**: har bir command `id` `_processedIds` set'iga yoziladi (FIFO 500).
/// Bir xil ID ikkinchi marta kelganda silent skip qilinadi — WS push va HTTP
/// poll bir-birini takrorlasa duplicate ish qilmaydi.
///
/// **Ack — ikkala yo'l bilan**:
/// - WS connected → `NexusWsClient.sendAck()` (frame)
/// - WS not connected → `POST /api/v1/commands/{id}/ack` (HTTP fallback)
///
/// Buyruq turlari (Nexus `CommandType` enum bilan mos):
///   notify, start_scan, stop_scan, enable_demo_mode, disable_demo_mode,
///   set_material, take_snapshot, sync_now, custom
class NexusCommandHandler {
  static final NexusCommandHandler _instance = NexusCommandHandler._();
  factory NexusCommandHandler() => _instance;
  NexusCommandHandler._();

  final NexusWsClient _ws = NexusWsClient();
  final NexusAuthService _auth = NexusAuthService();
  final MobileCommandBus _bus = MobileCommandBus();
  final SensorFusionArbiter _arbiter = SensorFusionArbiter();
  final MaterialService _material = MaterialService();
  final NexusUploadService _uploader = NexusUploadService();

  StreamSubscription<NexusIncomingCommand>? _sub;
  Timer? _pollTimer;
  http.Client? _http;
  bool _polling = false;

  /// Qayta ishlangan command ID'lari — FIFO cap 500.
  /// WS va HTTP poll bir xil commandni ikki marta keltirsa, ikkinchisi skip bo'ladi.
  final Set<String> _processedIds = <String>{};
  static const int _maxDedupSize = 500;

  /// App startup'da chaqiriladi — bir marta.
  void start({Duration pollInterval = const Duration(seconds: 60)}) {
    _sub?.cancel();
    _sub = _ws.commands.listen(_dispatch);
    _http = http.Client();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) => pollNow());
    // Boshlanishida darhol poll qilamiz — WS hali ulanmagan paytda
    Future.microtask(pollNow);
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _http?.close();
    _http = null;
  }

  /// HTTP poll: `GET /commands/pending`. Login bo'lmagan / endpoint bo'lmasa no-op.
  /// Public — boshqa joydan ham chaqirsa bo'ladi (masalan login muvaffaqiyatli bo'lgach).
  Future<void> pollNow() async {
    if (_polling) return;
    if (!_auth.isAuthenticated || _http == null) return;
    final base = _auth.baseUrl;
    final devId = _auth.deviceIdentifier;
    if (base == null || devId == null) return;
    _polling = true;
    try {
      final uri = Uri.parse(
          '$base/api/v1/commands/pending?device_identifier=$devId');
      final resp = await _http!
          .get(uri, headers: _auth.authHeaders(contentType: ''))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) {
        debugPrint('[NexusCmd] poll http ${resp.statusCode}');
        return;
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is! List) return;
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        final cmd = _fromWire(item);
        if (cmd != null) await _dispatch(cmd);
      }
    } catch (e) {
      debugPrint('[NexusCmd] poll err: $e');
    } finally {
      _polling = false;
    }
  }

  /// Server'dan kelgan turli formatlarni bitta `NexusIncomingCommand` ga
  /// keltiradi (WS `to_wire()` va REST `CommandOut` schema'lari farq qiladi).
  NexusIncomingCommand? _fromWire(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final type = (json['command_type'] ?? json['type']) as String?;
    if (id == null || type == null) return null;
    return NexusIncomingCommand(
      id: id,
      type: type,
      payload: ((json['payload'] as Map?)?.cast<String, dynamic>()) ?? const {},
      issuedAt: DateTime.tryParse(
              (json['created_at'] ?? json['issued_at']) as String? ?? '') ??
          DateTime.now(),
      expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? '') ??
          DateTime.now().add(const Duration(hours: 24)),
    );
  }

  Future<void> _dispatch(NexusIncomingCommand cmd) async {
    // Dedup
    if (_processedIds.contains(cmd.id)) {
      debugPrint('[NexusCmd] dedup skip ${cmd.id}');
      return;
    }
    _processedIds.add(cmd.id);
    while (_processedIds.length > _maxDedupSize) {
      _processedIds.remove(_processedIds.first);
    }

    debugPrint('[NexusCmd] dispatch ${cmd.type} (${cmd.id})');
    try {
      switch (cmd.type) {
        case 'notify':
          _bus.showNotify(
            title: (cmd.payload['title'] as String?) ?? 'EigenGuard',
            message: (cmd.payload['message'] as String?) ?? '',
            riskPercent: (cmd.payload['risk_percent'] as num?)?.toDouble(),
          );
          await _ack(cmd.id, success: true);
          break;

        case 'start_scan':
          _bus.requestStartScan();
          await _ack(cmd.id, success: true);
          break;

        case 'stop_scan':
          _bus.requestStopScan();
          await _ack(cmd.id, success: true);
          break;

        case 'enable_demo_mode':
          _arbiter.demoMode = true;
          await _ack(cmd.id, success: true, result: {'demo_mode': true});
          break;

        case 'disable_demo_mode':
          _arbiter.demoMode = false;
          await _ack(cmd.id, success: true, result: {'demo_mode': false});
          break;

        case 'set_material':
          final materialId = cmd.payload['material_id'] as String?;
          if (materialId == null || materialId.isEmpty) {
            await _ack(cmd.id,
                success: false,
                errorMessage: 'material_id payload\'da yo\'q');
            return;
          }
          final profile = MaterialPresets.byId(materialId);
          _material.setManual(profile);
          await _ack(cmd.id,
              success: true, result: {'material_id': profile.id});
          break;

        case 'take_snapshot':
          _bus.requestSnapshot();
          await _ack(cmd.id, success: true);
          break;

        case 'sync_now':
          await _uploader.syncNow();
          await _ack(cmd.id,
              success: true, result: {'last_error': _uploader.lastError.value});
          break;

        case 'custom':
          debugPrint('[NexusCmd] custom payload: ${cmd.payload}');
          await _ack(cmd.id, success: true);
          break;

        default:
          await _ack(cmd.id,
              success: false,
              errorMessage: 'Noma\'lum command turi: ${cmd.type}');
      }
    } catch (e, st) {
      debugPrint('[NexusCmd] handle err: $e\n$st');
      await _ack(cmd.id, success: false, errorMessage: e.toString());
    }
  }

  /// Ack — WS connected bo'lsa frame, aks holda HTTP POST.
  Future<void> _ack(
    String id, {
    required bool success,
    String? errorMessage,
    Map<String, dynamic>? result,
  }) async {
    if (_ws.state.value == NexusWsState.connected) {
      _ws.sendAck(id,
          success: success, errorMessage: errorMessage, result: result);
      return;
    }
    // HTTP fallback
    if (!_auth.isAuthenticated || _http == null) return;
    final base = _auth.baseUrl;
    if (base == null) return;
    try {
      await _http!
          .post(
            Uri.parse('$base/api/v1/commands/$id/ack'),
            headers: _auth.authHeaders(),
            body: jsonEncode({
              'success': success,
              if (errorMessage != null) 'error_message': errorMessage,
              if (result != null) 'result_payload': result,
            }),
          )
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[NexusCmd] http ack err: $e');
    }
  }
}
