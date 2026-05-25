import 'dart:math' as math;

/// EigenGuard — Bowyer-Watson Delaunay Triangulation (2D)
///
/// Point Cloud (3D nuqtalar buluti) → 2.5D mesh:
///   1. Nuqtalarni XY tekisligiga proyeksiya qilamiz (Z saqlanadi).
///   2. Bu kutubxona XY tekislikda Delaunay triangulyatsiya qiladi.
///   3. Olingan uchburchaklar XY indeks asosida — Z qiymatlari qayta
///      qo'shilib 3D mesh (Mesh3D) tuziladi.
///
/// **Algoritm:** Bowyer-Watson (O(n^1.5) average). 8000 nuqta ≈ 50-100ms
/// telefon CPU da — har 1 sek mesh qayta qurish maqbul.
///
/// **Alpha-shape filter:** uchburchakdagi eng uzun qirra `alphaSquared` dan
/// uzun bo'lsa, u olib tashlanadi. Bu spurious "ko'prik" uchburchaklarni
/// kesib, obyektning haqiqiy chegarasini saqlaydi.
class Delaunay {
  Delaunay._();

  /// Asosiy entry point — nuqtalar ro'yxatidan Delaunay triangulyatsiya
  static List<DTriangle> triangulate(List<DPoint> points) {
    final n = points.length;
    if (n < 3) return const [];

    // Super-triangle — barcha nuqtalarni o'z ichiga oluvchi katta uchburchak
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final p in points) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
    final dx = maxX - minX;
    final dy = maxY - minY;
    final deltaMax = math.max(dx, dy) * 10.0 + 1.0;
    final midX = (minX + maxX) / 2.0;
    final midY = (minY + maxY) / 2.0;

    // Super-triangle vertekslari — manfiy indekslar bilan belgilanadi
    final superA = DPoint(midX - 20 * deltaMax, midY - deltaMax, -1);
    final superB = DPoint(midX, midY + 20 * deltaMax, -2);
    final superC = DPoint(midX + 20 * deltaMax, midY - deltaMax, -3);

    final triangles = <DTriangle>[DTriangle(superA, superB, superC)];

    for (final p in points) {
      // Bu nuqta sircumcircle ichida qoladigan barcha "yomon" uchburchaklar
      final badTriangles = <DTriangle>[];
      for (final t in triangles) {
        if (t.containsInCircumcircle(p)) {
          badTriangles.add(t);
        }
      }
      if (badTriangles.isEmpty) continue;

      // Yomon uchburchaklar chegarasidagi qirralarni topish
      // (faqat 1 marta uchragan qirralar — chegara hisoblanadi)
      final polygon = <DEdge>[];
      for (int i = 0; i < badTriangles.length; i++) {
        final t = badTriangles[i];
        final edges = [
          DEdge(t.a, t.b),
          DEdge(t.b, t.c),
          DEdge(t.c, t.a),
        ];
        for (final e in edges) {
          bool shared = false;
          for (int j = 0; j < badTriangles.length; j++) {
            if (i == j) continue;
            if (badTriangles[j].hasEdge(e)) {
              shared = true;
              break;
            }
          }
          if (!shared) polygon.add(e);
        }
      }

      // Yomon uchburchaklarni olib tashlash
      triangles.removeWhere(badTriangles.contains);

      // Chegara qirralaridan yangi uchburchaklar quramiz
      for (final e in polygon) {
        triangles.add(DTriangle(e.a, e.b, p));
      }
    }

    // Super-triangle bilan bog'liq uchburchaklarni olib tashlash
    triangles.removeWhere((t) =>
        t.a.index < 0 || t.b.index < 0 || t.c.index < 0);

