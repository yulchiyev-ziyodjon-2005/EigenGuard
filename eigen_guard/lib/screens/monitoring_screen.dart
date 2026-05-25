import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../models/material_profile.dart';
import '../models/measurement_record.dart';
import '../services/ai_assistant_service.dart';
import '../services/database_service.dart';
import '../services/live_metrics_service.dart';
import '../services/material_service.dart';

/// MonitoringScreen — REAL ma'lumotlar bilan ishlaydigan tahlil oynasi.
/// HECH QANDAY synthetic/Random() yo'q — barcha ma'lumotlar:
///   • LIVE tabi: Dashboard'ning hozirgi pipeline'idan
///   • TARIX tabi: SQLite'da saqlangan haqiqiy bufferlardan
class MonitoringScreen extends StatefulWidget {
  final MeasurementRecord? initialRecord;
  final AiAssistantService? aiService;
  final Function(int)? onTabRequested;

  const MonitoringScreen({
    super.key,
    this.initialRecord,
    this.aiService,
    this.onTabRequested,
  });

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

enum _ViewMode { live, history }

class _MonitoringScreenState extends State<MonitoringScreen> {
  final DatabaseService _db = DatabaseService();
  final LiveMetricsService _live = LiveMetricsService();
  final MaterialService _material = MaterialService();

  _ViewMode _mode = _ViewMode.live;
  MeasurementRecord? _selectedRecord;
  List<MeasurementRecord> _recentRecords = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    // Agar dastlabki rekord berilgan bo'lsa, TARIX tabga o'tamiz
    if (widget.initialRecord != null) {
      _mode = _ViewMode.history;
      _selectedRecord = widget.initialRecord;
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    final records = await _db.getAllMeasurements();
    if (!mounted) return;
    setState(() {
      _recentRecords = records;
      if (_selectedRecord == null && records.isNotEmpty) {
        _selectedRecord = records.first;
      }
      _loading = false;
    });
  }

  void _selectRecord(MeasurementRecord r) {
    setState(() => _selectedRecord = r);
  }

  Color _riskColor(double risk) {
    if (risk > 75) return AppTheme.danger;
    if (risk > 50) return AppTheme.warning;
    return AppTheme.success;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            const SizedBox(height: 8),
            Expanded(
              child: _mode == _ViewMode.live
                  ? _buildLiveView()
                  : _buildHistoryView(),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HEADER + TAB BAR
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: const [
          Icon(Icons.analytics_rounded, color: AppTheme.primary, size: 22),
          SizedBox(width: 10),
          Text(
            'MONITORING & TAHLIL',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(child: _tabButton(_ViewMode.live, 'LIVE', Icons.bolt)),
          const SizedBox(width: 8),
          Expanded(
              child: _tabButton(_ViewMode.history, 'TARIX', Icons.history)),
        ],
      ),
    );
  }

