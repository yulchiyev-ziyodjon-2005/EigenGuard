import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../models/measurement_record.dart';
import '../services/database_service.dart';
import 'monitoring_screen.dart';

/// HistoryScreen — Saqlangan monitoring sessiyalari tarixi
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final DatabaseService _db = DatabaseService();
  List<MeasurementRecord> _records = [];
  bool _loading = true;
  double _avgRisk = 0;
  double _maxRisk = 0;
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final records = await _db.getAllMeasurements();
    final avg = await _db.getAverageRisk();
    final max = await _db.getMaxRisk();
    final count = await _db.getTotalCount();
    if (mounted) {
      setState(() {
        _records = records;
        _avgRisk = avg;
        _maxRisk = max;
        _totalCount = count;
        _loading = false;
      });
    }
  }

  Future<void> _deleteRecord(MeasurementRecord record) async {
    if (record.id == null) return;
    await _db.deleteMeasurement(record.id!);
    await _loadData();
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text(
          'Tarixni tozalash',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: const Text(
          'Barcha o\'lchov ma\'lumotlari o\'chirilsin?',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('BEKOR',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("O'CHIRISH",
                style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _db.clearAll();
      await _loadData();
    }
  }

  Color _riskColor(String level) {
    switch (level) {
      case 'LOW':
        return AppTheme.success;
      case 'MEDIUM':
        return AppTheme.warning;
      case 'HIGH':
        return AppTheme.danger;
      case 'CRITICAL':
        return const Color(0xFFFF0055);
      default:
        return AppTheme.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width > 700;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(isWide ? 20 : 12),
        child: Column(
          children: [
            _buildHeader(isWide),
            const SizedBox(height: 12),
            _buildStatsRow(),
            const SizedBox(height: 12),
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool wide) {
    return Row(
      children: [
        const Icon(Icons.history_rounded, color: AppTheme.primary, size: 20),
        const SizedBox(width: 8),
        Text(
          wide ? 'O\'LCHOV TARIXI' : 'TARIX',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: wide ? 18 : 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        const Spacer(),
        if (_records.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded,
                color: AppTheme.danger, size: 20),
            onPressed: _clearAll,
            tooltip: 'Barchasini o\'chirish',
          ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded,
              color: AppTheme.primary, size: 20),
          onPressed: _loadData,
          tooltip: 'Yangilash',
        ),
      ],
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _miniStat(
            'JAMI SESSIYA',
            '$_totalCount',
            Icons.list_alt_rounded,
            AppTheme.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _miniStat(
            "O'RT. XAVF",
            '${_avgRisk.toStringAsFixed(1)}%',
            Icons.show_chart_rounded,
            AppTheme.warning,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _miniStat(
            'ENG YUQORI',
            '${_maxRisk.toStringAsFixed(1)}%',
            Icons.warning_amber_rounded,
            AppTheme.danger,
          ),
        ),
      ],
    );
  }

  Widget _miniStat(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.glassCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 9,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_records.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_rounded,
                color: AppTheme.textMuted.withValues(alpha: 0.3), size: 64),
            const SizedBox(height: 16),
            const Text(
              'Hozircha o\'lchovlar yo\'q',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text(
              'Dashboard da monitoring boshlang',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppTheme.primary,
      backgroundColor: AppTheme.surface,
      onRefresh: _loadData,
      child: ListView.separated(
        itemCount: _records.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _buildRecordCard(_records[i]),
      ),
    );
  }

  Widget _buildRecordCard(MeasurementRecord r) {
    final color = _riskColor(r.riskLevel);
    return Dismissible(
      key: Key('rec_${r.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppTheme.danger.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_rounded, color: AppTheme.danger),
      ),
      onDismissed: (_) => _deleteRecord(r),
      child: InkWell(
        onTap: () => _showReplayDialog(r),
        child: Container(
          decoration: AppTheme.glassCard,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Xavf darajasi badge
              Container(
                width: 48,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Text(
                      '${r.riskPercent.toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: color,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      r.riskLevel,
                      style: TextStyle(
                          color: color, fontSize: 7, letterSpacing: 0.5),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Ma'lumotlar
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.formattedTimestamp,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _chip('${r.frequency.toStringAsFixed(1)} Hz',
                            Icons.waves),
                        const SizedBox(width: 8),
                        _chip('${r.amplitude.toStringAsFixed(1)} mm',
                            Icons.height),
                        const SizedBox(width: 8),
                        _chip('${r.durationSeconds}s', Icons.access_time),
                        const SizedBox(width: 8),
                        // Sprint 15 — B2G manba ko'rsatkichi (mobile/edge/fused)
                        _sourceChip(r),
                      ],
                    ),
                  ],
                ),
              ),
              // Kadrlar soni
              Text(
                '${r.frameCount}\nkdr',
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String text, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: AppTheme.textMuted),
        const SizedBox(width: 3),
        Text(
          text,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 10,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  /// Sprint 15 — Yozuv manbasini ko'rsatadigan rangli chip
  /// (mobile=kulrang, edge=ko'k, fused=yashil + sync holati nuqtasi)
  Widget _sourceChip(MeasurementRecord r) {
    Color color;
    IconData icon;
    String label;
    switch (r.source) {
      case MeasurementSource.fused:
        color = AppTheme.success;
        icon = Icons.verified;
        label = 'FUSED';
        break;
      case MeasurementSource.edge:
        color = AppTheme.primary;
        icon = Icons.sensors;
        label = 'EDGE';
        break;
      case MeasurementSource.mobile:
        color = AppTheme.textMuted;
        icon = Icons.smartphone;
        label = 'MOBILE';
        break;
    }
    // Sync indikatori nuqtasi
    Color syncDot;
    switch (r.syncStatus) {
      case SyncStatus.synced:
        syncDot = AppTheme.success;
        break;
      case SyncStatus.failed:
        syncDot = AppTheme.danger;
        break;
      case SyncStatus.pending:
        syncDot = AppTheme.warning;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 8, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 4),
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(color: syncDot, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }

  void _showReplayDialog(MeasurementRecord r) {
    // Sessiya tanlanganda to'liq Monitoring (tahlil) oynasi ochiladi
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MonitoringScreen(initialRecord: r),
      ),
    );
  }
}