    return triangles;
  }

  /// Alpha-shape filter — uchburchakdagi eng uzun qirra `maxEdge` dan
  /// uzun bo'lsa, uchburchak olib tashlanadi.
  ///
  /// `maxEdge` — masofa (XY tekislikdagi), `maxEdgeSquared` ichida bo'ladi.
  /// Bu kvadrat masofa — sqrt() bilan vaqt yutmaslik uchun.
  static List<DTriangle> alphaFilter(
    List<DTriangle> triangles,
    double maxEdgeSquared,
  ) {
    final result = <DTriangle>[];
    for (final t in triangles) {
      final dab = _distSquared(t.a, t.b);
      if (dab > maxEdgeSquared) continue;
      final dbc = _distSquared(t.b, t.c);
      if (dbc > maxEdgeSquared) continue;
      final dca = _distSquared(t.c, t.a);
      if (dca > maxEdgeSquared) continue;
      result.add(t);
    }
    return result;
  }

  static double _distSquared(DPoint a, DPoint b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return dx * dx + dy * dy;
  }
}

/// 2D nuqta — Delaunay uchun. `index` original ro'yxatdagi tartib raqami,
/// manfiy qiymat — super-triangle vertekslari uchun.
class DPoint {
  final double x;
  final double y;
  final int index;
  const DPoint(this.x, this.y, this.index);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DPoint &&
          // Index orqali identifikatsiya — to'g'ri va tez
          index == other.index);

  @override
  int get hashCode => index.hashCode;
}

/// Yo'naltirilmagan qirra — equality `Edge(a,b) == Edge(b,a)`.
class DEdge {
  final DPoint a;
  final DPoint b;
  const DEdge(this.a, this.b);

  @override
  bool operator ==(Object other) {
    if (other is! DEdge) return false;
    return (a.index == other.a.index && b.index == other.b.index) ||
        (a.index == other.b.index && b.index == other.a.index);
  }

  @override
  int get hashCode {
    final i = a.index;
    final j = b.index;
    return i < j ? Object.hash(i, j) : Object.hash(j, i);
  }
}

/// Delaunay uchburchagi — circumcircle markazi va radiusi precomputed.
class DTriangle {
  final DPoint a;
  final DPoint b;
  final DPoint c;
  late final double _ccX;
  late final double _ccY;
  late final double _ccRadiusSq;

  DTriangle(this.a, this.b, this.c) {
    final ax = a.x, ay = a.y;
    final bx = b.x, by = b.y;
    final cx = c.x, cy = c.y;
    final d = 2.0 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by));
    if (d.abs() < 1e-12) {
      // Kollinear — circumcircle tutib bo'lmaydi → infinity
      _ccX = 0;
      _ccY = 0;
      _ccRadiusSq = double.infinity;
      return;
    }
    final a2 = ax * ax + ay * ay;
    final b2 = bx * bx + by * by;
    final c2 = cx * cx + cy * cy;
    _ccX = (a2 * (by - cy) + b2 * (cy - ay) + c2 * (ay - by)) / d;
    _ccY = (a2 * (cx - bx) + b2 * (ax - cx) + c2 * (bx - ax)) / d;
    final dxr = ax - _ccX;
    final dyr = ay - _ccY;
    _ccRadiusSq = dxr * dxr + dyr * dyr;
  }

  /// Nuqta circumcircle ichidami (Delaunay shartining buzilishi)
  bool containsInCircumcircle(DPoint p) {
    final dx = p.x - _ccX;
    final dy = p.y - _ccY;
    return (dx * dx + dy * dy) < _ccRadiusSq;
  }

  /// Berilgan qirra shu uchburchakda bormi (3 ta qirra: a-b, b-c, c-a)
  bool hasEdge(DEdge e) {
    final ea = e.a.index;
    final eb = e.b.index;
    final ai = a.index, bi = b.index, ci = c.index;
    // a-b qirrasi
    if ((ai == ea && bi == eb) || (ai == eb && bi == ea)) return true;
    // b-c qirrasi
    if ((bi == ea && ci == eb) || (bi == eb && ci == ea)) return true;
    // c-a qirrasi
    if ((ci == ea && ai == eb) || (ci == eb && ai == ea)) return true;
    return false;
  }
}
