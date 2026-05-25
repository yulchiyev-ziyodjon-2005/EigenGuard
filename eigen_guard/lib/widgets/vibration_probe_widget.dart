import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../services/material_service.dart';
import '../services/vibration_probe_service.dart';

/// TEGISH TESTI tugmasi — Dashboard pastida ko'rsatiladi.
class VibrationProbeButton extends StatelessWidget {
  final VoidCallback? onCompleted;
  const VibrationProbeButton({super.key, this.onCompleted});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final result = await showVibrationProbeDialog(context);
        if (result != null && result.isValid) onCompleted?.call();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.warning.withValues(alpha: 0.5),
            width: 1.2,
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.vibration, color: AppTheme.warning, size: 18),
            SizedBox(width: 8),
            Text(
              'TEGISH TESTI',
              style: TextStyle(
                color: AppTheme.warning,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vibratsiya probe ni boshlovchi modal — instruktsiya → probe → natija.
Future<VibrationProbeResult?> showVibrationProbeDialog(BuildContext context) {
  return showDialog<VibrationProbeResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _VibrationProbeDialog(),
  );
}

class _VibrationProbeDialog extends StatefulWidget {
  const _VibrationProbeDialog();

  @override
  State<_VibrationProbeDialog> createState() => _VibrationProbeDialogState();
}

enum _ProbeStage { intro, running, result, error }

class _VibrationProbeDialogState extends State<_VibrationProbeDialog>
    with SingleTickerProviderStateMixin {
  final _service = VibrationProbeService();
  late final AnimationController _pulse;
  _ProbeStage _stage = _ProbeStage.intro;
  VibrationProbeResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _runProbe() async {
    setState(() {
      _stage = _ProbeStage.running;
      _result = null;
      _error = null;
    });
    try {
      final r = await _service.probe();
      if (!mounted) return;
      setState(() {
        _result = r;
        _stage = r.isValid ? _ProbeStage.result : _ProbeStage.error;
        _error = r.error;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _ProbeStage.error;
        _error = '$e';
      });
    }
  }

  void _apply() {
    if (_result == null || !_result!.isValid) return;
    MaterialService().setManual(_result!.bestMatch);
    Navigator.of(context).pop(_result);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.background,
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              Flexible(child: _buildBody()),
              const SizedBox(height: 12),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.vibration, color: AppTheme.warning, size: 22),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TEGISH TESTI',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                ),
              ),
              Text(
                'Vibration impulse · IMU response · Damping analysis',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 10),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close, color: AppTheme.textMuted),
        ),
      ],
    );
  }

  Widget _buildBody() {
    switch (_stage) {
      case _ProbeStage.intro:
        return _buildIntro();
      case _ProbeStage.running:
        return _buildRunning();
      case _ProbeStage.result:
        return _buildResult(_result!);
      case _ProbeStage.error:
        return _buildError();
    }
  }

  Widget _buildIntro() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.warning.withValues(alpha: 0.15),
              border: Border.all(color: AppTheme.warning, width: 1.5),
            ),
            child: const Icon(Icons.touch_app,
                color: AppTheme.warning, size: 40),
          ),
          const SizedBox(height: 18),
          const Text(
            'TELEFONNI YUZAGA TIRANG',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Telefon orqasini tekshirilayotgan obyekt (devor, taxta, val) yuzasiga qattiq tiranglik. Vibratsiya impulsi yuborilib, IMU sensori reaksiyani yozadi.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          const Text(
            'Probe davomida telefonni qimirlatmang (~1.2 sek)',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
                fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildRunning() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              final scale = 0.85 + _pulse.value * 0.3;
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.warning.withValues(alpha: 0.18),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.warning.withValues(alpha: 0.5),
                        blurRadius: 30,
                        spreadRadius: 8,
                      )
                    ],
                  ),
                  child: const Icon(Icons.vibration,
                      color: AppTheme.warning, size: 56),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          const Text(
            'IMPULS YUBORILMOQDA…',
            style: TextStyle(
              color: AppTheme.warning,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Telefonni qimirlatmang',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.danger, size: 56),
          const SizedBox(height: 16),
          Text(
            _error ?? 'Noma\'lum xato',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.danger, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildResult(VibrationProbeResult r) {
    final mat = r.bestMatch;
    final confidencePct = (r.matchConfidence * 100).round();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Topilgan material kartochka
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: mat.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: mat.color, width: 1.5),
            ),
            child: Row(
              children: [
                Icon(mat.icon, color: mat.color, size: 36),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TOPILGAN MATERIAL',
                          style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5)),
                      const SizedBox(height: 2),
                      Text(
                        mat.displayName.toUpperCase(),
                        style: TextStyle(
                            color: mat.color,
                            fontSize: 16,
                            fontWeight: FontWeight.w900),
                      ),
                      Text(
                        'Ishonch: $confidencePct%   ·   Damping: ${r.dampingRatio.toStringAsFixed(3)}',
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Reaksiya grafigi (3 o'q)
          Container(
            height: 140,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
            ),
            child: CustomPaint(
              size: Size.infinite,
              painter: _VibrationResponsePainter(
                timeMs: r.timeSeriesMs,
                accelX: r.accelX,
                accelY: r.accelY,
                accelZ: r.accelZ,
                impulseStartMs: r.impulseStartMs,
                impulseEndMs: r.impulseStartMs + r.impulseMs,
                peakTimeMs: r.peakTimeMs,
                materialColor: mat.color,
              ),
            ),
          ),

          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _legendDot('X', Colors.redAccent),
              _legendDot('Y', Colors.greenAccent),
              _legendDot('Z', Colors.blueAccent),
            ],
          ),

          const SizedBox(height: 14),

          // Metrikalar grid
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metricChip('Peak',
                  '${r.peakAccel.toStringAsFixed(2)} m/s²', mat.color),
              _metricChip(
                  'Decay (τ)', '${r.decayTimeMs.toStringAsFixed(0)} ms',
                  mat.color),
              _metricChip(
                  'SNR', r.snr.toStringAsFixed(1), mat.color),
              _metricChip(
                  'Baseline RMS',
                  r.baselineRms.toStringAsFixed(3),
                  mat.color),
            ],
          ),

          const SizedBox(height: 14),

          const Text(
            'BOSHQA EHTIMOLLAR',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          ...r.rankedCandidates.skip(1).take(3).map(_buildCandidateRow),
        ],
      ),
    );
  }

  Widget _legendDot(String label, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 10,
        height: 3,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 4),
      Text(label,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
    ]);
  }

  Widget _metricChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
          ),
          Text(
            value,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _buildCandidateRow(MaterialRankSimple rank) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(rank.profile.icon, color: rank.profile.color, size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            rank.profile.displayName,
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 11),
          ),
        ),
        SizedBox(
          width: 60,
          child: Stack(children: [
            Container(
                height: 4,
                decoration: BoxDecoration(
                    color: AppTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(2))),
            FractionallySizedBox(
              widthFactor: rank.score.clamp(0.0, 1.0),
              child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                      color: rank.profile.color,
                      borderRadius: BorderRadius.circular(2))),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Text(
          '${(rank.score * 100).toStringAsFixed(0)}%',
          style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700),
        ),
      ]),
    );
  }

  Widget _buildActions() {
    switch (_stage) {
      case _ProbeStage.intro:
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('BEKOR',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _runProbe,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.warning,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 10),
              ),
              child: const Text('BOSHLASH',
                  style:
                      TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
            ),
          ],
        );
      case _ProbeStage.running:
        return const SizedBox(height: 0);
      case _ProbeStage.result:
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _runProbe,
              child: const Text('QAYTA',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _apply,
              style: ElevatedButton.styleFrom(
                backgroundColor: _result!.bestMatch.color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
              ),
              child: const Text('QO\'LLASH',
                  style:
                      TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
            ),
          ],
        );
      case _ProbeStage.error:
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('YOPISH',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _runProbe,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.warning,
                foregroundColor: Colors.black,
              ),
              child: const Text('QAYTA',
                  style:
                      TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
            ),
          ],
        );
    }
  }
}

