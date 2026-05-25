import 'dart:convert';

/// Sprint 15 — B2G ekotizimi: Edge node (ESP32 + MPU6050 + MLX90614 + akustik)
/// dan kelgan bitta telemetriya o'qish nuqtasi.
///
/// **Topic sxemasi:** `eigenguard/<site>/<device>/{vib,temp,acoustic}`
/// Har bir topic JSON payload yuboradi; ushbu DTO uni dekoder qiladi.
///
/// Bu model `MeasurementRecord` dan kichikroq — chunki Edge node faqat real-time
/// telemetriya yuboradi, to'liq sessiya emas. Saqlanmaydi, faqat
/// `SensorFusionArbiter` orqali camera ma'lumotlari bilan korrelyatsiya qilinadi.
class EdgeSensorReading {
  /// ESP32 qurilma identifikatori (MAC yoki UUID). Ko'p qurilmali sitelarda
  /// kerak — qaysi nasos / dvigatel ekanligini ajratish uchun.
  final String deviceId;

  /// Manzil (ixtiyoriy) — masalan "Plant-A/Pump-7".
  final String? siteTag;

  /// Edge node tomonidan ishlab chiqarilgan vaqt belgisi.
  /// Mobil app vaqti emas — fusion uchun klock skew bo'lishi mumkin.
  final DateTime edgeTimestamp;

  /// Mobil app ushbu o'qishni qabul qilgan vaqt — fusion oynasi shu vaqtni
  /// ishlatadi (klock skew muammosini chetlab o'tish).
  final DateTime receivedAt;

  /// Tebranish amplitudasi (mm) — MPU6050 dan integral orqali.
  /// `null` → vib topic emas (faqat temp yoki acoustic).
  final double? vibrationAmplitudeMm;

  /// Dominant chastota (Hz) — MPU6050 FFT.
  final double? dominantFrequencyHz;

  /// IR harorat (°C) — MLX90614.
  final double? temperatureC;

  /// Akustik daraja (dB SPL) — agar mavjud bo'lsa.
  final double? acousticDb;

  /// Signal sifati (0..1) — Edge firmware mavjud bo'lsa o'zi yuboradi,
  /// aks holda RSSI / paket-yo'qotish dan hisoblanadi.
  final double signalQuality;

  /// MQTT topic suffix: 'vib' / 'temp' / 'acoustic'.
  final String channel;

  const EdgeSensorReading({
    required this.deviceId,
    required this.edgeTimestamp,
    required this.receivedAt,
    required this.channel,
    this.siteTag,
    this.vibrationAmplitudeMm,
    this.dominantFrequencyHz,
    this.temperatureC,
    this.acousticDb,
    this.signalQuality = 1.0,
  });

  /// Vibratsiya hodisasi mavjudmi? (Fusion arbiter uchun "hardware triggered").
  /// Default chegara: 1.0 mm yoki 5 Hz dan yuqori dominant chastota.
  bool isVibrationEvent({double ampThresholdMm = 1.0, double freqMinHz = 5.0}) {
    final amp = vibrationAmplitudeMm;
    final freq = dominantFrequencyHz;
    if (amp == null && freq == null) return false;
    final ampHit = amp != null && amp >= ampThresholdMm;
    final freqHit = freq != null && freq >= freqMinHz;
    return ampHit || freqHit;
  }

  /// **Sprint 16 — BYOD (Bring-Your-Own-Device) protocol-agnostic dekoder.**
  ///
  /// Har xil ESP32/Arduino/Particle/RPi firmware'lar har xil JSON formati
  /// yuborishi mumkin. Ushbu factory **chayqalgan** payload'larni ham
  /// qabul qiladi:
  /// - Maydon nomlari: `vib_mm` / `vibration` / `vibrationAmplitudeMm` / `amp` / `amplitude_mm`
  /// - Qiymatlar: number yoki string (`"1.42"` → 1.42)
  /// - Nested obyektlar: `{"data": {...}}` yoki `{"payload": {...}}`
  /// - Case-insensitive maydonlar
  /// - Yo'q bo'lgan maydonlar — `null` (ilova hech qachon crash bo'lmaydi)
  ///
  /// Kutilgan kanonik format (sodda ESP32 firmware uchun):
  /// ```json
  /// { "ts": 1731600000000, "vib_mm": 1.42, "freq_hz": 28.4,
  ///   "temp_c": 47.2, "snr": 0.92 }
  /// ```
  factory EdgeSensorReading.fromJson(
    String deviceId,
    String channel,
    Map<String, dynamic> json, {
    String? siteTag,
  }) {
    final f = _FlexJson(json);
    final tsMillis = f.intOf(
        const ['ts', 'timestamp', 't', 'time', 'epoch_ms', 'epochMs', 'unix']);
    final edgeTs = tsMillis != null
        ? DateTime.fromMillisecondsSinceEpoch(tsMillis)
        : DateTime.now();
    final resolvedDeviceId =
        f.stringOf(const ['device_id', 'deviceId', 'id', 'mac', 'uuid']) ??
            deviceId;
    return EdgeSensorReading(
      deviceId: resolvedDeviceId,
      siteTag: siteTag ??
          f.stringOf(const ['site', 'site_tag', 'siteTag', 'location']),
      channel: channel,
      edgeTimestamp: edgeTs,
      receivedAt: DateTime.now(),
      vibrationAmplitudeMm: f.numOf(const [
        'vib_mm',
        'vibrationAmplitudeMm',
        'vibration',
        'vib',
        'amplitude_mm',
        'amplitude',
        'amp_mm',
        'amp',
      ]),
      dominantFrequencyHz: f.numOf(const [
        'freq_hz',
        'dominantFrequencyHz',
        'frequency',
        'freq',
        'hz',
        'dominant_freq',
      ]),
      temperatureC: f.numOf(const [
        'temp_c',
        'temperatureC',
        'temperature',
        'temp',
        'celsius',
        't_c',
      ]),
      acousticDb: f.numOf(const [
        'db',
        'acoustic_db',
        'acousticDb',
        'acoustic',
        'sound',
        'spl',
        'sound_db',
      ]),
      signalQuality: f.numOf(const [
            'snr',
            'signal_quality',
            'signalQuality',
            'quality',
            'rssi_q',
          ]) ??
          1.0,
    );
  }

