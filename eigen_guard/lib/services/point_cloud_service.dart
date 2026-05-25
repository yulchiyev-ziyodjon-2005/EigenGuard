import 'dart:math';
import 'package:flutter/material.dart';
import '../models/mesh_3d.dart';
import '../utils/delaunay.dart';

class Point3D {
  double x;
  double y;
  double z;
  /// Tebranish kuchi (Heatmap rangi) — 0.0 (sovuq/normal) … 1.0 (qizg'in/kritik).
  /// TZ §3.4: aynan shu qiymat bo'yicha 3D maket ustida zonalar qizil ranglanadi.
  double intensity;
  Point3D(this.x, this.y, this.z, {this.intensity = 0.0});
}

/// Sanoat 100% On-Device AR Point Cloud Simulyatsiyasi.
/// TZ §3.2: YOLO Segmentation poligoni ichidagi nuqtalardan
/// 2.5D rel'yef (yarim shar) shaklida Point Cloud yig'iladi.
/// Tashqi Cloud API ulashni bartaraf qilib tizimning o'zida obyekt bulutini yaratadi.
class PointCloudService {
  static final PointCloudService _instance = PointCloudService._internal();
  factory PointCloudService() => _instance;
  PointCloudService._internal();

  final List<Point3D> _points = [];
  // Voxel → Point3D xaritasi. Set o'rniga Map ishlatilmoqda, chunki voxel
  // qaytadan urilganda eski Point3D ning intensity sini EMA bilan yangilaymiz
  // (TZ §3.4: bir zonada keyingi o'tishlarda yangilangan tebranish kuchini
  // saqlab qolish uchun).
  final Map<String, Point3D> _voxelGrid = {};
  bool _isScanning = false;

  // Intensity EMA aralashtirish koeffitsienti (yangi qiymat ulushi).
  static const double _intensityBlend = 0.3;
  // Pulse chegarasi — bu chegaradan yuqori nuqtalar miltillaydi.
  static const double pulseThreshold = 0.6;

  // Voxel Grid Downsampling rezolyutsiyasi (≈ 0.5 sm)
  static const double _voxelSize = 10.0;
  // Maksimal nuqtalar (RAM tejamkorligi)
  static const int _maxPoints = 8000;
  // Yarim shar gologramma "qavariqligi"ning bazaviy balandligi (Z)
  static const double _domeHeight = 100.0;

  List<Point3D> get points => _points;
  bool get isScanning => _isScanning;

  void startScanning() {
    _points.clear();
    _voxelGrid.clear();
    _isScanning = true;
  }

  void pauseScanning() => _isScanning = false;
  void resumeScanning() => _isScanning = true;
  void stopScanning() => _isScanning = false;

  void clear() {
    _points.clear();
    _voxelGrid.clear();
  }

  /// Kameradan olingan dx, dy (Optical Flow piksel siljishi) va YOLO segmentation
  /// poligoni asosida nuqtalar bulutiga yangi qatlam qo'shish.
  ///
  /// TZ §3.2 — polygon birinchi navbatda ishlatiladi (haqiqiy obyekt shakli).
  /// Agar YOLO faqat Bounding Box qaytarsa (segmentation yo'q), `fallbackBox` ishlatiladi.
  ///
  /// [vibrationIntensity] — TZ §3.4 Heatmap: kadrning hozirgi tebranish kuchi
  /// (0.0..1.0). Yangi qo'shilayotgan nuqtalarga shu qiymat yoziladi, mavjud
  /// voxelga qaytib urilsa EMA bilan aralashtiriladi.
  void processMovement(
    double dx,
    double dy,
    List<Offset>? polygons, {
    Rect? fallbackBox,
    double vibrationIntensity = 0.0,
  }) {
    if (!_isScanning) return;
    final intensity = vibrationIntensity.clamp(0.0, 1.0);

    // Polygon rejimi (asosiy — TZ §3.2)
    if (polygons != null && polygons.length >= 3) {
      _addPolygonPoints(polygons, intensity);
      return;
    }

    // Fallback — faqat Bounding Box (YOLO da segmentation bo'lmasa)
    if (fallbackBox != null && fallbackBox.width > 0 && fallbackBox.height > 0) {
      _addBoxPoints(fallbackBox, intensity);
    }
  }

