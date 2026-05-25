import 'dart:math';
import 'package:flutter/material.dart';
import '../core/app_theme.dart';

/// Real-time splayn grafik — CustomPainter bilan chiziladi.
/// Asl nuqtalar (doiralar) va splayn egri chiziq (silliq) ko'rsatadi.
class SplineChartWidget extends StatelessWidget {
  final List<double> timeData;
  final List<double> rawData;
  final List<double>? smoothedData; // Splayn smoothed
  final List<double>? smoothedTime;
  final String title;
  final double height;

  const SplineChartWidget({
    super.key,
    required this.timeData,
    required this.rawData,
    this.smoothedData,
    this.smoothedTime,
    this.title = 'Tebranish Signali',
    this.height = 220,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: AppTheme.glassCard,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: AppTheme.chartLine,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // Legend
              _legend('Raw', AppTheme.textMuted),
              const SizedBox(width: 8),
              _legend('Splayn', AppTheme.chartLine),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: timeData.isEmpty
                ? Center(
                    child: Text(
                      'Ma\'lumot kutilmoqda...',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                    ),
                  )
                : CustomPaint(
                    size: Size.infinite,
                    painter: _SplineChartPainter(
                      timeData: timeData,
                      rawData: rawData,
                      smoothedData: smoothedData,
                      smoothedTime: smoothedTime,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _legend(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
      ],
    );
  }
}

class _SplineChartPainter extends CustomPainter {
  final List<double> timeData;
  final List<double> rawData;
  final List<double>? smoothedData;
  final List<double>? smoothedTime;

  _SplineChartPainter({
    required this.timeData,
    required this.rawData,
    this.smoothedData,
    this.smoothedTime,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (timeData.isEmpty) return;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Min/max qiymatlarni aniqlash
    double minY = rawData.reduce(min);
    double maxY = rawData.reduce(max);
    if (smoothedData != null && smoothedData!.isNotEmpty) {
      minY = min(minY, smoothedData!.reduce(min));
      maxY = max(maxY, smoothedData!.reduce(max));
    }
    final yRange = maxY - minY;
    minY -= yRange * 0.15;
    maxY += yRange * 0.15;

    final minX = timeData.first;
    final maxX = timeData.last;

    // Grid chizish
    _drawGrid(canvas, rect, minX, maxX, minY, maxY);

    // Splayn egri chiziq (silliqlangan)
    if (smoothedData != null && smoothedData!.isNotEmpty) {
      final sTime = smoothedTime ?? timeData;
      _drawSmoothCurve(
        canvas,
        rect,
        sTime,
        smoothedData!,
        minX,
        maxX,
        minY,
        maxY,
      );
    }

    // Raw nuqtalar (asl ma'lumotlar)
    _drawRawPoints(canvas, rect, minX, maxX, minY, maxY);

    // O'qlar nomlari
    _drawAxisLabels(canvas, rect, minX, maxX, minY, maxY);
  }

  void _drawGrid(
    Canvas canvas,
    Rect rect,
    double minX,
    double maxX,
    double minY,
    double maxY,
  ) {
    final gridPaint = Paint()
      ..color = AppTheme.gridLine.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // Gorizontal gridlar (5 ta)
    for (int i = 0; i <= 4; i++) {
      final y = rect.top + rect.height * i / 4;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gridPaint);
    }

    // Vertikal gridlar (6 ta)
    for (int i = 0; i <= 5; i++) {
      final x = rect.left + rect.width * i / 5;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), gridPaint);
    }

    // Nol chiziq (agar mavjud)
    if (minY < 0 && maxY > 0) {
      final zeroY = rect.bottom - (0 - minY) / (maxY - minY) * rect.height;
      final zeroPaint = Paint()
        ..color = AppTheme.textMuted.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(rect.left, zeroY),
        Offset(rect.right, zeroY),
        zeroPaint,
      );
    }
  }

  void _drawSmoothCurve(
    Canvas canvas,
    Rect rect,
    List<double> times,
    List<double> values,
    double minX,
    double maxX,
    double minY,
    double maxY,
  ) {
    if (values.length < 2) return;

    final path = Path();
    final fillPath = Path();

    Offset toScreen(double x, double y) {
      final rangeX = (maxX - minX);
      final rangeY = (maxY - minY);
      return Offset(
        rect.left + (rangeX == 0 ? 0.5 : (x - minX) / rangeX) * rect.width,
        rect.bottom - (rangeY == 0 ? 0.5 : (y - minY) / rangeY) * rect.height,
      );
    }

    final first = toScreen(times[0], values[0]);
    path.moveTo(first.dx, first.dy);
    fillPath.moveTo(first.dx, rect.bottom);
    fillPath.lineTo(first.dx, first.dy);

    for (int i = 1; i < values.length; i++) {
      final p = toScreen(times[i], values[i]);
      path.lineTo(p.dx, p.dy);
      fillPath.lineTo(p.dx, p.dy);
    }

    final last = toScreen(times.last, values.last);
    fillPath.lineTo(last.dx, rect.bottom);
    fillPath.close();

    // Fill gradient
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppTheme.chartLine.withValues(alpha: 0.2),
          AppTheme.chartLine.withValues(alpha: 0.0),
        ],
      ).createShader(rect);
    canvas.drawPath(fillPath, fillPaint);

    // Chiziq
    final linePaint = Paint()
      ..color = AppTheme.chartLine
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    // Glow effekt
    final glowPaint = Paint()
      ..color = AppTheme.chartLine.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawPath(path, glowPaint);
  }

  void _drawRawPoints(
    Canvas canvas,
    Rect rect,
    double minX,
    double maxX,
    double minY,
    double maxY,
  ) {
    final dotPaint = Paint()..color = AppTheme.textMuted.withValues(alpha: 0.6);
    final dotBorderPaint = Paint()
      ..color = AppTheme.textMuted.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 0; i < timeData.length; i++) {
      final rangeX = (maxX - minX);
      final rangeY = (maxY - minY);
      final x = rect.left + (rangeX == 0 ? 0.5 : (timeData[i] - minX) / rangeX) * rect.width;
      final y = rect.bottom - (rangeY == 0 ? 0.5 : (rawData[i] - minY) / rangeY) * rect.height;
      canvas.drawCircle(Offset(x, y), 3, dotPaint);
      canvas.drawCircle(Offset(x, y), 3, dotBorderPaint);
    }
  }

  void _drawAxisLabels(
    Canvas canvas,
    Rect rect,
    double minX,
    double maxX,
    double minY,
    double maxY,
  ) {
    const textStyle = TextStyle(
      color: Colors.cyanAccent,
      fontSize: 11,
      fontWeight: FontWeight.bold,
      fontFamily: 'monospace',
    );

    // Y o'qi (chap tomon)
    for (int i = 0; i <= 4; i++) {
      final val = minY + (maxY - minY) * (4 - i) / 4;
      final span = TextSpan(text: val.toStringAsFixed(1), style: textStyle);
      final painter = TextPainter(text: span, textDirection: TextDirection.ltr);
      painter.layout();
      final y = rect.top + rect.height * i / 4 - painter.height / 2;
      painter.paint(canvas, Offset(rect.left, y));
    }
  }

  @override
  bool shouldRepaint(covariant _SplineChartPainter oldDelegate) => true;
}