/// IMU reaksiyasini 3 o'q bo'yicha chizadi + impuls va peak markerlari
class _VibrationResponsePainter extends CustomPainter {
  final List<double> timeMs;
  final List<double> accelX;
  final List<double> accelY;
  final List<double> accelZ;
  final double impulseStartMs;
  final double impulseEndMs;
  final double peakTimeMs;
  final Color materialColor;

  _VibrationResponsePainter({
    required this.timeMs,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.impulseStartMs,
    required this.impulseEndMs,
    required this.peakTimeMs,
    required this.materialColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (timeMs.length < 2) return;

    final tStart = timeMs.first;
    final tEnd = timeMs.last;
    final tRange = tEnd - tStart;
    if (tRange <= 0) return;

    // Y o'q diapazoni — barcha 3 o'qning max/min
    double yMin = double.infinity, yMax = -double.infinity;
    for (final v in accelX) {
      if (v < yMin) yMin = v;
      if (v > yMax) yMax = v;
    }
    for (final v in accelY) {
      if (v < yMin) yMin = v;
      if (v > yMax) yMax = v;
    }
    for (final v in accelZ) {
      if (v < yMin) yMin = v;
      if (v > yMax) yMax = v;
    }
    final yPad = math.max((yMax - yMin) * 0.1, 0.5);
    yMin -= yPad;
    yMax += yPad;
    final yRange = yMax - yMin;

    double xMap(double t) =>
        ((t - tStart) / tRange).clamp(0.0, 1.0) * size.width;
    double yMap(double v) =>
        size.height - ((v - yMin) / yRange).clamp(0.0, 1.0) * size.height;

    // Impuls oralig'i (orqa fonda sariq highlight)
    final impulsePaint = Paint()
      ..color = AppTheme.warning.withValues(alpha: 0.15);
    canvas.drawRect(
      Rect.fromLTRB(
        xMap(impulseStartMs),
        0,
        xMap(impulseEndMs),
        size.height,
      ),
      impulsePaint,
    );

    // Peak vertikal chiziq
    final peakPaint = Paint()
      ..color = materialColor.withValues(alpha: 0.6)
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(xMap(peakTimeMs), 0),
      Offset(xMap(peakTimeMs), size.height),
      peakPaint,
    );

    // Nol o'q (agar 0 diapazonda bo'lsa)
    if (yMin < 0 && yMax > 0) {
      final zeroY = yMap(0);
      final zeroPaint = Paint()
        ..color = AppTheme.textMuted.withValues(alpha: 0.3)
        ..strokeWidth = 0.5;
      canvas.drawLine(
          Offset(0, zeroY), Offset(size.width, zeroY), zeroPaint);
    }

    // 3 o'q chiziqlari
    void drawAxis(List<double> values, Color color) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      final path = Path();
      for (int i = 0; i < values.length; i++) {
        final p = Offset(xMap(timeMs[i]), yMap(values[i]));
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, paint);
    }

    drawAxis(accelX, Colors.redAccent);
    drawAxis(accelY, Colors.greenAccent);
    drawAxis(accelZ, Colors.blueAccent);
  }

  @override
  bool shouldRepaint(covariant _VibrationResponsePainter oldDelegate) =>
      oldDelegate.timeMs != timeMs;
}