  Widget _tabButton(_ViewMode m, String label, IconData icon) {
    final isActive = _mode == m;
    final color = m == _ViewMode.live ? AppTheme.success : AppTheme.primary;
    return GestureDetector(
      onTap: () => setState(() => _mode = m),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.18) : AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? color : AppTheme.surfaceLight,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isActive ? color : AppTheme.textMuted, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isActive ? color : AppTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // LIVE — Hozirgi monitoring pipeline'idan jonli ma'lumot
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildLiveView() {
    return ValueListenableBuilder<LiveMetrics>(
      valueListenable: _live.metrics,
      builder: (context, m, _) {
        if (!m.isMonitoring && !m.hasData) {
          return _buildLiveEmpty();
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _liveStatusCard(m),
              const SizedBox(height: 12),
              _liveMetricsRow(m),
              const SizedBox(height: 14),
              _liveAmpChart(),
              const SizedBox(height: 14),
              _liveSpectrumChart(),
              const SizedBox(height: 14),
              _livePredictionCard(m),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLiveEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sensors_off,
              color: AppTheme.textMuted.withValues(alpha: 0.4), size: 56),
          const SizedBox(height: 14),
          const Text(
            'Jonli ma\'lumot yo\'q',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 14),
          ),
          const SizedBox(height: 6),
          const Text(
            'Dashboard\'da skanerlashni boshlang',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () => widget.onTabRequested?.call(0),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.4),
                ),
                borderRadius: BorderRadius.circular(10),
                color: AppTheme.primary.withValues(alpha: 0.08),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.radar, color: AppTheme.primary, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Dashboard ga o\'tish',
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveStatusCard(LiveMetrics m) {
    final color = _riskColor(m.riskPercent);
    return ValueListenableBuilder<MaterialProfile>(
      valueListenable: _material.current,
      builder: (context, mat, _) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: mat.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(mat.icon, color: mat.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mat.displayName.toUpperCase(),
                      style: TextStyle(
                        color: mat.color,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      m.objectLabel ?? 'Obyekt aniqlanmoqda...',
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color),
                ),
                child: Text(
                  m.riskLevelLabel,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _liveMetricsRow(LiveMetrics m) {
    return Row(
      children: [
        Expanded(
            child: _metricBox(
                'AMP', '${m.amplitudeMm.toStringAsFixed(2)} mm', AppTheme.warning)),
        const SizedBox(width: 8),
        Expanded(
            child: _metricBox(
                'FREQ', '${m.frequencyHz.toStringAsFixed(0)} Hz', AppTheme.success)),
        const SizedBox(width: 8),
        Expanded(
            child: _metricBox('RISK', '${m.riskPercent.toStringAsFixed(0)}%',
                _riskColor(m.riskPercent))),
      ],
    );
  }

  Widget _metricBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _liveAmpChart() {
    return ValueListenableBuilder<List<double>>(
      valueListenable: _live.liveAmpWindow,
      builder: (context, amps, _) {
        return _ChartCard(
          title: 'AMPLITUDA (mm) — LIVE',
          subtitle: amps.isEmpty ? 'Ma\'lumot kutilmoqda...' : '${amps.length} samples',
          height: 170,
          child: amps.length < 2
              ? const _EmptyChart('Ma\'lumot to\'planmoqda…')
              : CustomPaint(
                  size: Size.infinite,
                  painter: _TimeSeriesPainter(
                    values: amps,
                    color: AppTheme.warning,
                  ),
                ),
        );
      },
    );
  }

  Widget _liveSpectrumChart() {
    return ValueListenableBuilder<Float64List>(
      valueListenable: _live.liveSpectrum,
      builder: (context, spec, _) {
        return _ChartCard(
          title: 'FFT SPEKTR — LIVE',
          subtitle: spec.isEmpty
              ? 'Mikrofon ma\'lumotini kutmoqda...'
              : 'Sample rate: ${_live.liveSpectrumSampleRate.toStringAsFixed(0)} Hz',
          height: 170,
          child: spec.isEmpty
              ? const _EmptyChart('Spektr hisoblanmoqda…')
              : CustomPaint(
                  size: Size.infinite,
                  painter: _FftBarPainter(
                    spectrum: spec,
                    sampleRate: _live.liveSpectrumSampleRate,
                    color: AppTheme.success,
                  ),
                ),
        );
      },
    );
  }

  Widget _livePredictionCard(LiveMetrics m) {
    return _ChartCard(
      title: '§6.4 BASHORAT (RUL)',
      subtitle: m.hasPrediction
          ? 'Parabolik fit y = ${m.trendA.toStringAsFixed(3)} + ${m.trendB.toStringAsFixed(3)}·t + ${m.trendC.toStringAsFixed(3)}·t²'
          : 'Bashorat uchun yetarli ma\'lumot kutilmoqda',
      height: 110,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('TREND',
                      style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 10,
                          letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Text(
                    '${m.trendArrow}  ${m.hasPrediction ? (m.trend.name.toUpperCase()) : '—'}',
                    style: TextStyle(
                      color: m.trend == TrendDir.rising
                          ? AppTheme.danger
                          : (m.trend == TrendDir.falling
                              ? AppTheme.success
                              : AppTheme.primary),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            Container(width: 1, height: 50, color: AppTheme.surfaceLight),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('KRITIKGACHA',
                      style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 10,
                          letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Text(
                    m.rulLabel,
                    style: TextStyle(
                      color: m.hoursToCritical > 0 && m.hoursToCritical < 24
                          ? AppTheme.danger
                          : AppTheme.primary,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TARIX — Saqlangan haqiqiy ma'lumotlar
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildHistoryView() {
    if (_recentRecords.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_toggle_off,
                color: AppTheme.textMuted.withValues(alpha: 0.4), size: 56),
            const SizedBox(height: 14),
            const Text(
              'Saqlangan sessiya yo\'q',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 14),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        SizedBox(
          height: 70,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _recentRecords.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => _historyChip(_recentRecords[i]),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _selectedRecord == null
              ? const Center(
                  child: Text('Sessiya tanlang',
                      style: TextStyle(
                          color: AppTheme.textMuted, fontSize: 12)))
              : _historyDetail(_selectedRecord!),
        ),
      ],
    );
  }

  Widget _historyChip(MeasurementRecord r) {
    final isSelected = _selectedRecord?.id == r.id;
    final color = _riskColor(r.riskPercent);
    return GestureDetector(
      onTap: () => _selectRecord(r),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : AppTheme.surfaceLight,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              r.formattedTimestamp,
              style: TextStyle(
                color: isSelected ? AppTheme.textPrimary : AppTheme.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                Text('${r.riskPercent.toStringAsFixed(0)}%',
                    style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w900)),
                const SizedBox(width: 6),
                if (r.materialId != null)
                  Text(
                    MaterialPresets.byId(r.materialId!).displayName,
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 9),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyDetail(MeasurementRecord r) {
    final mat = r.materialId != null
        ? MaterialPresets.byId(r.materialId!)
        : MaterialPresets.universal;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _historyParamsCard(r, mat),
          const SizedBox(height: 14),
          _historyAmpChart(r),
          const SizedBox(height: 14),
          _historyFftChart(r),
          const SizedBox(height: 14),
          _historyPredictionCard(r),
          if (r.latitude != null) ...[
            const SizedBox(height: 14),
            _historyGeoCard(r),
          ],
          const SizedBox(height: 14),
          if (r.riskPercent > 50) _aiTroubleshootButton(r),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _historyParamsCard(MeasurementRecord r, MaterialProfile mat) {
    final color = _riskColor(r.riskPercent);
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(mat.icon, color: mat.color, size: 18),
              const SizedBox(width: 8),
              Text(
                mat.displayName.toUpperCase(),
                style: TextStyle(
                  color: mat.color,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color),
                ),
                child: Text(
                  r.riskLevel,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 10,
            children: [
              _paramTile('Amplituda', '${r.amplitude.toStringAsFixed(2)} mm'),
              _paramTile('Chastota', '${r.frequency.toStringAsFixed(0)} Hz'),
              _paramTile('Xavf', '${r.riskPercent.toStringAsFixed(0)}%'),
              _paramTile('Davomiyligi', '${r.durationSeconds} s'),
              _paramTile('Kadrlar', '${r.frameCount}'),
              if (r.objectLabel != null)
                _paramTile('Obyekt', r.objectLabel!),
              // Sprint 15 — B2G ekotizimi manba va sync ma'lumotlari
              _paramTile('Manba', r.source.wireName.toUpperCase()),
              if (r.fusionConfidence != null)
                _paramTile('Fusion',
                    '${(r.fusionConfidence! * 100).toStringAsFixed(0)}%'),
              if (r.deviceId != null) _paramTile('Edge ID', r.deviceId!),
            ],
          ),
        ],
      ),
    );
  }

  Widget _paramTile(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _historyAmpChart(MeasurementRecord r) {
    final series = r.amplitudeSeries;
    return _ChartCard(
      title: 'AMPLITUDA TARIXI (mm)',
      subtitle: series == null
          ? 'Bu sessiya uchun bufer saqlanmagan'
          : '${series.length} samples',
      height: 170,
      child: (series == null || series.length < 2)
          ? const _EmptyChart('Buffer mavjud emas')
          : CustomPaint(
              size: Size.infinite,
              painter: _TimeSeriesPainter(
                values: series,
                color: AppTheme.warning,
              ),
            ),
    );
  }

  Widget _historyFftChart(MeasurementRecord r) {
    final spec = r.fftSpectrum;
    final rate = r.fftSampleRate ?? 44100.0;
    return _ChartCard(
      title: 'FFT SPEKTR (saqlangan)',
      subtitle: spec == null
          ? 'Spektr saqlanmagan'
          : 'Sample rate: ${rate.toStringAsFixed(0)} Hz',
      height: 170,
      child: (spec == null || spec.isEmpty)
          ? const _EmptyChart('Spektr mavjud emas')
          : CustomPaint(
              size: Size.infinite,
              painter: _FftBarPainter(
                spectrum: Float64List.fromList(spec),
                sampleRate: rate,
                color: AppTheme.success,
              ),
            ),
    );
  }

  Widget _historyPredictionCard(MeasurementRecord r) {
    final hasPred = r.predictionA != null &&
        r.predictionB != null &&
        r.predictionC != null;
    return _ChartCard(
      title: '§6.4 PARABOLIK BASHORAT',
      subtitle: hasPred
          ? 'y = ${r.predictionA!.toStringAsFixed(3)} + ${r.predictionB!.toStringAsFixed(3)}·t + ${r.predictionC!.toStringAsFixed(3)}·t²'
          : 'Bashorat saqlanmagan',
      height: 110,
      child: !hasPred
          ? const _EmptyChart('Bashorat saqlanmagan')
          : Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('KRITIKGACHA',
                            style: TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 10,
                                letterSpacing: 1)),
                        const SizedBox(height: 4),
                        Text(
                          _formatHoursLabel(r.hoursToCritical ?? -1),
                          style: const TextStyle(
                              color: AppTheme.primary,
                              fontSize: 18,
                              fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 50, color: AppTheme.surfaceLight),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('KOEFFITSIYENTLAR',
                            style: TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 10,
                                letterSpacing: 1)),
                        const SizedBox(height: 4),
                        Text(
                          'a=${r.predictionA!.toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 11),
                        ),
                        Text(
                          'b=${r.predictionB!.toStringAsFixed(3)}, c=${r.predictionC!.toStringAsFixed(4)}',
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  String _formatHoursLabel(double h) {
    if (h < 0) return '—';
    if (h < 1) return '${(h * 60).toStringAsFixed(0)} daq';
    if (h < 48) return '${h.toStringAsFixed(1)} soat';
    return '${(h / 24).toStringAsFixed(1)} kun';
  }

  Widget _historyGeoCard(MeasurementRecord r) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.gps_fixed, color: AppTheme.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('GEO-TAG',
                    style: TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  '${r.latitude!.toStringAsFixed(5)}, ${r.longitude!.toStringAsFixed(5)}'
                  '${r.locationAccuracyM != null ? "  ±${r.locationAccuracyM!.toStringAsFixed(0)}m" : ""}',
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          if (r.magneticFieldUt != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (r.magneticAnomaly == true
                        ? AppTheme.danger
                        : AppTheme.success)
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${r.magneticFieldUt!.toStringAsFixed(0)} µT',
                style: TextStyle(
                  color: r.magneticAnomaly == true
                      ? AppTheme.danger
                      : AppTheme.success,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _aiTroubleshootButton(MeasurementRecord r) {
    return GestureDetector(
      onTap: () async {
        if (widget.aiService == null) return;
        final info = "Sessiya: ${r.formattedTimestamp}\n"
            "Material: ${r.materialId != null ? MaterialPresets.byId(r.materialId!).displayName : 'Universal'}\n"
            "Obyekt: ${r.objectLabel ?? 'Aniqlanmagan'}\n"
            "Xavf: ${r.riskPercent.toStringAsFixed(1)}%\n"
            "Chastota: ${r.frequency.toStringAsFixed(1)} Hz\n"
            "Amplituda: ${r.amplitude.toStringAsFixed(2)} mm";
        await widget.aiService!.startTroubleshooting(info);
        if (!mounted) return;
        widget.onTabRequested?.call(4);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.primary, AppTheme.secondary],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.4),
              blurRadius: 14,
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome, color: Colors.white),
            SizedBox(width: 10),
            Text(
              'AI BILAN MUAMMONI TAHLIL',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CHART CONTAINER + PAINTERS — Real ma'lumotni chizadi (no synthetic)
// ═══════════════════════════════════════════════════════════════════════════
class _ChartCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final double height;
  final Widget child;

  const _ChartCard({
    required this.title,
    this.subtitle,
    required this.height,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 11),
              child: Text(
                subtitle!,
                style:
                    const TextStyle(color: AppTheme.textMuted, fontSize: 10),
              ),
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(height: height - 50, child: child),
        ],
      ),
    );
  }
}

class _EmptyChart extends StatelessWidget {
  final String message;
  const _EmptyChart(this.message);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
      ),
    );
  }
}

/// Real time-series (amplituda mm) — yumshatilmagan haqiqiy chiziq
class _TimeSeriesPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  _TimeSeriesPainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    double minY = values.reduce(min);
    double maxY = values.reduce(max);
    if ((maxY - minY).abs() < 1e-6) {
      minY -= 1;
      maxY += 1;
    }
    final pad = (maxY - minY) * 0.1;
    minY -= pad;
    maxY += pad;
    final yRange = maxY - minY;

    // Grid
    final gridPaint = Paint()
      ..color = AppTheme.surfaceLight.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;
    for (int i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Fill area
    final fillPath = Path();
    final linePath = Path();
    double xMap(int i) => i * size.width / (values.length - 1);
    double yMap(double v) =>
        size.height - ((v - minY) / yRange) * size.height;

    final p0 = Offset(xMap(0), yMap(values[0]));
    linePath.moveTo(p0.dx, p0.dy);
    fillPath.moveTo(p0.dx, size.height);
    fillPath.lineTo(p0.dx, p0.dy);
    for (int i = 1; i < values.length; i++) {
      final p = Offset(xMap(i), yMap(values[i]));
      linePath.lineTo(p.dx, p.dy);
      fillPath.lineTo(p.dx, p.dy);
    }
    fillPath.lineTo(xMap(values.length - 1), size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.3),
          color.withValues(alpha: 0.02),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    canvas.drawPath(linePath, linePaint);

    // Min/max labellar
    final tp = TextPainter(
      text: TextSpan(
        text:
            'min ${minY.toStringAsFixed(2)}   max ${maxY.toStringAsFixed(2)}',
        style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 9,
            fontFamily: 'monospace'),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, const Offset(2, 2));
  }

  @override
  bool shouldRepaint(covariant _TimeSeriesPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

/// Real FFT spektri — bin'lardan log-scale bar chart
class _FftBarPainter extends CustomPainter {
  final Float64List spectrum;
  final double sampleRate;
  final Color color;
  static const double _maxDisplayHz = 5000.0;

  _FftBarPainter({
    required this.spectrum,
    required this.sampleRate,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (spectrum.isEmpty) return;

    final binHz = sampleRate / (2.0 * spectrum.length);
    final maxBin = min((_maxDisplayHz / binHz).round(), spectrum.length);
    if (maxBin < 4) return;

    // Logarifmik bin'larga grouping (visualization aniqligi uchun)
    const visualBars = 64;
    final groupedMags = List<double>.filled(visualBars, 0.0);
    final binsPerGroup = (maxBin / visualBars).ceil();
    double maxMag = 1e-9;
    for (int g = 0; g < visualBars; g++) {
      double s = 0;
      int n = 0;
      for (int k = 0; k < binsPerGroup; k++) {
        final idx = g * binsPerGroup + k;
        if (idx >= maxBin) break;
        s += spectrum[idx];
        n++;
      }
      groupedMags[g] = n > 0 ? s / n : 0;
      if (groupedMags[g] > maxMag) maxMag = groupedMags[g];
    }

    // Grid chiziqlari (gorizontal)
    final gridPaint = Paint()
      ..color = AppTheme.surfaceLight.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;
    for (int i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final barWidth = size.width / visualBars;
    final barPaint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < visualBars; i++) {
      final hRatio = (groupedMags[i] / maxMag).clamp(0.0, 1.0);
      final h = hRatio * size.height;
      // Yuqori chastota — yuqori intensity rangi
      final tColor = Color.lerp(
          color.withValues(alpha: 0.6),
          AppTheme.danger.withValues(alpha: 0.9),
          hRatio)!;
      barPaint.color = tColor;
      canvas.drawRect(
        Rect.fromLTWH(
            i * barWidth, size.height - h, barWidth * 0.85, h),
        barPaint,
      );
    }

    // X axis labellar (Hz)
    final labelPainter = TextPainter(textDirection: TextDirection.ltr);
    final hzLabels = [0.0, 1000.0, 2000.0, 3000.0, 4000.0, 5000.0];
    for (final hz in hzLabels) {
      final ratio = hz / _maxDisplayHz;
      if (ratio > 1) continue;
      labelPainter.text = TextSpan(
        text: '${(hz / 1000).toStringAsFixed(0)}k',
        style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 9,
            fontFamily: 'monospace'),
      );
      labelPainter.layout();
      labelPainter.paint(
        canvas,
        Offset(ratio * size.width - labelPainter.width / 2,
            size.height - labelPainter.height - 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FftBarPainter oldDelegate) =>
      oldDelegate.spectrum != spectrum ||
      oldDelegate.sampleRate != sampleRate;
}
