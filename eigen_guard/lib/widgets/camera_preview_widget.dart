import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/app_theme.dart';
import '../services/camera_service.dart';

/// Kamera oynasi va issiqlik (Heatmap) chizuvchi vidjyet.
/// Phase 7: skanerlash davrida pastdan yuqoriga harakatlanuvchi scan-line va
/// faol obyekt bbox burchaklarida corner brackets ko'rsatiladi.
class CameraPreviewWidget extends StatefulWidget {
  final double dx;
  final double dy;
  final double magnitude;
  final bool isMonitoring;
  /// Faol (Tap-to-Lock) obyekt bbox — corner brackets uchun
  final Rect? activeBox;
  /// Bbox rangi (material rangiga moslashtirilishi mumkin)
  final Color bracketColor;

  const CameraPreviewWidget({
    super.key,
    required this.dx,
    required this.dy,
    required this.magnitude,
    required this.isMonitoring,
    this.activeBox,
    this.bracketColor = const Color(0xFF00E5FF),
  });

  @override
  State<CameraPreviewWidget> createState() => _CameraPreviewWidgetState();
}

class _CameraPreviewWidgetState extends State<CameraPreviewWidget>
    with SingleTickerProviderStateMixin {
  final CameraService _cameraService = CameraService();
  late final AnimationController _scanCtrl;

  @override
  void initState() {
    super.initState();
    _scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _scanCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ruxsat berilmagan holat
    if (_cameraService.permissionDenied) {
      return Container(
        color: const Color(0xFF0A0E1A),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.no_photography_rounded,
                  color: AppTheme.danger.withValues(alpha: 0.7), size: 48),
              const SizedBox(height: 12),
              const Text('Kamera ruxsati berilmagan',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              const Text('Sozlamalar orqali ruxsat bering',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => openAppSettings(),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.4)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Sozlamalarni ochish',
                      style: TextStyle(color: AppTheme.primary, fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Kamera hali tayyorlanmagan
    if (!_cameraService.isInitialized || _cameraService.controller == null) {
      return Container(
        color: const Color(0xFF0A0E1A),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  color: Colors.cyanAccent,
                  strokeWidth: 3,
                ),
              ),
              SizedBox(height: 16),
              Text('Kamera ulanmoqda...',
                  style: TextStyle(color: Colors.cyanAccent, fontSize: 13, letterSpacing: 1.5)),
            ],
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Kamera obyekti — to'liq ekran, lekin format buzilmaydi
        SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              // Android da odatda Portrait bo'lganda height va width o'rnini almashtiramiz
              width: _cameraService.controller!.value.previewSize?.height ?? 1080,
              height: _cameraService.controller!.value.previewSize?.width ?? 1920,
              child: CameraPreview(_cameraService.controller!),
            ),
          ),
        ),

        // Phase 7 — Scan-line animatsiya (faqat monitoring davrida)
        if (widget.isMonitoring)
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _scanCtrl,
              builder: (context, _) {
                return CustomPaint(
                  painter: _ScanLinePainter(
                    progress: _scanCtrl.value,
                    color: widget.bracketColor,
                  ),
                );
              },
            ),
          ),

        // Phase 7 — Corner brackets faol obyekt bbox uchun
        if (widget.activeBox != null)
          IgnorePointer(
            child: CustomPaint(
              painter: _CornerBracketsPainter(
                box: widget.activeBox!,
                color: widget.bracketColor,
              ),
            ),
          ),

        // Tebranish harakatlari (Optical Flow dx, dy yo'nalishi)
        if (widget.isMonitoring && widget.magnitude > 0.5)
          CustomPaint(
            painter: HeatmapOverlayPainter(
              dx: widget.dx,
              dy: widget.dy,
              magnitude: widget.magnitude,
            ),
          ),
      ],
    );
  }
}

/// Pastdan yuqoriga harakatlanuvchi gradient chiziq (sanoat scan effect)
class _ScanLinePainter extends CustomPainter {
  final double progress; // 0.0 — 1.0
  final Color color;

  _ScanLinePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * (1.0 - progress);
    const bandHeight = 60.0;
    final rect = Rect.fromLTWH(0, y - bandHeight / 2, size.width, bandHeight);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.35),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, paint);

    // Asosiy o'tkir chiziq
    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
  }

  @override
  bool shouldRepaint(covariant _ScanLinePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

/// Faol obyekt bbox burchaklarida 4 ta L-shape corner brackets
class _CornerBracketsPainter extends CustomPainter {
  final Rect box;
  final Color color;
  static const double _len = 18.0;
  static const double _stroke = 2.5;

  _CornerBracketsPainter({required this.box, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Top-left
    canvas.drawLine(Offset(box.left, box.top + _len),
        Offset(box.left, box.top), paint);
    canvas.drawLine(
        Offset(box.left, box.top), Offset(box.left + _len, box.top), paint);
    // Top-right
    canvas.drawLine(Offset(box.right - _len, box.top),
        Offset(box.right, box.top), paint);
    canvas.drawLine(
        Offset(box.right, box.top), Offset(box.right, box.top + _len), paint);
    // Bottom-left
    canvas.drawLine(Offset(box.left, box.bottom - _len),
        Offset(box.left, box.bottom), paint);
    canvas.drawLine(Offset(box.left, box.bottom),
        Offset(box.left + _len, box.bottom), paint);
    // Bottom-right
    canvas.drawLine(Offset(box.right - _len, box.bottom),
        Offset(box.right, box.bottom), paint);
    canvas.drawLine(Offset(box.right, box.bottom),
        Offset(box.right, box.bottom - _len), paint);
  }

  @override
  bool shouldRepaint(covariant _CornerBracketsPainter oldDelegate) =>
      oldDelegate.box != box || oldDelegate.color != color;
}

/// Optical Flow dx/dy natijalariga ko'ra "qizib" boruvchi markerlar
class HeatmapOverlayPainter extends CustomPainter {
  final double dx;
  final double dy;
  final double magnitude;

  HeatmapOverlayPainter({
    required this.dx,
    required this.dy,
    required this.magnitude,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (magnitude < 0.1 || magnitude.isNaN || dx.isNaN || dy.isNaN) return;

    final center = size.center(Offset.zero);

    // Rangi tebranish kuchiga qarab sariq -> to'q qizil ga aylanadi
    Color heatColor = AppTheme.warning;
    if (magnitude > 10) heatColor = const Color(0xFFFF6B35); // orange
    if (magnitude > 20) heatColor = AppTheme.danger; // red

    final paint = Paint()
      ..color = heatColor.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;

    // Markaziy obyektdagi asosiy sakrash doirasi
    final radius = (magnitude * 5).clamp(10.0, size.width / 4);
    canvas.drawCircle(center, radius, paint);

    // Yo'nalish chizig'i
    final linePaint = Paint()
      ..color = heatColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    // dx va dy pixel emas, koeffitsient ekaniga asoslanib uzunlikni chizamiz
    final endPoint = Offset(center.dx + dx * 10, center.dy + dy * 10);

    // Ekrandan chiqib ketmasligi uchun chegaralab oling
    final clampedEndX = endPoint.dx.clamp(0.0, size.width);
    final clampedEndY = endPoint.dy.clamp(0.0, size.height);

    canvas.drawLine(center, Offset(clampedEndX, clampedEndY), linePaint);

    // Kichik yordamchi izlar
    canvas.drawCircle(Offset(clampedEndX, clampedEndY), 4,
        linePaint..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant HeatmapOverlayPainter oldDelegate) {
    return dx != oldDelegate.dx ||
        dy != oldDelegate.dy ||
        magnitude != oldDelegate.magnitude;
  }
}
