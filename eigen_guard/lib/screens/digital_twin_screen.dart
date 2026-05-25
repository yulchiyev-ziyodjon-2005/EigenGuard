import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../core/app_theme.dart';
import '../models/material_profile.dart';
import '../models/mesh_3d.dart';
import '../services/live_metrics_service.dart';
import '../services/material_service.dart';
import '../services/point_cloud_service.dart';
import '../widgets/mesh_painter.dart';

/// EigenGuard 3D Digital Twin — Universal (har qanday material uchun).
///
/// Point Cloud (Delaunay + alpha-shape) → Mesh3D → 4 ta render rejim.
/// Live data LiveMetricsService dan, material rangi MaterialService dan.
/// Hot-spot zonalar avtomatik aniqlanadi va alohida belgilanadi.
class DigitalTwinScreen extends StatefulWidget {
  final Function(int)? onTabRequested;
  const DigitalTwinScreen({super.key, this.onTabRequested});

  @override
  State<DigitalTwinScreen> createState() => _DigitalTwinScreenState();
}

class _DigitalTwinScreenState extends State<DigitalTwinScreen>
    with TickerProviderStateMixin {
  // ── Render holat ──────────────────────────────────────────────────────────
  MeshRenderMode _renderMode = MeshRenderMode.xray;
  Mesh3D _mesh = Mesh3D.empty();
  MeshVertex? _selectedHotspot;

  // Pan / Zoom / Rotate
  double _scale = 1.0;
  double _rx = -0.3; // boshlang'ich biroz qiya
  double _ry = 0.4;
  Offset _lastFocal = Offset.zero;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  Timer? _meshRefreshTimer;

  // Servislar
  final PointCloudService _pc = PointCloudService();
  final LiveMetricsService _live = LiveMetricsService();
  final MaterialService _material = MaterialService();

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim =
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);

    // Mesh ni har 2 sek qayta qurish (point cloud o'zgarib turishi mumkin)
    _rebuildMesh();
    _meshRefreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) _rebuildMesh();
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _meshRefreshTimer?.cancel();
    super.dispose();
  }

  /// Point cloud dan mesh qayta qurish (Delaunay + alpha-shape)
  void _rebuildMesh() {
    final mesh = _pc.buildMesh();
    if (!mounted) return;
    setState(() {
      _mesh = mesh;
      // Tanlangan hot-spot endi mavjud bo'lmasa — tozalash
      if (_selectedHotspot != null &&
          !_mesh.hotspots.any((h) =>
              h.x == _selectedHotspot!.x &&
              h.y == _selectedHotspot!.y &&
              h.z == _selectedHotspot!.z)) {
        _selectedHotspot = null;
      }
    });
  }

  Future<void> _exportToCsv() async {
    final points = _pc.points;
    if (points.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Bosh ma\'lumot saqlanmaydi! Iltimos, oldin skanerlang.'),
        backgroundColor: AppTheme.warning,
      ));
      return;
    }
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return;

      final ts = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'eigenguard_scan_$ts.csv';
      final file = File('${dir.path}/$fileName');

      final sb = StringBuffer();
      sb.writeln('X,Y,Z,Intensity');
      for (final p in points) {
        sb.writeln('${p.x},${p.y},${p.z},${p.intensity}');
      }

      await file.writeAsString(sb.toString());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Saqlandi: $fileName'),
        backgroundColor: AppTheme.success,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Xatolik: $e'),
        backgroundColor: AppTheme.danger,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: _mesh.isEmpty
                  ? _buildEmptyState()
                  : _buildMainView(),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TOP BAR
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildTopBar() {
    return ValueListenableBuilder<MaterialProfile>(
      valueListenable: _material.current,
      builder: (context, mat, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.surface.withValues(alpha: 0.9),
            border: Border(
              bottom: BorderSide(
                color: mat.color.withValues(alpha: 0.25),
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: mat.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(mat.icon, color: mat.color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '3D DIGITAL TWIN',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                    Text(
                      '${mat.displayName} · ${_mesh.stats}',
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _rebuildMesh,
                tooltip: 'Mesh qayta qurish',
                icon: Icon(
                  Icons.refresh,
                  color: mat.color,
                  size: 20,
                ),
              ),
              IconButton(
                onPressed: _exportToCsv,
                tooltip: 'CSV eksport',
                icon: Icon(
                  Icons.download,
                  color: mat.color,
                  size: 20,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // MAIN VIEW — Mesh viewer + render mode chips + live data panel
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildMainView() {
    return Column(
      children: [
        _buildRenderModeBar(),
        Expanded(child: _build3DViewer()),
        _buildHotspotList(),
        _buildLiveDataPanel(),
      ],
    );
  }

  Widget _buildRenderModeBar() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: MeshRenderMode.values.map((m) {
          final isActive = m == _renderMode;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
              child: GestureDetector(
                onTap: () => setState(() => _renderMode = m),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppTheme.primary.withValues(alpha: 0.2)
                        : AppTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isActive
                          ? AppTheme.primary
                          : AppTheme.surfaceLight,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      m.label,
                      style: TextStyle(
                        color: isActive
                            ? AppTheme.primary
                            : AppTheme.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _build3DViewer() {
    return ValueListenableBuilder<MaterialProfile>(
      valueListenable: _material.current,
      builder: (context, mat, _) {
        return Container(
          color: const Color(0xFF050810),
          child: GestureDetector(
            onScaleStart: (d) => _lastFocal = d.localFocalPoint,
            onScaleUpdate: (d) {
              setState(() {
                if (d.scale != 1.0) {
                  _scale = (_scale * d.scale).clamp(0.3, 6.0);
                } else {
                  final delta = d.localFocalPoint - _lastFocal;
                  _rx -= delta.dy * 0.008;
                  _ry += delta.dx * 0.008;
                }
                _lastFocal = d.localFocalPoint;
              });
            },
            child: AnimatedBuilder(
              animation: _pulseAnim,
              builder: (context, _) {
                return CustomPaint(
                  size: Size.infinite,
                  painter: MeshPainter(
                    mesh: _mesh,
                    mode: _renderMode,
                    baseColor: mat.color,
                    rotationX: _rx,
                    rotationY: _ry,
                    scale: _scale * 1.6,
                    hotspotPulse: _pulseAnim.value,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildHotspotList() {
    if (_mesh.hotspots.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          top: BorderSide(color: AppTheme.danger.withValues(alpha: 0.25)),
        ),
      ),
      child: Row(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'KRITIK ZONALAR',
                style: TextStyle(
                  color: AppTheme.danger,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              Text(
                '${_mesh.hotspots.length} ta',
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _mesh.hotspots.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) => _buildHotspotChip(_mesh.hotspots[i], i),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHotspotChip(MeshVertex hs, int index) {
    final isSelected = _selectedHotspot != null &&
        _selectedHotspot!.x == hs.x &&
        _selectedHotspot!.y == hs.y &&
        _selectedHotspot!.z == hs.z;
    return GestureDetector(
      onTap: () => setState(() => _selectedHotspot = hs),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.danger.withValues(alpha: 0.25)
              : AppTheme.danger.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? AppTheme.danger
                : AppTheme.danger.withValues(alpha: 0.4),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppTheme.danger, size: 14),
            const SizedBox(width: 4),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HZ-${index + 1}',
                  style: const TextStyle(
                    color: AppTheme.danger,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '${(hs.intensity * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveDataPanel() {
    return ValueListenableBuilder<LiveMetrics>(
      valueListenable: _live.metrics,
      builder: (context, m, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            border: Border(
              top: BorderSide(
                color: AppTheme.primary.withValues(alpha: 0.15),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: m.isMonitoring
                          ? AppTheme.success
                          : AppTheme.textMuted,
                      boxShadow: m.isMonitoring
                          ? [
                              BoxShadow(
                                color: AppTheme.success.withValues(alpha: 0.6),
                                blurRadius: 6,
                              )
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    m.isMonitoring ? 'JONLI MA\'LUMOT' : 'OXIRGI HOLAT',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  if (m.objectLabel != null)
                    Text(
                      m.objectLabel!.toUpperCase(),
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _miniMetric(
                      'AMPLITUDA',
                      '${m.amplitudeMm.toStringAsFixed(2)} mm',
                      _ampColor(m.amplitudeMm, m.criticalAmpMm),
                    ),
                  ),
                  Expanded(
                    child: _miniMetric(
                      'CHASTOTA',
                      '${m.frequencyHz.toStringAsFixed(0)} Hz',
                      AppTheme.success,
                    ),
                  ),
                  Expanded(
                    child: _miniMetric(
                      'XAVF',
                      '${m.riskPercent.toStringAsFixed(0)}%',
                      _riskColor(m.riskPercent),
                    ),
                  ),
                  Expanded(
                    child: _miniMetric(
                      'KRITIKGACHA',
                      m.rulLabel,
                      m.hoursToCritical > 0 && m.hoursToCritical < 24
                          ? AppTheme.danger
                          : AppTheme.primary,
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

  Widget _miniMetric(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Color _ampColor(double amp, double critical) {
    if (critical <= 0) return AppTheme.primary;
    final r = amp / critical;
    if (r > 0.85) return AppTheme.danger;
    if (r > 0.5) return AppTheme.warning;
    return AppTheme.success;
  }

  Color _riskColor(double r) {
    if (r > 75) return AppTheme.danger;
    if (r > 50) return AppTheme.warning;
    return AppTheme.success;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BOTTOM BAR — Pan/zoom hint
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.background,
        border: Border(
          top: BorderSide(
              color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: const [
          _GestureHint(icon: Icons.pinch, label: 'ZOOM'),
          _GestureHint(icon: Icons.pan_tool_alt, label: 'AYLANTIRISH'),
          _GestureHint(icon: Icons.touch_app, label: 'HOT-SPOT'),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // EMPTY STATE — hech narsa skan qilinmagan
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildEmptyState() {
    return Container(
      color: const Color(0xFF050810),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.3),
                  width: 2,
                ),
                color: AppTheme.primary.withValues(alpha: 0.05),
              ),
              child: Icon(
                Icons.view_in_ar_rounded,
                size: 56,
                color: AppTheme.primary.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '3D Maket Yaratilmagan',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Hozircha 3D raqamli egizak mavjud emas.\n'
                'Dashboard orqali obyektni skanerlang —\n'
                'natijalar avtomatik bu yerga yuklanadi.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 32),
            GestureDetector(
              onTap: () => widget.onTabRequested?.call(0),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.4),
                  ),
                  borderRadius: BorderRadius.circular(8),
                  color: AppTheme.primary.withValues(alpha: 0.08),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.radar_rounded,
                        color: AppTheme.primary, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Skanerlashga o\'tish',
                      style: TextStyle(
                        color: AppTheme.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GestureHint extends StatelessWidget {
  final IconData icon;
  final String label;
  const _GestureHint({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppTheme.textMuted, size: 12),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}
