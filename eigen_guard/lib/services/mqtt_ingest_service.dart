import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart' as mqtt;
import 'package:mqtt_client/mqtt_server_client.dart' as mqtt;
import '../models/edge_sensor_reading.dart';

/// Sprint 15 — MQTT Ingest Service (FRAMEWORK).
///
/// **Vazifa:** ESP32 Edge node'lardan kelgan telemetriya MQTT brokerdan
/// olib, `EdgeSensorReading` ga aylantirish va `SensorFusionArbiter` ga
/// uzatish.
///
/// **Topic sxemasi:** `eigenguard/<site>/<device>/{vib,temp,acoustic}`
///
/// **Hozirgi holat:** `mqtt_client` paketi qo'shilmagan — backend interfeysi
/// stubdan iborat. Mocked rejim default — har 100ms da synthetic o'qish chiqaradi
/// (ESP32 hali yo'qligida arbiter va UI ni test qilish uchun). Real ESP32
/// ulanganda `connectReal(broker, port)` chaqirilib mqtt_client orqali
/// haqiqiy brokerga ulanadi (TODO: kelgusi sprint).
///
/// **Threading:** Hammasi ValueNotifier orqali — main thread bloklanmaydi.
/// Mock timer ham 100ms granularda ishlaydi, og'ir hisoblash yo'q.
enum MqttConnectionState {
  disconnected,
  connecting,
  connected,
  mockedStreaming,
  error,
}

class MqttIngestService {
  static final MqttIngestService _instance = MqttIngestService._();
  factory MqttIngestService() => _instance;
  MqttIngestService._();

  // ── Public observables ──────────────────────────────────────────────
  /// Joriy ulanish holati.
  final ValueNotifier<MqttConnectionState> state =
      ValueNotifier(MqttConnectionState.disconnected);

  /// Oxirgi qabul qilingan Edge reading (har channel uchun yangilanadi).
  final ValueNotifier<EdgeSensorReading?> lastReading =
      ValueNotifier<EdgeSensorReading?>(null);

  /// Faol Edge qurilmalar ro'yxati (deviceId → eng so'nggi reading).
  /// HUD chip'da "3 ta qurilma faol" deb ko'rsatish uchun.
  final ValueNotifier<Map<String, EdgeSensorReading>> devices =
      ValueNotifier<Map<String, EdgeSensorReading>>({});

  /// Broadcast stream — Fusion arbiter va boshqa subscriberlar uchun.
  Stream<EdgeSensorReading> get readings => _readingsCtrl.stream;
  final StreamController<EdgeSensorReading> _readingsCtrl =
      StreamController<EdgeSensorReading>.broadcast();

  // ── Internal state ──────────────────────────────────────────────────
  Timer? _mockTimer;
  final Random _rng = Random();
  double _mockPhase = 0;
  String _mockDeviceId = 'mock-esp32-A1';
  String _mockSiteTag = 'demo-site/pump-1';
  // Real broker (Sprint 16)
  mqtt.MqttServerClient? _brokerClient;
  StreamSubscription<List<mqtt.MqttReceivedMessage<mqtt.MqttMessage>>>?
      _brokerSub;
  String _topicFilter = 'eigenguard/+/+/+';

  /// 0.0..1.0 — mock simulyatsiyasidagi "tebranish darajasi".
  /// 0 — har doim sokin (vibration silent), 1 — har doim alert.
  /// Default 0.15 — vaqti-vaqti bilan rezonans, asosan sokin.
  double _mockIntensity = 0.15;

  // ────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ────────────────────────────────────────────────────────────────────

  /// Mocked stream'ni boshlash (default 100ms interval).
  /// ESP32 fizik ulanmagunicha shu rejim ishlatiladi.
  void startMockStream({
    Duration interval = const Duration(milliseconds: 100),
    String? deviceId,
    String? siteTag,
    double intensity = 0.15,
  }) {
    stopAll();
    if (deviceId != null) _mockDeviceId = deviceId;
    if (siteTag != null) _mockSiteTag = siteTag;
    _mockIntensity = intensity.clamp(0.0, 1.0);
    state.value = MqttConnectionState.mockedStreaming;
    _mockTimer = Timer.periodic(interval, (_) => _emitMockReading());
  }

