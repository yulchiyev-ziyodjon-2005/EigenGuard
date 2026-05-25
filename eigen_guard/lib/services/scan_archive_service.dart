import 'package:flutter/foundation.dart';
import '../services/database_service.dart';
import '../services/point_cloud_service.dart';

/// EigenGuard — Point Cloud arxivi (SQLite blob).
///
/// Har bir 3D skan tugagach point cloud Float32 packed BLOB sifatida
/// `scans` jadvalga yoziladi. Tarix ekranida sessiya tanlanganda u
/// `PointCloudService` ga qayta tiklanadi va DigitalTwin'da ko'rinadi.
///
/// **Format:** har bir nuqta = 4 × Float32 (x, y, z, intensity) = 16 bayt.
/// 1000 nuqta = 16 KB. 8000 nuqta (max) = 128 KB — SQLite uchun OK.
class ScanArchiveService {
  static final ScanArchiveService _instance = ScanArchiveService._internal();
  factory ScanArchiveService() => _instance;
  ScanArchiveService._internal();

  final DatabaseService _db = DatabaseService();

  /// Point cloud ni measurement bilan bog'lab DB ga saqlash.
  /// Avval shu measurement uchun mavjud bo'lsa, almashtirib qo'yiladi.
  /// Sprint 15 — `deviceId`/`source` opsional: Edge node yoki fused skan uchun.
  Future<int> savePointCloud(
    int measurementId,
    List<Point3D> points, {
    String? deviceId,
    String source = 'mobile',
  }) async {
    if (points.isEmpty) return 0;

    // Float32 packed buffer — har nuqta 16 bayt
    final f32 = Float32List(points.length * 4);
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final base = i * 4;
      f32[base] = p.x;
      f32[base + 1] = p.y;
      f32[base + 2] = p.z;
      f32[base + 3] = p.intensity;
    }
    final blob = f32.buffer.asUint8List(f32.offsetInBytes, f32.lengthInBytes);

    final db = await _db.database;
    // Eski yozuvni o'chirish (1 measurement = 1 point cloud)
    await db.delete('scans',
        where: 'measurement_id = ?', whereArgs: [measurementId]);
    return await db.insert('scans', {
      'measurement_id': measurementId,
      'points_blob': blob,
      'point_count': points.length,
      'device_id': deviceId,
      'source': source,
      'sync_status': 'pending',
    });
  }

  /// DB dan point cloud o'qish — measurement ID bo'yicha
  Future<List<Point3D>> loadPointCloud(int measurementId) async {
    try {
      final db = await _db.database;
      final rows = await db.query(
        'scans',
        where: 'measurement_id = ?',
        whereArgs: [measurementId],
        limit: 1,
      );
      if (rows.isEmpty) return const [];
      final blob = rows.first['points_blob'] as Uint8List;
      final count = rows.first['point_count'] as int;
      if (blob.lengthInBytes < count * 16) return const [];

      final f32 =
          blob.buffer.asFloat32List(blob.offsetInBytes, blob.lengthInBytes ~/ 4);
      final pts = <Point3D>[];
      for (int i = 0; i < count; i++) {
        final base = i * 4;
        pts.add(Point3D(
          f32[base].toDouble(),
          f32[base + 1].toDouble(),
          f32[base + 2].toDouble(),
          intensity: f32[base + 3].toDouble(),
        ));
      }
      return pts;
    } catch (e) {
      debugPrint('[ScanArchive] o\'qishda xato: $e');
      return const [];
    }
  }

  /// Saqlangan point cloud larni `PointCloudService` ga to'g'ridan-to'g'ri
  /// yuklash — Tarixdan tanlanganda DigitalTwin ko'rsata olishi uchun.
  Future<bool> restoreToPointCloudService(int measurementId) async {
    final pts = await loadPointCloud(measurementId);
    if (pts.isEmpty) return false;
    final pc = PointCloudService();
    pc.clear();
    for (final p in pts) {
      pc.points.add(p); // _voxelGrid bo'sh — re-trim ishlatmaymiz
    }
    return true;
  }

  /// Saqlangan sessiyalar soni
  Future<int> getCount() async {
    final db = await _db.database;
    final r = await db
        .rawQuery('SELECT COUNT(*) as c FROM scans');
    return (r.first['c'] as int?) ?? 0;
  }

  /// O'chirish (deleteMeasurement orqali avtomatik CASCADE qiladi)
  Future<void> delete(int measurementId) async {
    final db = await _db.database;
    await db
        .delete('scans', where: 'measurement_id = ?', whereArgs: [measurementId]);
  }
}
