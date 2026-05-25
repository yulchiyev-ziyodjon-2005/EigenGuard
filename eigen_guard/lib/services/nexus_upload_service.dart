import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/measurement_record.dart';
import 'database_service.dart';
import 'nexus_auth_service.dart';
import 'settings_service.dart';

/// Sprint 16 — Nexus Backend Uploader (skeleton).
///
/// **Vazifa:** SQLite'da `sync_status='pending'` bo'lgan o'lchov yozuvlarini
/// Nexus backend HTTP endpoint'iga JSON sifatida POST qiladi. Muvaffaqiyatli
/// bo'lsa `markRecordSynced(nexusId)`, xato bo'lsa `markRecordSyncFailed()`.
///
/// **Skeleton holati:** dummy endpoint chaqiriladi (Settings → Nexus Endpoint).
/// Bo'sh endpoint → uploader o'chirilgan holatda turadi (no-op).
///
/// **Threading:** Periodic Timer + http async — main thread bloklanmaydi.
/// `ValueNotifier` orqali UI status'ni kuzatadi.
enum NexusSyncState { idle, syncing, success, failed, disabled }

class NexusUploadService {
  static final NexusUploadService _instance = NexusUploadService._();
  factory NexusUploadService() => _instance;
  NexusUploadService._();

  final DatabaseService _db = DatabaseService();

  // ── Public observables ──────────────────────────────────────────────
  final ValueNotifier<NexusSyncState> state =
      ValueNotifier(NexusSyncState.idle);
  final ValueNotifier<int> pendingCount = ValueNotifier(0);
  final ValueNotifier<int> totalSynced = ValueNotifier(0);
  final ValueNotifier<int> totalFailed = ValueNotifier(0);
  final ValueNotifier<DateTime?> lastSyncAt = ValueNotifier(null);
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  // ── Internal ────────────────────────────────────────────────────────
  Timer? _timer;
  bool _inFlight = false;
  http.Client? _httpClient;
  static const Duration _requestTimeout = Duration(seconds: 10);
  static const int _batchLimit = 50;

  // ────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ────────────────────────────────────────────────────────────────────

  /// Periodic upload boshlash (default har 5 daqiqa).
  /// Sprint 18 dan keyin: agar `NexusAuthService` login bo'lsa — uning
  /// `baseUrl` + JWT ishlatiladi. Aks holda eski `nexusEndpoint` Settings'dan.
  void start({Duration period = const Duration(minutes: 5)}) {
    stop();
    _httpClient = http.Client();
    refreshState();
    if (_endpoint().isEmpty) return;
    _timer = Timer.periodic(period, (_) => syncNow());
    // Darhol bir marta urinib ko'ramiz
    unawaited(syncNow());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _httpClient?.close();
    _httpClient = null;
  }

  /// Sozlamalar o'zgargach yoki endpoint o'zgargach UI dan qayta sozlash uchun.
  /// Periodic timer'ni qaytadan ishga tushiradi (yangi period bilan).
  void restart({Duration period = const Duration(minutes: 5)}) {
    start(period: period);
  }