  /// Raw MQTT bayt qatordan dekoder — UTF-8 JSON deb tushuniladi.
  /// Xato JSON / bo'sh payload — `null` (silent fail, ilova crash bo'lmaydi).
  static EdgeSensorReading? tryDecodePayload(
    String deviceId,
    String channel,
    List<int> bytes, {
    String? siteTag,
  }) {
    if (bytes.isEmpty) return null;
    try {
      final text = utf8.decode(bytes, allowMalformed: true);
      final trimmed = text.trim();
      if (trimmed.isEmpty) return null;
      final decoded = jsonDecode(trimmed);
      // Top-level Map yoki List (ko'p qurilmalar List yuboradi)
      if (decoded is Map<String, dynamic>) {
        return EdgeSensorReading.fromJson(deviceId, channel, decoded,
            siteTag: siteTag);
      }
      if (decoded is List && decoded.isNotEmpty) {
        final first = decoded.first;
        if (first is Map<String, dynamic>) {
          return EdgeSensorReading.fromJson(deviceId, channel, first,
              siteTag: siteTag);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        if (siteTag != null) 'site_tag': siteTag,
        'channel': channel,
        'edge_ts': edgeTimestamp.toIso8601String(),
        'received_at': receivedAt.toIso8601String(),
        if (vibrationAmplitudeMm != null) 'vib_mm': vibrationAmplitudeMm,
        if (dominantFrequencyHz != null) 'freq_hz': dominantFrequencyHz,
        if (temperatureC != null) 'temp_c': temperatureC,
        if (acousticDb != null) 'db': acousticDb,
        'snr': signalQuality,
      };

  @override
  String toString() =>
      'EdgeSensorReading($deviceId/$channel @${edgeTimestamp.millisecondsSinceEpoch})';
}

/// **Sprint 16 — BYOD JSON helper.** Maydon nomlari aliaslari, case-insensitive
/// qidiruv, nested obyektlar, string→number parsing, no-throw fallback.
class _FlexJson {
  final Map<String, dynamic> root;
  _FlexJson(this.root);

  static const _nestedKeys = ['data', 'payload', 'msg', 'body', 'sensor'];
  static final _numericCleaner = RegExp(r'[^\d.\-eE+]');

  /// Maydon qiymatini bir nechta alias bo'yicha qidirib, sonni qaytaradi.
  /// String `"1.42"` ham, raw `1.42` ham qabul qilinadi.
  double? numOf(List<String> aliases) {
    for (final key in aliases) {
      final v = _lookup(root, key);
      if (v == null) continue;
      if (v is num) return v.toDouble();
      if (v is bool) return v ? 1.0 : 0.0;
      if (v is String) {
        final s = v.trim();
        if (s.isEmpty) continue;
        final parsed = double.tryParse(s);
        if (parsed != null) return parsed;
        // "1.42mm", "28.4 Hz", "47.2°C" — birliklarni tashlab yuboramiz
        final cleaned = s.replaceAll(_numericCleaner, '');
        final fallback = double.tryParse(cleaned);
        if (fallback != null) return fallback;
      }
    }
    return null;
  }

  int? intOf(List<String> aliases) => numOf(aliases)?.toInt();

  String? stringOf(List<String> aliases) {
    for (final key in aliases) {
      final v = _lookup(root, key);
      if (v == null) continue;
      if (v is String) return v.trim().isEmpty ? null : v.trim();
      return v.toString();
    }
    return null;
  }

  /// Case-insensitive + nested obyektlarda ham qidiradi.
  static dynamic _lookup(Map<String, dynamic> map, String key) {
    if (map.containsKey(key)) {
      final v = map[key];
      if (v != null) return v;
    }
    final lower = key.toLowerCase();
    for (final k in map.keys) {
      if (k.toLowerCase() == lower) {
        final v = map[k];
        if (v != null) return v;
      }
    }
    // Nested
    for (final nest in _nestedKeys) {
      final sub = map[nest];
      if (sub is Map<String, dynamic>) {
        final found = _lookup(sub, key);
        if (found != null) return found;
      }
    }
    return null;
  }
}
