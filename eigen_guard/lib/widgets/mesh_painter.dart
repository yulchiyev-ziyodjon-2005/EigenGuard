import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../models/mesh_3d.dart';

/// EigenGuard — Universal 3D Mesh Painter.
///
/// **4 render rejim:**
///   • SOLID     — to'liq to'ldirilgan, normal-shaded
///   • WIREFRAME — faqat qirralar (X-Ray sketch ko'rinishi)
///   • X-RAY     — past alpha to'ldirish + edge glow (rasmdagi holografik)
///   • HEATMAP   — intensity bo'yicha cyan→red gradient
///
/// **Painter algoritmi (z-sort):** uchburchaklar Z bo'yicha kamayuvchi
/// tartibda chiziladi — uzoqdagi avval, yaqindagi keyin (back-to-front).
///
/// **Hot-spot:** alohida glowing sferalar bilan ko'rsatiladi (qizil, pulsing).
///
/// **Material rangi** — base color sifatida (material.color) ishlatiladi,
/// intensity bilan modulyatsiya qilinadi.
class MeshPainter extends CustomPainter {
  final Mesh3D mesh;
  final MeshRenderMode mode;
  final Color baseColor;
  /// X o'qi atrofida aylanish (radian)
  final double rotationX;
  /// Y o'qi atrofida aylanish (radian)
  final double rotationY;
  /// Masshtab (zoom)
  final double scale;
  /// Hot-spot pulse animatsiyasi qiymati (0.0..1.0)
  final double hotspotPulse;

  MeshPainter({
    required this.mesh,
    required this.mode,
    required this.baseColor,
    this.rotationX = 0,
    this.rotationY = 0,
    this.scale = 1.0,
    this.hotspotPulse = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (mesh.isEmpty) return;

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Aylanish matritsa elementlari (pre-compute)
    final cosX = math.cos(rotationX);
    final sinX = math.sin(rotationX);
    final cosY = math.cos(rotationY);
    final sinY = math.sin(rotationY);

    // Verteksni 3D dan ekran koordinatasiga proyeksiyalash
    Offset project3D(MeshVertex v, [double? outZ]) {
      // Y atrofida aylanish
      double xr = v.x * cosY - v.z * sinY;
      double zr = v.x * sinY + v.z * cosY;
      // X atrofida aylanish
      double yr = v.y * cosX - zr * sinX;
      double zr2 = v.y * sinX + zr * cosX;
      // Perspektiv proyeksiya (z=300 oddiy)
      const camDist = 300.0;
      double persp = camDist / (camDist + zr2);
      if (persp < 0.05) persp = 0.05;
      return Offset(cx + xr * scale * persp, cy + yr * scale * persp);
    }

    // Z chuqurligini hisoblash (sort uchun) — faqat Z komponentasi kerak
    double depthOf(MeshVertex v) {
      final zr = v.x * sinY + v.z * cosY;
      return v.y * sinX + zr * cosX;
    }

    // Painter algoritmi — uchburchaklarni Z bo'yicha sortlash
    final indices = List<int>.generate(mesh.triangles.length, (i) => i);
    final depths = mesh.triangles.map((t) {
      return (depthOf(t.v0) + depthOf(t.v1) + depthOf(t.v2)) / 3.0;
    }).toList();
    indices.sort((a, b) => depths[a].compareTo(depths[b]));

    // Uchburchaklarni chizish
    for (final i in indices) {
      final t = mesh.triangles[i];
      final p0 = project3D(t.v0);
      final p1 = project3D(t.v1);
      final p2 = project3D(t.v2);
      _drawTriangle(canvas, t, p0, p1, p2);
    }

    // Hot-spot lar — eng tepada
    for (final hs in mesh.hotspots) {
      _drawHotspot(canvas, hs, project3D(hs));
    }
  }

  void _drawTriangle(
    Canvas canvas,
    MeshTriangle t,
    Offset p0,
    Offset p1,
    Offset p2,
  ) {
    final path = Path()
      ..moveTo(p0.dx, p0.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();

    final intensity = t.averageIntensity;
    final triColor = _colorForTriangle(intensity);

    switch (mode) {
      case MeshRenderMode.solid:
        // Normal-shaded fill
        final fillPaint = Paint()
          ..color = triColor
          ..style = PaintingStyle.fill;
        canvas.drawPath(path, fillPaint);
        // Edge ozgina ko'rinish
        final edgePaint = Paint()
          ..color = Colors.black.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5;
        canvas.drawPath(path, edgePaint);
        break;

      case MeshRenderMode.wireframe:
        final edgePaint = Paint()
          ..color = triColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        canvas.drawPath(path, edgePaint);
        break;

      case MeshRenderMode.xray:
        // Past alpha fill
        final fillPaint = Paint()
          ..color = triColor.withValues(alpha: 0.12)
          ..style = PaintingStyle.fill;
        canvas.drawPath(path, fillPaint);
        // Glow edge
        final glowPaint = Paint()
          ..color = triColor.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.0);
        canvas.drawPath(path, glowPaint);
        // Sharp edge
        final edgePaint = Paint()
          ..color = triColor.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5;
        canvas.drawPath(path, edgePaint);
        break;

      case MeshRenderMode.heatmap:
        final fillPaint = Paint()
          ..color = _heatmapColor(intensity)
          ..style = PaintingStyle.fill;
        canvas.drawPath(path, fillPaint);
        // Yaqin sezilarli edge
        final edgePaint = Paint()
          ..color = Colors.black.withValues(alpha: 0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5;
        canvas.drawPath(path, edgePaint);
        break;
    }
  }

  /// Uchburchak rangi: material base color + intensity bilan modulyatsiya
  Color _colorForTriangle(double intensity) {
    if (mode == MeshRenderMode.heatmap) {
      return _heatmapColor(intensity);
    }
    // Solid / Wireframe / X-Ray uchun: base color
    // Yuqori intensity → qizil tomon shift
    if (intensity > 0.5) {
      final t = (intensity - 0.5) * 2.0; // 0..1
      return Color.lerp(baseColor, AppTheme.danger, t) ?? baseColor;
    }
    return baseColor;
  }

  /// HSV gradient — cyan(180°) → green(120°) → yellow(60°) → red(0°)
  static Color _heatmapColor(double intensity) {
    final i = intensity.clamp(0.0, 1.0);
    final hue = 180.0 - 180.0 * i;
    return HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
  }

  /// Hot-spot — qizil glowing sfera, pulse animatsiyasi bilan
  void _drawHotspot(Canvas canvas, MeshVertex hs, Offset center) {
    final pulseRadius = 14.0 + hotspotPulse * 8.0;
    final glowPaint = Paint()
      ..color = AppTheme.danger.withValues(alpha: 0.35 + 0.25 * hotspotPulse)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(center, pulseRadius, glowPaint);

    final corePaint = Paint()
      ..color = AppTheme.danger
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 5.0, corePaint);

    final ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, 5.0, ringPaint);
  }

  @override
  bool shouldRepaint(covariant MeshPainter oldDelegate) =>
      oldDelegate.mesh != mesh ||
      oldDelegate.mode != mode ||
      oldDelegate.rotationX != rotationX ||
      oldDelegate.rotationY != rotationY ||
      oldDelegate.scale != scale ||
      oldDelegate.hotspotPulse != hotspotPulse ||
      oldDelegate.baseColor != baseColor;
}
