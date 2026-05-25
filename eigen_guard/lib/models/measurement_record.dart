import 'dart:typed_data';

/// Sprint 15 — B2G ekotizimi: yozuv qayerdan kelganini belgilaydi
enum MeasurementSource {
  mobile,   // Faqat Flutter (kamera + telefon datchiklari)
  edge,     // Faqat ESP32 IoT node (MPU6050 + MLX90614 + akustik)
  fused;    // Kamera + Edge konsensus (SensorFusionArbiter)

  String get wireName => name;
  static MeasurementSource fromWire(String? s) {
    switch (s) {
      case 'edge':
        return MeasurementSource.edge;
      case 'fused':
        return MeasurementSource.fused;
      default:
        return MeasurementSource.mobile;
    }
  }
}

/// Sprint 15 — Nexus backend sync holati
enum SyncStatus {
  pending,  // Hali yuborilmagan
  synced,   // Nexus tomonidan tasdiqlangan
  failed;   // Qayta urinish kerak

  String get wireName => name;
  static SyncStatus fromWire(String? s) {
    switch (s) {
      case 'synced':
        return SyncStatus.synced;
      case 'failed':
        return SyncStatus.failed;
      default:
        return SyncStatus.pending;
    }
  }
}

/// MeasurementRecord — Bitta monitoring sessiyasi ma'lumotlari
class MeasurementRecord {
  final int? id;
  final DateTime timestamp;
  final double riskPercent;
  final double frequency;
  final double amplitude;
  final double splineError;
  final int frameCount;
  final int durationSeconds;
  final String riskLevel; // LOW / MEDIUM / HIGH / CRITICAL
  final String? objectLabel;
  // Phase 1 — material
  final String? materialId;
  // Phase 3 — geo-tag + magnetometer
  final double? latitude;
  final double? longitude;
  final double? locationAccuracyM;
  final double? magneticFieldUt; // joriy magnit maydon kuchi
  final bool? magneticAnomaly; // anomaliya aniqlanganmi (ferrous)
  // Phase 7 — to'liq tarix: real-time bufferlar serialized
  /// Amplituda time-series (mm) — Float64 LE bayt qator
  final Uint8List? amplitudeSeriesBlob;
  /// FFT spektri snapshot — Float64 LE bayt qator
  final Uint8List? fftSpectrumBlob;
  /// FFT sample rate (Hz) — spektrni qayta tiklash uchun
  final double? fftSampleRate;
  /// §6.4 — Parabolik bashorat koeffitsiyentlari (y = a + b·t + c·t²)
  final double? predictionA;
  final double? predictionB;
  final double? predictionC;
  /// Kritikgacha qolgan vaqt (soat) — saqlash paytidagi qiymat
  final double? hoursToCritical;
  /// Hot-spotlar — JSON: [{x,y,z,intensity}, ...]
  final String? hotspotsJson;
  // Sprint 15 — B2G ekotizimi
  /// Bog'langan Edge qurilma identifikatori (ESP32 MAC yoki UUID).
  /// `null` — yozuv faqat mobil app dan.
  final String? deviceId;
  /// Yozuv manbasi (mobile/edge/fused). Default: mobile.
  final MeasurementSource source;
  /// Nexus backend sync holati. Default: pending.
  final SyncStatus syncStatus;
  /// Nexus backend tomonidan berilgan ID (sync paytida to'ldiriladi).
  final String? nexusId;
  /// Fusion arbiter ishonch foizi (0.0..1.0) — faqat `fused` manba uchun.
  final double? fusionConfidence;

  const MeasurementRecord({
    this.id,
    required this.timestamp,
    required this.riskPercent,
    required this.frequency,
    required this.amplitude,
    required this.splineError,
    required this.frameCount,
    required this.durationSeconds,
    required this.riskLevel,
    this.objectLabel,
    this.materialId,
    this.latitude,
    this.longitude,
    this.locationAccuracyM,
    this.magneticFieldUt,
    this.magneticAnomaly,
    this.amplitudeSeriesBlob,
    this.fftSpectrumBlob,
    this.fftSampleRate,
    this.predictionA,
    this.predictionB,
    this.predictionC,
    this.hoursToCritical,
    this.hotspotsJson,
    this.deviceId,
    this.source = MeasurementSource.mobile,
    this.syncStatus = SyncStatus.pending,
    this.nexusId,
    this.fusionConfidence,
  });

