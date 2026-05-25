import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'nexus_auth_service.dart';

/// Sprint 18 — Nexus mobile WebSocket client.
///
/// URL: `ws[s]://<nexus-base>/api/v1/ws/mobile?token=<JWT>&device_identifier=<UUID>`
///
/// Real-time'da Nexus'dan command'larni qabul qiladi va ack yuboradi.
/// Auto-reconnect exponential backoff bilan (1s → 2s → 4s → 8s → 16s → 30s cap).
/// Login bo'lmagan paytda hech narsa qilmaydi. Logout qilinganda yopiladi.
enum NexusWsState { disconnected, connecting, connected, error }

class NexusIncomingCommand {
  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime issuedAt;
  final DateTime expiresAt;

  const NexusIncomingCommand({
    required this.id,
    required this.type,
    required this.payload,
    required this.issuedAt,
    required this.expiresAt,
  });

  factory NexusIncomingCommand.fromJson(Map<String, dynamic> json) =>
      NexusIncomingCommand(
        id: json['id'] as String,
        type: json['type'] as String,
        payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
        issuedAt: DateTime.tryParse(json['issued_at'] as String? ?? '') ??
            DateTime.now(),
        expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? '') ??
            DateTime.now().add(const Duration(hours: 24)),
      );
}

class NexusWsClient {
  static final NexusWsClient _instance = NexusWsClient._();
  factory NexusWsClient() => _instance;
  NexusWsClient._();

  final NexusAuthService _auth = NexusAuthService();

  // ── Public observables ──────────────────────────────────────────────
  final ValueNotifier<NexusWsState> state =
      ValueNotifier(NexusWsState.disconnected);
  final ValueNotifier<DateTime?> lastMessageAt = ValueNotifier(null);
  final ValueNotifier<int> pendingCommandCount = ValueNotifier(0);

  /// Kelayotgan buyruqlar oqimi — NexusCommandHandler subscribe qiladi.
  Stream<NexusIncomingCommand> get commands => _cmdCtrl.stream;
  final StreamController<NexusIncomingCommand> _cmdCtrl =
      StreamController<NexusIncomingCommand>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _heartbeat;
  Timer? _reconnect;
  int _backoffSeconds = 1;
  bool _wantsConnection = false;

  // ────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ────────────────────────────────────────────────────────────────────

  /// Login bo'lgan paytda chaqirilishi kerak — connect + auto-reconnect.
  void connect() {
    if (!_auth.isAuthenticated) {
      state.value = NexusWsState.disconnected;
      return;
    }
    _wantsConnection = true;
    _backoffSeconds = 1;
    _connectInternal();
  }

  /// Logout / kerakmas bo'lganda chaqiriladi.
  void disconnect() {
    _wantsConnection = false;
    _reconnect?.cancel();
    _reconnect = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close(ws_status.normalClosure);
    } catch (_) {}
    _channel = null;
    state.value = NexusWsState.disconnected;
  }

  /// Buyruq bajarilganligini Nexus'ga xabardor qilish.
  /// `success=true` → status=acknowledged, `false` → failed.
  void sendAck(
    String commandId, {
    bool success = true,
    String? errorMessage,
    Map<String, dynamic>? result,
  }) {
    if (_channel == null || state.value != NexusWsState.connected) return;
    try {
      _channel!.sink.add(jsonEncode({
        'kind': 'ack',
        'command_id': commandId,
        'success': success,
        if (errorMessage != null) 'error_message': errorMessage,
        if (result != null) 'result': result,
      }));
    } catch (e) {
      debugPrint('[NexusWs] ack err: $e');
    }
  }

  void dispose() {
    disconnect();
    _cmdCtrl.close();
    state.dispose();
    lastMessageAt.dispose();
    pendingCommandCount.dispose();
  }

  // ────────────────────────────────────────────────────────────────────
  // INTERNAL
  // ────────────────────────────────────────────────────────────────────

  void _connectInternal() {
    if (!_wantsConnection) return;
    final base = _auth.baseUrl;
    final token = _auth.token;
    final devId = _auth.deviceIdentifier;
    if (base == null || token == null || devId == null) {
      state.value = NexusWsState.disconnected;
      return;
    }
    // http(s) → ws(s)
    final wsScheme = base.startsWith('https://') ? 'wss://' : 'ws://';
    final host = base.replaceFirst(RegExp(r'^https?://'), '');
    final uri = Uri.parse(
      '$wsScheme$host/api/v1/ws/mobile?token=$token&device_identifier=$devId'
      '&platform=${defaultTargetPlatform.name}&device_name=EigenGuard Mobile',
    );

    state.value = NexusWsState.connecting;
    try {
      _channel = WebSocketChannel.connect(uri);
      _sub = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );
      // Heartbeat — har 30 sek ping
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
        try {
          _channel?.sink.add(jsonEncode({'kind': 'ping'}));
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('[NexusWs] connect err: $e');
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    lastMessageAt.value = DateTime.now();
    try {
      final msg = jsonDecode(raw as String);
      if (msg is! Map<String, dynamic>) return;
      final kind = msg['kind'] as String?;
      switch (kind) {
        case 'hello':
          state.value = NexusWsState.connected;
          _backoffSeconds = 1; // reset
          final pendingCount = (msg['pending_count'] as int?) ?? 0;
          pendingCommandCount.value = pendingCount;
          debugPrint('[NexusWs] connected (pending=$pendingCount)');
          break;
        case 'command':
          final data = msg['data'] as Map<String, dynamic>?;
          if (data != null) {
            final cmd = NexusIncomingCommand.fromJson(data);
            _cmdCtrl.add(cmd);
          }
          break;
        case 'pong':
          // heartbeat reply
          break;
        default:
          debugPrint('[NexusWs] unknown kind: $kind');
      }
    } catch (e) {
      debugPrint('[NexusWs] parse err: $e');
    }
  }

  void _onError(Object error, [StackTrace? st]) {
    debugPrint('[NexusWs] stream err: $error');
    state.value = NexusWsState.error;
  }

  void _onDone() {
    debugPrint('[NexusWs] connection closed');
    _heartbeat?.cancel();
    _sub?.cancel();
    _channel = null;
    state.value = NexusWsState.disconnected;
    if (_wantsConnection) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_wantsConnection) return;
    _reconnect?.cancel();
    _reconnect = Timer(Duration(seconds: _backoffSeconds), () {
      _backoffSeconds = (_backoffSeconds * 2).clamp(1, 30);
      _connectInternal();
    });
  }
}