  /// Mock intensivligini live tarzda o'zgartirish (HUD slider uchun).
  void setMockIntensity(double v) {
    _mockIntensity = v.clamp(0.0, 1.0);
  }

  /// **Sprint 16 — Real MQTT broker ulanish.**
  /// Auto-reconnect + resubscribe on reconnect yoqilgan. Default QoS 1.
  /// Topic filter default `eigenguard/+/+/+` (3 darajali wildcard:
  /// `eigenguard/<site>/<device>/<channel>`).
  ///
  /// `username`/`password` bo'sh string yoki null — anonymous ulanish.
  /// 10-sekundlik timeout — connect xato bo'lsa `false` qaytadi (silent fail,
  /// caller mock'ga qaytishi mumkin).
  Future<bool> connectReal({
    required String brokerHost,
    int port = 1883,
    String clientId = 'eigenguard-mobile',
    String? username,
    String? password,
    String topicFilter = 'eigenguard/+/+/+',
  }) async {
    stopAll();
    state.value = MqttConnectionState.connecting;
    _topicFilter = topicFilter;

    final c = mqtt.MqttServerClient.withPort(brokerHost, clientId, port);
    c.keepAlivePeriod = 30;
    c.autoReconnect = true;
    c.resubscribeOnAutoReconnect = true;
    c.logging(on: false);
    c.connectionMessage = mqtt.MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .withWillQos(mqtt.MqttQos.atLeastOnce);

    c.onConnected = () => state.value = MqttConnectionState.connected;
    c.onAutoReconnect = () => state.value = MqttConnectionState.connecting;
    c.onSubscribed = (topic) => debugPrint('[MQTT] Subscribed: $topic');
    c.onDisconnected = () {
      if (state.value != MqttConnectionState.disconnected &&
          state.value != MqttConnectionState.connecting) {
        state.value = MqttConnectionState.error;
      }
    };

    try {
      final hasUser = username != null && username.isNotEmpty;
      final hasPass = password != null && password.isNotEmpty;
      final status = await c
          .connect(hasUser ? username : null, hasPass ? password : null)
          .timeout(const Duration(seconds: 10));
      if (status == null ||
          status.state != mqtt.MqttConnectionState.connected) {
        state.value = MqttConnectionState.error;
        try {
          c.disconnect();
        } catch (_) {}
        return false;
      }
    } catch (e) {
      state.value = MqttConnectionState.error;
      debugPrint('[MQTT] Connect err: $e');
      try {
        c.disconnect();
      } catch (_) {}
      return false;
    }

    c.subscribe(_topicFilter, mqtt.MqttQos.atLeastOnce);
    _brokerSub = c.updates?.listen((msgs) {
      for (final m in msgs) {
        try {
          final pubMsg = m.payload as mqtt.MqttPublishMessage;
          _handleIncomingMessage(m.topic, pubMsg.payload.message);
        } catch (e) {
          debugPrint('[MQTT] Message err: $e');
        }
      }
    });

    _brokerClient = c;
    return true;
  }

  /// Topic'dan device/channel/site parse qilib payload'ni
  /// BYOD-tolerant `EdgeSensorReading.tryDecodePayload` orqali parse qiladi.
  /// Format: `eigenguard/<site>/<device>/<channel>` (3+ darajali).
  void _handleIncomingMessage(String topic, List<int> payloadBytes) {
    final parts = topic.split('/');
    String deviceId;
    String channel = 'vib';
    String? siteTag;
    if (parts.length >= 4 && parts.first == 'eigenguard') {
      siteTag = parts[1];
      deviceId = parts[2];
      channel = parts[3];
    } else if (parts.length >= 3) {
      siteTag = parts[parts.length - 3];
      deviceId = parts[parts.length - 2];
      channel = parts.last;
    } else if (parts.length == 2) {
      deviceId = parts[0];
      channel = parts[1];
    } else {
      deviceId = topic.isEmpty ? 'unknown' : topic;
    }
    final reading = EdgeSensorReading.tryDecodePayload(
      deviceId,
      channel,
      payloadBytes,
      siteTag: siteTag,
    );
    if (reading != null) _publishReading(reading);
  }