  // ============================================================
  // POLIGON ASOSIDA NUQTA YIG'ISH (Ray-Casting + 2.5D Dome)
  // ============================================================
  void _addPolygonPoints(List<Offset> poly, double intensity) {
    final rng = Random();

    // 1) Poligonning bounding box (rejection sampling sohasi)
    double minX = poly.first.dx, maxX = poly.first.dx;
    double minY = poly.first.dy, maxY = poly.first.dy;
    for (final p in poly) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    final w = maxX - minX;
    final h = maxY - minY;
    if (w <= 0 || h <= 0) return;

    // 2) Centroid — vertex o'rtachasi (Z chuqurligi va lokal koordinatalar uchun)
    double cx = 0, cy = 0;
    for (final p in poly) {
      cx += p.dx;
      cy += p.dy;
    }
    cx /= poly.length;
    cy /= poly.length;

    // 3) Centroid'dan eng uzoq vertexgacha — Z normalizatsiyasi uchun radius
    double maxR = 0;
    for (final p in poly) {
      final ddx = p.dx - cx;
      final ddy = p.dy - cy;
      final r = sqrt(ddx * ddx + ddy * ddy);
      if (r > maxR) maxR = r;
    }
    if (maxR <= 0) return;

    // 4) Rejection sampling — har kadrda 3-8 ta poligon ICHIDAGI nuqta yig'amiz
    const int targetPoints = 6;
    const int maxAttempts = 60; // 10x rejection sabr (qiyshiq poligonlar uchun)
    int added = 0;
    int attempts = 0;

    while (added < targetPoints && attempts < maxAttempts) {
      attempts++;

      final px = minX + rng.nextDouble() * w;
      final py = minY + rng.nextDouble() * h;

      if (!_pointInPolygon(px, py, poly)) continue;

      // Lokal koordinatalar (centroid = origin)
      final localX = px - cx;
      final localY = py - cy;

      // Z chuqurligi — markazga yaqin = qabariqroq (yarim shar tenglamasi).
      // z = h * sqrt(1 - (r/R)^2)  →  markazda h, chetda 0.
      final r = sqrt(localX * localX + localY * localY);
      final normalized = (r / maxR).clamp(0.0, 1.0);
      final zBase = _domeHeight * sqrt(1.0 - normalized * normalized);
      final z = zBase + (rng.nextDouble() - 0.5) * 8.0; // realistic shovqin

      // Voxel Grid Downsampling — bu voxel allaqachon bandmi?
      final voxelKey = _voxelKey(localX, localY, z);
      final existing = _voxelGrid[voxelKey];
      if (existing != null) {
        // TZ §3.4 — kameralar shu zonaga qaytsa, intensity ni EMA bilan
        // yangilab boramiz (eski qiymatni butunlay o'chirmasdan, yangi
        // o'lchov bilan aralashtirib).
        existing.intensity =
            existing.intensity * (1.0 - _intensityBlend) +
            intensity * _intensityBlend;
        continue;
      }

      final p = Point3D(localX, localY, z, intensity: intensity);
      _points.add(p);
      _voxelGrid[voxelKey] = p;
      added++;

      _trimIfOversize();
    }
  }

  // ============================================================
  // FALLBACK: BOUNDING BOX ASOSIDA (eski mantiq, kompatibillik uchun)
  // ============================================================
  void _addBoxPoints(Rect roiBox, double intensity) {
    final rng = Random();
    final pointsToAdd = rng.nextInt(6) + 3;

    for (int i = 0; i < pointsToAdd; i++) {
      final rx = roiBox.left + rng.nextDouble() * roiBox.width;
      final ry = roiBox.top + rng.nextDouble() * roiBox.height;

      final distX = (rx - roiBox.center.dx).abs() / (roiBox.width / 2);
      final distY = (ry - roiBox.center.dy).abs() / (roiBox.height / 2);

      final zBase = _domeHeight * (1.0 - max(distX, distY));
      final z = zBase + (rng.nextDouble() - 0.5) * 15.0;

      final localX = rx - roiBox.center.dx;
      final localY = ry - roiBox.center.dy;

      final voxelKey = _voxelKey(localX, localY, z);
      final existing = _voxelGrid[voxelKey];
      if (existing != null) {
        existing.intensity =
            existing.intensity * (1.0 - _intensityBlend) +
            intensity * _intensityBlend;
        continue;
      }

      final p = Point3D(localX, localY, z, intensity: intensity);
      _points.add(p);
      _voxelGrid[voxelKey] = p;

      _trimIfOversize();
    }
  }

