import 'dart:math';
import 'package:flutter/material.dart';
import '../core/app_theme.dart';

/// Doiraviy xavf darajasi ko'rsatkichi (Risk Gauge).
class RiskGaugeWidget extends StatefulWidget {
  final double riskPercent;
  final double size;

  const RiskGaugeWidget({
    super.key,
    required this.riskPercent,
    this.size = 200,
  });

  @override
  State<RiskGaugeWidget> createState() => _RiskGaugeWidgetState();
}

class _RiskGaugeWidgetState extends State<RiskGaugeWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _previousValue = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animation = Tween<double>(
      begin: 0,
      end: widget.riskPercent,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant RiskGaugeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.riskPercent != widget.riskPercent) {
      _previousValue = _animation.value;
      _animation = Tween<double>(begin: _previousValue, end: widget.riskPercent)
          .animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
          );
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final value = _animation.value;
        final color = AppTheme.getRiskColor(value);
        final label = AppTheme.getRiskLabel(value);

        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _GaugePainter(
                  value: value / 100.0,
                  color: color,
                  backgroundColor: AppTheme.surfaceLight,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${value.toInt()}%',
                    style: TextStyle(
                      fontSize: widget.size * 0.2,
                      fontWeight: FontWeight.bold,
                      color: color,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value; // 0.0 - 1.0
  final Color color;
  final Color backgroundColor;

  _GaugePainter({
    required this.value,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 12;
    const strokeWidth = 10.0;
    const startAngle = 2.3;
    const totalSweep = 2 * pi - 0.6;

    // Background arc
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      totalSweep,
      false,
      bgPaint,
    );

    // Value arc — oddiy rang bilan (SweepGradient o'rniga)
    if (value > 0.001) {
      final valueSweep = totalSweep * value.clamp(0.0, 1.0);

      final valuePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 2
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        valueSweep,
        false,
        valuePaint,
      );

      // Glow effekt
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 8
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        valueSweep,
        false,
        glowPaint,
      );

      // Indikator nuqta
      final dotAngle = startAngle + valueSweep;
      final dotX = center.dx + radius * cos(dotAngle);
      final dotY = center.dy + radius * sin(dotAngle);

      canvas.drawCircle(Offset(dotX, dotY), 7, Paint()..color = color);
      canvas.drawCircle(Offset(dotX, dotY), 4, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.value != value || oldDelegate.color != color;
  }
}