  /// Tashqi manbadan (masalan BLE bridge yoki test) reading kiritish.
  /// Arbiter va devices ro'yxati avtomatik yangilanadi.
  void ingestExternalReading(EdgeSensorReading reading) {
    _publishReading(reading);
  }

  /// Hamma narsani to'xtatish (mock + real).
  void stopAll() {
    _mockTimer?.cancel();
    _mockTimer = null;
    _brokerSub?.cancel();
    _brokerSub = null;
    if (_brokerClient != null) {
      try {
        _brokerClient!.disconnect();
      } catch (_) {}
      _brokerClient = null;
    }
    state.value = MqttConnectionState.disconnected;
  }

  /// Boshqaruvchi: mock yoki real stream faol ekanmi.
  bool get isStreaming =>
      state.value == MqttConnectionState.mockedStreaming ||
      state.value == MqttConnectionState.connected;

  /// HUD chip uchun yorliq matni.
  String get statusLabel {
    switch (state.value) {
      case MqttConnectionState.disconnected:
        return 'MQTT —';
      case MqttConnectionState.connecting:
        return 'MQTT...';
      case MqttConnectionState.connected:
        return 'EDGE FAOL';
      case MqttConnectionState.mockedStreaming:
        return 'MOCK EDGE';
      case MqttConnectionState.error:
        return 'MQTT ERR';
    }
  }

  void dispose() {
    stopAll();
    _readingsCtrl.close();
    state.dispose();
    lastReading.dispose();
    devices.dispose();
  }

  // ────────────────────────────────────────────────────────────────────
  // INTERNAL: mock generator
  // ────────────────────────────────────────────────────────────────────
  void _emitMockReading() {
    _mockPhase += 0.0628; // ~10 cycles per second @ 100ms
    if (_mockPhase > 2 * pi) _mockPhase -= 2 * pi;

    // Asosiy fon: sinusoidal "normal vibration" + Gaussian noise
    final base = 0.3 * sin(_mockPhase) + (_rng.nextDouble() - 0.5) * 0.2;

    // Spike ehtimoli mockIntensity ga proportional
    final shouldSpike = _rng.nextDouble() < _mockIntensity;
    final spike = shouldSpike ? 1.5 + _rng.nextDouble() * 1.5 : 0.0;

    final ampMm = (base.abs() + spike).clamp(0.0, 5.0);
    final freq = shouldSpike
        ? 20.0 + _rng.nextDouble() * 40.0  // resonance band
        : 1.0 + _rng.nextDouble() * 3.0;    // baseline
    final tempC = 45.0 + sin(_mockPhase * 0.3) * 3.0;

    final reading = EdgeSensorReading(
      deviceId: _mockDeviceId,
      siteTag: _mockSiteTag,
      channel: 'vib',
      edgeTimestamp: DateTime.now(),
      receivedAt: DateTime.now(),
      vibrationAmplitudeMm: ampMm,
      dominantFrequencyHz: freq,
      temperatureC: tempC,
      signalQuality: 0.9 + _rng.nextDouble() * 0.1,
    );
    _publishReading(reading);
  }

  void _publishReading(EdgeSensorReading reading) {
    lastReading.value = reading;
    final updated = Map<String, EdgeSensorReading>.from(devices.value);
    updated[reading.deviceId] = reading;
    devices.value = updated;
    if (!_readingsCtrl.isClosed) {
      _readingsCtrl.add(reading);
    }
  }
}