  // ============================================================
  // YORDAMCHI: Ray-Casting (Point-in-Polygon)
  // ============================================================
  /// W. Randolph Franklin algoritmi — O(n), konveks va konkav poligonlar uchun.
  bool _pointInPolygon(double x, double y, List<Offset> poly) {
    bool inside = false;
    final n = poly.length;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final xi = poly[i].dx;
      final yi = poly[i].dy;
      final xj = poly[j].dx;
      final yj = poly[j].dy;

      final intersects = ((yi > y) != (yj > y)) &&
          (x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi);
      if (intersects) inside = !inside;
    }
    return inside;
  }

  String _voxelKey(double x, double y, double z) {
    final vx = (x / _voxelSize).round();
    final vy = (y / _voxelSize).round();
    final vz = (z / _voxelSize).round();
    return '${vx}_${vy}_$vz';
  }

  void _trimIfOversize() {
    if (_points.length <= _maxPoints) return;
    final removed = _points.removeAt(0);
    _voxelGrid.remove(_voxelKey(removed.x, removed.y, removed.z));
  }

  // ============================================================
  // PHASE 6: 3D MESH RECONSTRUCTION (Delaunay + alpha-shape)
  // ============================================================

  /// Joriy point cloud dan 3D mesh quradi. Algoritm:
  ///   1. Nuqtalarni XY tekisligiga proyeksiya
  ///   2. Bowyer-Watson Delaunay triangulyatsiya
  ///   3. Alpha-shape filter — uzun "ko'prik" qirralarni olib tashlash
  ///   4. Z qiymatlari bilan 3D MeshTriangle ga qayta tiklash
  ///
  /// `alphaScale` — alpha threshold = avgSpacing × alphaScale. Default 4.0
  /// (4×o'rtacha nuqtalar oraliqi). Kichikroq = mayda fragmentlar, kattaroq =
  /// bog'liq mesh.
  Mesh3D buildMesh({double alphaScale = 4.0}) {
    if (_points.length < 3) return Mesh3D.empty();

    // 1) DPoint ro'yxati (XY proyeksiya, asl Point3D index'i bilan)
    final dPoints = <DPoint>[];
    for (int i = 0; i < _points.length; i++) {
      final p = _points[i];
      dPoints.add(DPoint(p.x, p.y, i));
    }

    // 2) Delaunay triangulyatsiya
    final triangles = Delaunay.triangulate(dPoints);
    if (triangles.isEmpty) return Mesh3D.empty();

    // 3) Alpha-shape — uzun qirralarni olib tashlash
    // O'rtacha nuqta oraliqi:
    //   density = n / area  →  spacing ≈ sqrt(1/density) = sqrt(area/n)
    double minX = double.infinity,
        minY = double.infinity,
        maxX = -double.infinity,
        maxY = -double.infinity;
    for (final p in _points) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
    final area = (maxX - minX) * (maxY - minY);
    final avgSpacing = area > 0 ? sqrt(area / _points.length) : 10.0;
    final alphaSq = pow(avgSpacing * alphaScale, 2.0).toDouble();

    final filtered = Delaunay.alphaFilter(triangles, alphaSq);

    // 4) MeshTriangle (3D verteks bilan)
    final meshTris = <MeshTriangle>[];
    for (final t in filtered) {
      final p0 = _points[t.a.index];
      final p1 = _points[t.b.index];
      final p2 = _points[t.c.index];
      meshTris.add(MeshTriangle(
        MeshVertex(p0.x, p0.y, p0.z, intensity: p0.intensity),
        MeshVertex(p1.x, p1.y, p1.z, intensity: p1.intensity),
        MeshVertex(p2.x, p2.y, p2.z, intensity: p2.intensity),
      ));
    }

    return Mesh3D(
      triangles: meshTris,
      hotspots: getCriticalHotspots()
          .map((p) =>
              MeshVertex(p.x, p.y, p.z, intensity: p.intensity))
          .toList(),
    );
  }

  /// Eng yuqori intensity zonalarni (kritik nuqtalarni) ajratib oladi.
  /// Top-N tanlash, lekin o'zaro `minSpacing` masofada bo'lishi shart —
  /// bir-biriga yopishgan nuqtalar bitta hot-spot deb hisoblanadi.
  ///
  /// `minIntensity` — bu chegaradan past bo'lganlari hot-spot emas.
  List<Point3D> getCriticalHotspots({
    int topN = 5,
    double minIntensity = 0.5,
    double minSpacing = 30.0,
  }) {
    if (_points.isEmpty) return const [];
    // Intensity bo'yicha kamayuvchi tartibda
    final sorted = List<Point3D>.from(_points)
      ..sort((a, b) => b.intensity.compareTo(a.intensity));

    final result = <Point3D>[];
    final minSpaceSq = minSpacing * minSpacing;
    for (final p in sorted) {
      if (p.intensity < minIntensity) break;
      // Avval qabul qilinganlardan birortasiga juda yaqinmi?
      bool tooClose = false;
      for (final existing in result) {
        final dx = p.x - existing.x;
        final dy = p.y - existing.y;
        final dz = p.z - existing.z;
        if (dx * dx + dy * dy + dz * dz < minSpaceSq) {
          tooClose = true;
          break;
        }
      }
      if (!tooClose) {
        result.add(p);
        if (result.length >= topN) break;
      }
    }
    return result;
  }
}
