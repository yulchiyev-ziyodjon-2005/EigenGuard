// 3D mesh modellari — Point Cloud dan triangulyatsiya orqali quriladi.

/// 3D verteks (x, y, z) + intensiveness (heatmap rangi uchun)
class MeshVertex {
  final double x;
  final double y;
  final double z;
  /// 0.0 (sovuq/normal) — 1.0 (qizg'in/kritik)
  final double intensity;
  const MeshVertex(this.x, this.y, this.z, {this.intensity = 0});
}

/// Bitta uchburchak — 3 ta MeshVertex
class MeshTriangle {
  final MeshVertex v0;
  final MeshVertex v1;
  final MeshVertex v2;
  const MeshTriangle(this.v0, this.v1, this.v2);

  /// Uchburchak markazidagi o'rtacha Z — painter algoritmi (z-sort) uchun
  double get centerZ => (v0.z + v1.z + v2.z) / 3.0;

  /// Uchburchak markazidagi o'rtacha intensity (heatmap)
  double get averageIntensity =>
      (v0.intensity + v1.intensity + v2.intensity) / 3.0;
}

/// 3D mesh — uchburchaklar to'plami + hot-spot zonalar
class Mesh3D {
  final List<MeshTriangle> triangles;
  /// Yuqori intensity (kritik) zonalar — alohida ko'rsatish uchun
  final List<MeshVertex> hotspots;

  const Mesh3D({
    required this.triangles,
    this.hotspots = const [],
  });

  bool get isEmpty => triangles.isEmpty;
  bool get isNotEmpty => triangles.isNotEmpty;

  /// Bo'sh mesh (boshlang'ich holat)
  factory Mesh3D.empty() => const Mesh3D(triangles: []);

  /// Mesh statistikasi (debug uchun)
  String get stats =>
      '${triangles.length} triangles · ${hotspots.length} hotspots';
}

/// Render rejimlari — DigitalTwin foydalanuvchi tanlaydi
enum MeshRenderMode {
  /// Solid — to'liq to'ldirilgan, normal-shaded
  solid,

  /// Wireframe — faqat qirralar
  wireframe,

  /// X-Ray — past alpha fill + edge glow
  xray,

  /// Heatmap — intensity bo'yicha rangli (cyan→red gradient)
  heatmap,
}

extension MeshRenderModeLabel on MeshRenderMode {
  String get label {
    switch (this) {
      case MeshRenderMode.solid:
        return 'SOLID';
      case MeshRenderMode.wireframe:
        return 'WIREFRAME';
      case MeshRenderMode.xray:
        return 'X-RAY';
      case MeshRenderMode.heatmap:
        return 'HEATMAP';
    }
  }
}