  /// Bayt qatordan amplituda time-series ni Float64 ro'yxatga qaytarish
  List<double>? get amplitudeSeries {
    final b = amplitudeSeriesBlob;
    if (b == null || b.isEmpty) return null;
    final view = b.buffer.asFloat64List(b.offsetInBytes, b.lengthInBytes ~/ 8);
    return List<double>.from(view);
  }

  /// Bayt qatordan FFT spektrini Float64 ro'yxatga qaytarish
  List<double>? get fftSpectrum {
    final b = fftSpectrumBlob;
    if (b == null || b.isEmpty) return null;
    final view = b.buffer.asFloat64List(b.offsetInBytes, b.lengthInBytes ~/ 8);
    return List<double>.from(view);
  }

  /// Float64List → Uint8List (LE)
  static Uint8List float64ListToBytes(List<double> values) {
    final f64 = Float64List.fromList(values);
    return f64.buffer.asUint8List(f64.offsetInBytes, f64.lengthInBytes);
  }

  /// Xavf darajasini hisoblash
  static String calculateRiskLevel(double riskPercent) {
    if (riskPercent < 25) return 'LOW';
    if (riskPercent < 50) return 'MEDIUM';
    if (riskPercent < 75) return 'HIGH';
    return 'CRITICAL';
  }

  /// SQLite uchun Map ga aylantirish
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'timestamp': timestamp.toIso8601String(),
      'risk_percent': riskPercent,
      'frequency': frequency,
      'amplitude': amplitude,
      'spline_error': splineError,
      'frame_count': frameCount,
      'duration_seconds': durationSeconds,
      'risk_level': riskLevel,
      'object_label': objectLabel,
      'material_id': materialId,
      'latitude': latitude,
      'longitude': longitude,
      'location_accuracy_m': locationAccuracyM,
      'magnetic_field_ut': magneticFieldUt,
      'magnetic_anomaly': magneticAnomaly == null
          ? null
          : (magneticAnomaly! ? 1 : 0),
      'amplitude_series': amplitudeSeriesBlob,
      'fft_spectrum': fftSpectrumBlob,
      'fft_sample_rate': fftSampleRate,
      'prediction_a': predictionA,
      'prediction_b': predictionB,
      'prediction_c': predictionC,
      'hours_to_critical': hoursToCritical,
      'hotspots_json': hotspotsJson,
      'device_id': deviceId,
      'source': source.wireName,
      'sync_status': syncStatus.wireName,
      'nexus_id': nexusId,
      'fusion_confidence': fusionConfidence,
    };
  }

  /// SQLite Map dan yaratish
  factory MeasurementRecord.fromMap(Map<String, dynamic> map) {
    return MeasurementRecord(
      id: map['id'] as int?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      riskPercent: (map['risk_percent'] as num).toDouble(),
      frequency: (map['frequency'] as num).toDouble(),
      amplitude: (map['amplitude'] as num).toDouble(),
      splineError: (map['spline_error'] as num).toDouble(),
      frameCount: map['frame_count'] as int,
      durationSeconds: map['duration_seconds'] as int,
      riskLevel: map['risk_level'] as String,
      objectLabel: map['object_label'] as String?,
      materialId: map['material_id'] as String?,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      locationAccuracyM: (map['location_accuracy_m'] as num?)?.toDouble(),
      magneticFieldUt: (map['magnetic_field_ut'] as num?)?.toDouble(),
      magneticAnomaly: map['magnetic_anomaly'] == null
          ? null
          : ((map['magnetic_anomaly'] as int) == 1),
      amplitudeSeriesBlob: map['amplitude_series'] as Uint8List?,
      fftSpectrumBlob: map['fft_spectrum'] as Uint8List?,
      fftSampleRate: (map['fft_sample_rate'] as num?)?.toDouble(),
      predictionA: (map['prediction_a'] as num?)?.toDouble(),
      predictionB: (map['prediction_b'] as num?)?.toDouble(),
      predictionC: (map['prediction_c'] as num?)?.toDouble(),
      hoursToCritical: (map['hours_to_critical'] as num?)?.toDouble(),
      hotspotsJson: map['hotspots_json'] as String?,
      deviceId: map['device_id'] as String?,
      source: MeasurementSource.fromWire(map['source'] as String?),
      syncStatus: SyncStatus.fromWire(map['sync_status'] as String?),
      nexusId: map['nexus_id'] as String?,
      fusionConfidence: (map['fusion_confidence'] as num?)?.toDouble(),
    );
  }

  /// Matnli ko'rinish
  String get formattedTimestamp {
    final d = timestamp;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }
}
