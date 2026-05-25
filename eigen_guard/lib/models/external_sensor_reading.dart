import 'dart:typed_data';

/// Tashqi BLE sensoridan kelgan bitta o'qish.
///
/// Yaratilish stsenariysi: BLE characteristic'dan kelgan byte buffer'i
/// `BleProtocolDecoder` orqali parse qilinadi. Agar decoder muvaffaqiyatsiz
/// bo'lsa, faqat raw hex va xato saqlanadi.
class ExternalSensorReading {
  final DateTime timestamp;
  /// Aktselerometr (m/s²) — agar decoder qo'llab quvvatlasa
  final double? accelX;
  final double? accelY;
  final double? accelZ;
  /// Sensor tomonidan yuborilgan raw bayt qator (hex display uchun)
  final Uint8List rawBytes;
  /// Decoder xatosi (agar protokol mos kelmasa)
  final String? parseError;

  const ExternalSensorReading({
    required this.timestamp,
    this.accelX,
    this.accelY,
    this.accelZ,
    required this.rawBytes,
    this.parseError,
  });

  /// 3 o'q magnitudasi (m/s²) — sensor fusion uchun
  double? get magnitude {
    if (accelX == null || accelY == null || accelZ == null) return null;
    return _sqrt(accelX! * accelX! + accelY! * accelY! + accelZ! * accelZ!);
  }

  /// Hex display: "A1 B2 C3 D4 E5 F6"
  String get hexString {
    return rawBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
  }

  bool get hasAccel =>
      accelX != null && accelY != null && accelZ != null;

  static double _sqrt(double x) => x <= 0 ? 0 : _newtonSqrt(x);
  static double _newtonSqrt(double x) {
    double r = x;
    for (int i = 0; i < 6; i++) {
      r = 0.5 * (r + x / r);
    }
    return r;
  }
}

/// BLE characteristic'idan kelgan baytlarni `ExternalSensorReading` ga
/// aylantiruvchi protokol decoder strategiyasi.
abstract class BleProtocolDecoder {
  String get name;
  String get description;
  ExternalSensorReading decode(Uint8List bytes);
}

/// Eng keng tarqalgan: 6 bayt = Int16 LE, X, Y, Z (m/s² yoki g, sensitivity bilan)
class Int16LeXyzAccelDecoder implements BleProtocolDecoder {
  /// Sensitivity (LSB → m/s²). Default: ±2g LSM6DSO standart = 0.061 mg/LSB
  /// (0.000599 m/s² per LSB). Foydalanuvchi sozlaydi.
  final double scaleToMs2;
  Int16LeXyzAccelDecoder({this.scaleToMs2 = 0.000599 * 9.80665});

  @override
  String get name => 'Int16 LE X/Y/Z (accelerometer)';

  @override
  String get description =>
      '6 bayt = signed Int16 LE × 3 o\'q · ±2g shkala (LSM6DSO va o\'xshashlar)';

  @override
  ExternalSensorReading decode(Uint8List bytes) {
    if (bytes.length < 6) {
      return ExternalSensorReading(
        timestamp: DateTime.now(),
        rawBytes: bytes,
        parseError: '6 bayt kerak, lekin ${bytes.length} keldi',
      );
    }
    final bd = ByteData.sublistView(bytes, 0, 6);
    final x = bd.getInt16(0, Endian.little) * scaleToMs2;
    final y = bd.getInt16(2, Endian.little) * scaleToMs2;
    final z = bd.getInt16(4, Endian.little) * scaleToMs2;
    return ExternalSensorReading(
      timestamp: DateTime.now(),
      accelX: x,
      accelY: y,
      accelZ: z,
      rawBytes: bytes,
    );
  }
}

/// 12 bayt = Float32 LE × 3 o'q (DIY Arduino+nRF, ESP32 sensorlar)
class Float32LeXyzAccelDecoder implements BleProtocolDecoder {
  @override
  String get name => 'Float32 LE X/Y/Z (accelerometer)';

  @override
  String get description =>
      '12 bayt = IEEE 754 float32 LE × 3 o\'q (m/s²) — DIY ESP32/nRF';

  @override
  ExternalSensorReading decode(Uint8List bytes) {
    if (bytes.length < 12) {
      return ExternalSensorReading(
        timestamp: DateTime.now(),
        rawBytes: bytes,
        parseError: '12 bayt kerak, lekin ${bytes.length} keldi',
      );
    }
    final bd = ByteData.sublistView(bytes, 0, 12);
    return ExternalSensorReading(
      timestamp: DateTime.now(),
      accelX: bd.getFloat32(0, Endian.little),
      accelY: bd.getFloat32(4, Endian.little),
      accelZ: bd.getFloat32(8, Endian.little),
      rawBytes: bytes,
    );
  }
}

/// Hech qanday parsing — faqat raw hex saqlaydi. Foydalanuvchi notanish
/// qurilma bilan ulanib, baytlar oqimini ko'rishni xohlasa.
class RawHexDecoder implements BleProtocolDecoder {
  @override
  String get name => 'Raw hex (parsing yo\'q)';

  @override
  String get description =>
      'Hech qanday tahlilsiz, faqat baytlar oqimi ko\'rsatiladi';

  @override
  ExternalSensorReading decode(Uint8List bytes) {
    return ExternalSensorReading(
      timestamp: DateTime.now(),
      rawBytes: bytes,
    );
  }
}

/// Barcha mavjud decoder'lar — UI da tanlash uchun
class BleProtocolDecoders {
  BleProtocolDecoders._();
  static final List<BleProtocolDecoder> all = [
    Int16LeXyzAccelDecoder(),
    Float32LeXyzAccelDecoder(),
    RawHexDecoder(),
  ];
}