  /// Qo'lda sinxronizatsiya (Settings ekranida "Sync now" tugmasi uchun).
  Future<void> syncNow() async {
    if (_inFlight) return;
    final endpoint = _endpoint();
    if (endpoint.isEmpty) {
      state.value = NexusSyncState.disabled;
      lastError.value = 'Endpoint sozlanmagan';
      return;
    }
    _inFlight = true;
    state.value = NexusSyncState.syncing;
    int ok = 0;
    int fail = 0;
    try {
      final pending = await _db.getPendingSyncRecords(limit: _batchLimit);
      pendingCount.value = pending.length;
      if (pending.isEmpty) {
        state.value = NexusSyncState.success;
        lastSyncAt.value = DateTime.now();
        lastError.value = null;
        return;
      }
      // Sprint 18 — NexusAuthService JWT, agar login bo'lmagan bo'lsa Settings token
      final auth = NexusAuthService();
      final tenant = auth.tenantSubdomain ??
          (SettingsService().nexusTenantSubdomain.trim().isEmpty
              ? null
              : SettingsService().nexusTenantSubdomain.trim());
      final bearer = auth.token ?? SettingsService().nexusAuthToken.trim();
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'User-Agent': 'EigenGuard-Mobile/1.0',
        if (bearer.isNotEmpty) 'Authorization': 'Bearer $bearer',
        if (tenant != null) 'X-EigenGuard-Tenant': tenant,
      };
      final client = _httpClient ?? http.Client();
      for (final rec in pending) {
        final id = rec.id;
        if (id == null) continue;
        try {
          final resp = await client
              .post(
                Uri.parse(endpoint),
                headers: headers,
                body: jsonEncode(_recordToJson(rec)),
              )
              .timeout(_requestTimeout);
          if (resp.statusCode >= 200 && resp.statusCode < 300) {
            final nexusId = _extractNexusId(resp.body);
            await _db.markRecordSynced(id, nexusId: nexusId);
            ok++;
          } else {
            await _db.markRecordSyncFailed(id);
            fail++;
          }
        } catch (e) {
          await _db.markRecordSyncFailed(id);
          fail++;
          debugPrint('[Nexus] upload err id=$id: $e');
        }
      }
      totalSynced.value += ok;
      totalFailed.value += fail;
      lastSyncAt.value = DateTime.now();
      state.value = fail == 0 ? NexusSyncState.success : NexusSyncState.failed;
      lastError.value =
          fail == 0 ? null : '$fail / ${pending.length} ta yozuv xato';
    } catch (e) {
      state.value = NexusSyncState.failed;
      lastError.value = e.toString();
    } finally {
      _inFlight = false;
      await refreshState();
    }
  }

  /// Joriy pending soni va endpoint holatini yangilash (UI badge uchun).
  Future<void> refreshState() async {
    if (_endpoint().isEmpty) {
      state.value = NexusSyncState.disabled;
      pendingCount.value = 0;
      return;
    }
    try {
      final pending = await _db.getPendingSyncRecords(limit: 1000);
      pendingCount.value = pending.length;
    } catch (_) {}
  }

  /// HUD chip yoki status badge uchun yorliq.
  String get statusLabel {
    switch (state.value) {
      case NexusSyncState.idle:
        return 'NEXUS IDLE';
      case NexusSyncState.syncing:
        return 'SYNCING...';
      case NexusSyncState.success:
        return 'NEXUS OK';
      case NexusSyncState.failed:
        return 'NEXUS ERR';
      case NexusSyncState.disabled:
        return 'NEXUS —';
    }
  }

  void dispose() {
    stop();
    state.dispose();
    pendingCount.dispose();
    totalSynced.dispose();
    totalFailed.dispose();
    lastSyncAt.dispose();
    lastError.dispose();
  }

  // ────────────────────────────────────────────────────────────────────
  // INTERNAL
  // ────────────────────────────────────────────────────────────────────

  /// Sprint 18 prioriteti:
  /// 1. NexusAuthService.baseUrl mavjud bo'lsa → `<base>/api/v1/measurements`
  /// 2. SettingsService.nexusBaseUrl bo'sh emas → `<base>/api/v1/measurements`
  /// 3. Eski Settings.nexusEndpoint (DEPRECATED) — to'liq URL sifatida
  String _endpoint() {
    final auth = NexusAuthService();
    final authBase = auth.baseUrl;
    if (authBase != null && authBase.isNotEmpty) {
      return '$authBase/api/v1/measurements';
    }
    final settingsBase = SettingsService().nexusBaseUrl.trim();
    if (settingsBase.isNotEmpty) {
      return '${settingsBase.replaceAll(RegExp(r'/+\$'), '')}/api/v1/measurements';
    }
    return SettingsService().nexusEndpoint.trim();
  }

  String? _extractNexusId(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final candidate = decoded['id'] ?? decoded['nexus_id'] ?? decoded['_id'];
        if (candidate is String) return candidate;
        if (candidate != null) return candidate.toString();
      }
    } catch (_) {}
    return null;
  }

  Map<String, dynamic> _recordToJson(MeasurementRecord r) {
    return {
      'local_id': r.id,
      'timestamp': r.timestamp.toIso8601String(),
      'risk_percent': r.riskPercent,
      'frequency_hz': r.frequency,
      'amplitude_mm': r.amplitude,
      'risk_level': r.riskLevel,
      'frame_count': r.frameCount,
      'duration_seconds': r.durationSeconds,
      if (r.objectLabel != null) 'object_label': r.objectLabel,
      if (r.materialId != null) 'material_id': r.materialId,
      if (r.latitude != null) 'lat': r.latitude,
      if (r.longitude != null) 'lng': r.longitude,
      if (r.locationAccuracyM != null) 'accuracy_m': r.locationAccuracyM,
      if (r.magneticFieldUt != null) 'magnetic_field_ut': r.magneticFieldUt,
      if (r.magneticAnomaly != null) 'magnetic_anomaly': r.magneticAnomaly,
      if (r.predictionA != null) 'prediction_a': r.predictionA,
      if (r.predictionB != null) 'prediction_b': r.predictionB,
      if (r.predictionC != null) 'prediction_c': r.predictionC,
      if (r.hoursToCritical != null) 'hours_to_critical': r.hoursToCritical,
      if (r.hotspotsJson != null) 'hotspots': r.hotspotsJson,
      if (r.deviceId != null) 'device_id': r.deviceId,
      'source': r.source.wireName,
      if (r.fusionConfidence != null) 'fusion_confidence': r.fusionConfidence,
    };
  }
}
