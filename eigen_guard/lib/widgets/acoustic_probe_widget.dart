import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../ffi/native_engine.dart';
import '../services/acoustic_probe_service.dart';
import '../services/material_service.dart';

/// AKUSTIK ZOND tugmasi — Dashboard pastida ko'rsatiladi
class AcousticProbeButton extends StatelessWidget {
  final NativeEngine engine;
  final VoidCallback? onCompleted;
  const AcousticProbeButton({
    super.key,
    required this.engine,
    this.onCompleted,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final result = await showAcousticProbeDialog(context, engine);
        if (result != null && result.isValid) onCompleted?.call();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.secondary.withValues(alpha: 0.5),
            width: 1.2,
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.graphic_eq, color: AppTheme.secondary, size: 18),
            SizedBox(width: 8),
            Text(
              'AKUSTIK ZOND',
              style: TextStyle(
                color: AppTheme.secondary,
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

/// Akustik probe ni boshlovchi modal dialog — chirp animatsiyasi va natija paneli.
/// Foydalanuvchi natijani qabul qilsa, joriy materialni o'zgartiradi.
Future<ProbeResult?> showAcousticProbeDialog(
    BuildContext context, NativeEngine engine) {
  return showDialog<ProbeResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _AcousticProbeDialog(engine: engine),
  );
}

class _AcousticProbeDialog extends StatefulWidget {
  final NativeEngine engine;
  const _AcousticProbeDialog({required this.engine});

  @override
  State<_AcousticProbeDialog> createState() => _AcousticProbeDialogState();
}

class _AcousticProbeDialogState extends State<_AcousticProbeDialog>
    with SingleTickerProviderStateMixin {
  late final AcousticProbeService _service;
  late final AnimationController _pulse;
  ProbeResult? _result;
  bool _isRunning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = AcousticProbeService(widget.engine);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    // Avtomatik boshlanadi
    WidgetsBinding.instance.addPostFrameCallback((_) => _runProbe());
  }

  @override
  void dispose() {
    _pulse.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _runProbe() async {
    setState(() {
      _isRunning = true;
      _error = null;
      _result = null;
    });
    try {
      final r = await _service.probe();
      if (!mounted) return;
      setState(() {
        _result = r;
        _isRunning = false;
        _error = r.isValid ? null : (r.error ?? 'Noma\'lum xato');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRunning = false;
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
              if (_isRunning)
                _buildRunningState()
              else if (_error != null)
                _buildErrorState()
              else if (_result != null)
                Flexible(child: _buildResultState(_result!)),
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
        const Icon(Icons.graphic_eq, color: AppTheme.secondary, size: 22),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AKUSTIK ZOND',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                ),
              ),
              Text(
                'Active acoustic probing · 100 Hz → 5 kHz sweep',
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

  Widget _buildRunningState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              final scale = 0.8 + _pulse.value * 0.4;
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.secondary.withValues(alpha: 0.15),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.secondary.withValues(alpha: 0.4),
                        blurRadius: 30,
                        spreadRadius: 8,
                      )
                    ],
                  ),
                  child: const Icon(Icons.volume_up,
                      color: AppTheme.secondary, size: 56),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          const Text(
            'CHIRP YUBORILMOQDA …',
            style: TextStyle(
              color: AppTheme.secondary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Telefonni obyektga 5-15 sm masofada tuting',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.danger, size: 56),
          const SizedBox(height: 16),
          Text(
            _error ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.danger, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildResultState(ProbeResult r) {
    final mat = r.bestMatch;
    final confidencePct = (r.matchConfidence * 100).round();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Topilgan material
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
                      const Text(
                        'TOPILGAN MATERIAL',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        mat.displayName.toUpperCase(),
                        style: TextStyle(
                          color: mat.color,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Ishonch: $confidencePct%   ·   Kritik amp.: ${mat.criticalAmplitudeMm.toStringAsFixed(1)} mm',
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

          // Spektr vizualizatsiyasi
          Container(
            height: 130,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
            ),
            child: CustomPaint(
              size: Size.infinite,
              painter: _SpectrumPainter(
                spectrum: r.spectrum,
                peaks: r.peaks,
                sampleRate: r.sampleRate,
                color: mat.color,
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Topilgan peaklar
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: r.peaks.take(5).map((p) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: mat.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${p.freqHz.toStringAsFixed(0)} Hz',
                  style: TextStyle(
                    color: mat.color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 14),

          // Boshqa nomzodlar (top-3)
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

  Widget _buildCandidateRow(MaterialRank rank) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
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
            child: Stack(
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: rank.score.clamp(0.0, 1.0),
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: rank.profile.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(rank.score * 100).toStringAsFixed(0)}%',
            style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    if (_isRunning) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: _runProbe,
          child: const Text('QAYTA',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 8),
        if (_result != null && _result!.isValid)
          ElevatedButton(
            onPressed: _apply,
            style: ElevatedButton.styleFrom(
              backgroundColor: _result!.bestMatch.color,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text('QO\'LLASH',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
          ),
      ],
    );
  }
}

/// FFT spektrini chizadi + aniqlangan peaklarni belgilaydi.
class _SpectrumPainter extends CustomPainter {
  final Float64List spectrum;
  final List<ResonancePeak> peaks;
  final double sampleRate;
  final Color color;

  _SpectrumPainter({
    required this.spectrum,
    required this.peaks,
    required this.sampleRate,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (spectrum.isEmpty) return;

    // Faqat 0–6 kHz diapazonida ko'rsatamiz (chirp diapazoniga mos)
    const maxDisplayHz = 6000.0;
    final binHz = sampleRate / (2.0 * spectrum.length);
    final maxBin = math.min((maxDisplayHz / binHz).round(), spectrum.length);
    if (maxBin < 4) return;

    double maxMag = 1e-9;
    for (int i = 0; i < maxBin; i++) {
      if (spectrum[i] > maxMag) maxMag = spectrum[i];
    }

    final paint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;

    final binWidth = size.width / maxBin;
    for (int i = 0; i < maxBin; i++) {
      final h = (spectrum[i] / maxMag) * size.height;
      canvas.drawRect(
        Rect.fromLTWH(
            i * binWidth, size.height - h, binWidth.clamp(0.5, 4), h),
        paint,
      );
    }

    // Peak markerlari
    final peakPaint = Paint()
      ..color = AppTheme.danger
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final p in peaks) {
      if (p.freqHz > maxDisplayHz) continue;
      final x = (p.freqHz / maxDisplayHz) * size.width;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        peakPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter oldDelegate) =>
      oldDelegate.spectrum != spectrum;
}
