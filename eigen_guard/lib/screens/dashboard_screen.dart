import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../ffi/native_engine.dart';
import '../models/measurement_record.dart';
import '../services/database_service.dart';
import '../services/camera_service.dart';
import '../services/imu_service.dart';
import '../services/audio_service.dart';
import '../services/vision_ai_service.dart';
import '../services/depth_service.dart';
import '../services/ai_assistant_service.dart';
import '../services/point_cloud_service.dart';
import 'dart:convert';
import '../services/live_metrics_service.dart';
import '../services/material_service.dart';
import '../services/magnetometer_service.dart';
import '../services/flash_service.dart';
import '../services/geo_location_service.dart';
import '../services/scan_archive_service.dart';
import '../services/mqtt_ingest_service.dart';
import '../services/sensor_fusion_arbiter.dart';
import '../services/mobile_command_bus.dart';
import '../widgets/acoustic_probe_widget.dart';
import '../widgets/ble_picker_widget.dart';
import '../widgets/camera_preview_widget.dart';
import '../widgets/material_selector_widget.dart';
import '../widgets/vibration_probe_widget.dart';
import 'ai_chat_screen.dart';

/// DashboardScreen — 100% Kamera arxitekturasi va Glassmorphism HUD (Sprint 7)
/// Uskuna tebranishini mm da hisoblash hamda Akustik anomaliyalarni ekranda aks ettirish.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  NativeEngine? _engine;
  SplineProcessor? _spline;
  CameraPipelineWrapper? _pipeline;
  bool _engineReady = false;

  final CameraService _camera = CameraService();
  final ImuService _imu = ImuService();
  final AudioService _audio = AudioService();
  final VisionAiService _vision = VisionAiService();
  final DepthService _depth = DepthService();
  final AiAssistantService _aiAssistant = AiAssistantService();
  final PointCloudService _pointCloud = PointCloudService();
  final LiveMetricsService _live = LiveMetricsService();
  final MaterialService _material = MaterialService();
  final MagnetometerService _magnet = MagnetometerService();
  final FlashService _flash = FlashService();
  final GeoLocationService _geo = GeoLocationService();
  final ScanArchiveService _scanArchive = ScanArchiveService();
  // Sprint 15 — B2G ekotizimi: MQTT bridge + True Sensor Fusion
  final MqttIngestService _mqtt = MqttIngestService();
  final SensorFusionArbiter _arbiter = SensorFusionArbiter();
  // Sprint 18 — Nexus'dan kelgan buyruqlar uchun command bus
  final MobileCommandBus _commandBus = MobileCommandBus();
  int _lastStartTrigger = 0;
  int _lastStopTrigger = 0;
  int _lastSnapshotTrigger = 0;
  GeoLocation? _scanStartLocation;

  // Phase 7 — Audio sliding window (live spektr uchun)
  final List<double> _audioWindow = []; // ~4096 sample
  static const int _audioWindowSize = 4096;
  DateTime _lastSpectrumPush = DateTime.fromMillisecondsSinceEpoch(0);
  Float64List _lastSpectrumSnapshot = Float64List(0);
  double _lastSpectrumRate = 44100.0;
  FftProcessorWrapper? _fft;
  ApproxProcessorWrapper? _approx;
  Uint8List? _prevFrame;

  bool _isMonitoring = false;
  double _riskPercent = 0.0;
  double _currentFreq = 0.0;
  double _currentAmplitude = 0.0; // Piksel siljishida
  double _currentAmplitudeMm = 0.0; // DaptService orqali haqiqiy o'lchov mm.

  int _frameCount = 0;
  final DatabaseService _db = DatabaseService();

  double _currentDx = 0.0;
  double _currentDy = 0.0;

  final List<double> _rawTime = [];
  final List<double> _rawAmplitude = [];

  // §6.4 — Predictive (RUL) bufferi: vaqt SOATda, amplituda MM da.
  // Real wall-clock asosida — fps yoki throttle o'zgarsa ham bashorat to'g'ri qoladi.
  DateTime? _monitorStart;
  final List<double> _predTimeH = [];
  final List<double> _predAmpMm = [];
  static const int _predMaxSamples = 600; // ≈ 1 daq @ 10 fps yoki ~10 daq @ 1 Hz

  // So'nggi bashorat — HUD da ko'rsatish uchun
  PredictionResult? _lastPrediction;
  Timer? _predictionTimer;

  // VLA Trigger (UI ni izolyatsiya qilish)
  final ValueNotifier<int> _frameTrigger = ValueNotifier<int>(0);

  // AR Box chizish uchun qisqa animatsiya
  bool _showRedAlert = false;
  bool _aiTriggered = false;
  
  // Tap-to-Lock o'zgaruvchilari
  Offset? _lockedCenter;
  DetectedObject? _activeObject;
  int _lastVisionUpdate = -1;

  @override
  void initState() {
    super.initState();
    _initEngine();
    // Sprint 18 — Nexus buyruqlarini tinglash
    _commandBus.startScanTrigger.addListener(_onStartScanCommand);
    _commandBus.stopScanTrigger.addListener(_onStopScanCommand);
    _commandBus.snapshotTrigger.addListener(_onSnapshotCommand);
    _commandBus.notifyEvent.addListener(_onNotifyEvent);
    _lastStartTrigger = _commandBus.startScanTrigger.value;
    _lastStopTrigger = _commandBus.stopScanTrigger.value;
    _lastSnapshotTrigger = _commandBus.snapshotTrigger.value;
  }

  void _onStartScanCommand() {
    if (_commandBus.startScanTrigger.value == _lastStartTrigger) return;
    _lastStartTrigger = _commandBus.startScanTrigger.value;
    if (!_isMonitoring && _engineReady) {
      _startMonitoring();
      _showCommandToast('Nexus: skanerlash boshlandi', AppTheme.success);
    }
  }

  void _onStopScanCommand() {
    if (_commandBus.stopScanTrigger.value == _lastStopTrigger) return;
    _lastStopTrigger = _commandBus.stopScanTrigger.value;
    if (_isMonitoring) {
      _stopMonitoring();
      _showCommandToast('Nexus: skanerlash to\'xtatildi', AppTheme.warning);
    }
  }

  void _onSnapshotCommand() {
    if (_commandBus.snapshotTrigger.value == _lastSnapshotTrigger) return;
    _lastSnapshotTrigger = _commandBus.snapshotTrigger.value;
    if (_isMonitoring) {
      _saveMeasurement();
      _showCommandToast('Nexus: snapshot saqlandi', AppTheme.primary);
    } else {
      _showCommandToast(
          'Snapshot uchun avval skanerlash boshlanishi kerak', AppTheme.warning);
    }
  }

  void _onNotifyEvent() {
    final ev = _commandBus.notifyEvent.value;
    if (ev == null) return;
    final color = ev.isCritical ? AppTheme.danger : AppTheme.primary;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  ev.isCritical
                      ? Icons.warning_amber_rounded
                      : Icons.notifications_active,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ev.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            if (ev.message.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                ev.message,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: ev.isCritical ? 6 : 3),
      ),
    );
  }

  void _showCommandToast(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.cloud_done, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message,
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _initEngine() {
    try {
      _engine = NativeEngine();
      _approx = _engine!.createApproxProcessor();
      _engineReady = true;
      // Magnetometer doimiy ishlaydi (HUD indikatori uchun ham, monitoring
      // davrida ham). Fon hisoblanadi — UI bloklamaydi.
      _magnet.start();
      // Sprint 15 — Edge bridge + Fusion arbiter ni ishga tushirish.
      // ESP32 fizik ulanmaguncha mock MQTT stream synthetic readings beradi
      // (har 100ms da), bu Critical Alert konsensus qoidasini test qilish imkonini beradi.
      _arbiter.bindToMqtt(_mqtt);
      if (!_mqtt.isStreaming) {
        _mqtt.startMockStream();
      }
      _camera.initialize().then((_) {
        if (mounted) {
          // Doimiy Kamera (Viewfinder) fonini yoqish
          _camera.startStream(
            onFrameData: _processCameraFrame,
            onRawImage: (image, orientation) {
              _vision.processCameraImage(image, orientation);
            },
          );
          setState(() {});
        }
      });
      _vision.initialize();
      _audio.initialize();
    } catch (e) {
      _engineReady = false;
    }
    setState(() {});
  }

  /// §6.4 — Parabolik least-squares fit asosida kritik chegaragacha qolgan
  /// vaqtni va tendentsiya yo'nalishini hisoblaydi. Har 1 sekundda chaqiriladi.
  /// `y_limit` joriy material profilidan olinadi (po'lat 2.8 mm, beton 0.5 mm, ...).
  void _runPrediction() {
    if (_approx == null || _predTimeH.length < 3) return;
    final t = Float64List.fromList(_predTimeH);
    final y = Float64List.fromList(_predAmpMm);
    _lastPrediction =
        _approx!.predict(t, y, _material.current.value.criticalAmplitudeMm);
  }

  void _toggleMonitoring() {
    _isMonitoring ? _stopMonitoring() : _startMonitoring();
  }

  void _startMonitoring() {
    if (!_engineReady || !_camera.isInitialized) return;
    _frameCount = 0;
    _isMonitoring = true;
    _aiTriggered = false;

    _rawAmplitude.clear();
    _predTimeH.clear();
    _predAmpMm.clear();
    _audioWindow.clear();
    _lastSpectrumSnapshot = Float64List(0);
    _lastPrediction = null;
    _monitorStart = DateTime.now();
    _fft ??= _engine!.createFftProcessor();

    // Skan boshlanishida joylashuvni olamiz (fon — bloklamaydi)
    _scanStartLocation = null;
    // ignore: unawaited_futures
    _geo.getCurrent().then((loc) {
      if (mounted) setState(() => _scanStartLocation = loc);
    });

    _imu.startListening();
    _audio.startStream(onFrameData: _processAudioFrame);

    // Point cloud qatlashni boshlash
    _pointCloud.startScanning();

    // §6.4 Predictive engine — har 1 sekundda parabolik bashorat
    _predictionTimer?.cancel();
    _predictionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _runPrediction();
    });
    setState(() {});
  }

  void _stopMonitoring() {
    _imu.stopListening();
    _audio.stopStream();
    // Kamera stream davom etaveradi (Viewfinder fon o'chmasligi uchun)
    _isMonitoring = false;

    // Skanerlash (Point Cloud) yig'ishni pauza qilish
    _pointCloud.pauseScanning();

    _predictionTimer?.cancel();
    _predictionTimer = null;

    _saveMeasurement();
    setState(() {});
  }

  void _saveAndFinishScan() {
    _stopMonitoring(); // Tebranishlarni arxivga olish
    
    // 3D Twin tabiga o'tish so'rovi (yoki SnackBar orqali qo'llanma berish)
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Obyekt nusxasi xotiraga olindi. Pastdagi menudan '3D Twin' ga o'ting."),
          backgroundColor: AppTheme.success,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _saveMeasurement() async {
    final magReading = _magnet.reading.value;
    final pred = _lastPrediction;
    // Sprint 15 — Fusion verdiktidan kelib chiqib source/deviceId/confidence
    final fusionState = _arbiter.verdict.value;
    final source = switch (fusionState.verdict) {
      FusionVerdict.consensusCritical => MeasurementSource.fused,
      FusionVerdict.hardwareOnly => MeasurementSource.edge,
      _ => MeasurementSource.mobile,
    };
    final edgeDeviceId = fusionState.matchedEdgeReading?.deviceId;
    final fusionConf = source == MeasurementSource.fused
        ? fusionState.confidence
        : null;

    // Hot-spotlar JSON ga (avval point cloud dan)
    final hotspots = _pointCloud.getCriticalHotspots();
    final hotspotsJson = hotspots.isEmpty
        ? null
        : jsonEncode(hotspots
            .map((p) => {
                  'x': p.x,
                  'y': p.y,
                  'z': p.z,
                  'intensity': p.intensity,
                })
            .toList());

    final record = MeasurementRecord(
      timestamp: DateTime.now(),
      riskPercent: _riskPercent,
      frequency: _currentFreq,
      amplitude: _currentAmplitudeMm,
      splineError: 0.0,
      frameCount: _frameCount,
      durationSeconds: _frameCount ~/ 30,
      riskLevel: MeasurementRecord.calculateRiskLevel(_riskPercent),
      objectLabel: _activeObject?.label,
      materialId: _material.current.value.id,
      latitude: _scanStartLocation?.latitude,
      longitude: _scanStartLocation?.longitude,
      locationAccuracyM: _scanStartLocation?.accuracyMeters,
      magneticFieldUt: magReading.magnitudeUt,
      magneticAnomaly: magReading.isAnomalous,
      // Phase 7 — to'liq tarix bufferlari
      amplitudeSeriesBlob: _predAmpMm.isEmpty
          ? null
          : MeasurementRecord.float64ListToBytes(_predAmpMm),
      fftSpectrumBlob: _lastSpectrumSnapshot.isEmpty
          ? null
          : _lastSpectrumSnapshot.buffer.asUint8List(
              _lastSpectrumSnapshot.offsetInBytes,
              _lastSpectrumSnapshot.lengthInBytes,
            ),
      fftSampleRate: _lastSpectrumSnapshot.isEmpty ? null : _lastSpectrumRate,
      predictionA: pred?.a,
      predictionB: pred?.b,
      predictionC: pred?.c,
      hoursToCritical: pred?.hoursToCritical,
      hotspotsJson: hotspotsJson,
      // Sprint 15 — B2G sync layer
      deviceId: edgeDeviceId,
      source: source,
      syncStatus: SyncStatus.pending,
      fusionConfidence: fusionConf,
    );
    final id = await _db.insertMeasurement(record);

    // Point cloud arxiviga saqlash (source/deviceId bilan birga)
    if (id > 0 && _pointCloud.points.isNotEmpty) {
      await _scanArchive.savePointCloud(
        id,
        List.of(_pointCloud.points),
        deviceId: edgeDeviceId,
        source: source.wireName,
      );
    }
  }

  void _processAudioFrame(Uint8List data) {
    if (!_isMonitoring || _fft == null || data.length < 2) return;
    try {
      final int16List =
          data.buffer.asInt16List(data.offsetInBytes, data.lengthInBytes ~/ 2);
      final floatList = Float64List(int16List.length);
      for (int i = 0; i < int16List.length; i++) {
        floatList[i] = int16List[i] / 32768.0;
      }
      final freq = _fft!.computeDominant(floatList, 44100.0);
      if (freq > 20.0 && freq < 20000.0) {
        // Tovushning o'rtachasini olamiz
        _currentFreq = (_currentFreq * 0.8) + (freq * 0.2);
      }

      // Phase 7 — sliding window audio sample (4096 ta)
      for (final v in floatList) {
        _audioWindow.add(v);
      }
      while (_audioWindow.length > _audioWindowSize) {
        _audioWindow.removeAt(0);
      }

      // Har 500ms da spektr hisoblab Monitoring LIVE tabiga yo'naltirish
      final now = DateTime.now();
      if (now.difference(_lastSpectrumPush).inMilliseconds >= 500 &&
          _audioWindow.length >= 1024) {
        _lastSpectrumPush = now;
        final spec = _fft!.computeSpectrum(
            Float64List.fromList(_audioWindow), 44100.0);
        _lastSpectrumSnapshot = spec.magnitudes;
        _lastSpectrumRate = 44100.0;
        _live.pushSpectrum(spec.magnitudes, 44100.0);
      }
    } catch (_) {}
  }

  void _processCameraFrame(Uint8List frame, int width, int height) {
    try {
      _pipeline ??= _engine!.createCameraPipeline(width, height);

      if (_prevFrame != null) {
        // --- Tap-to-Lock obyektini yangilash (Yangi YOLO javob kutish) ---
        bool isNewYoloFrame = _lastVisionUpdate != _vision.updateCount;
        
        if (isNewYoloFrame) {
          _lastVisionUpdate = _vision.updateCount;

          if (_lockedCenter != null && _vision.currentObjects.isNotEmpty) {
            // Eng yaqin obyektni topish
            DetectedObject? closest;
            double minDistance = double.infinity;
            for (var obj in _vision.currentObjects) {
              final center = obj.box.center;
              final dist = (center - _lockedCenter!).distance;
              if (dist < minDistance) {
                minDistance = dist;
                closest = obj;
              }
            }
            if (minDistance < 150) { // Tolerans biroz kattalashtirildi
              _activeObject = closest;
              _lockedCenter = closest!.box.center;
            } else {
              _activeObject = null;
            }
          } else if (_vision.currentObjects.isNotEmpty) {
            _activeObject = _vision.currentObjects.first; // Avtomatik 1-obj
          } else {
            _activeObject = null;
          }

          // Material auto-infer (foydalanuvchi qo'lda tanlamagan bo'lsa)
          _material.inferFromYoloLabel(_activeObject?.rawLabel);
        }

        final dx = Float32List(1);
        final dy = Float32List(1);

        final imuData = _imu.getRecentImuData();
        double imuDx = imuData[3] * 10.0;
        double imuDy = imuData[4] * 10.0;

        // Faol obyekt bo'yicha ROI ni C++ ga uzatamiz
        int roiX = 0, roiY = 0, roiW = 0, roiH = 0;
        if (_activeObject != null) {
          final box = _activeObject!.box;
          roiX = box.left.toInt();
          roiY = box.top.toInt();
          roiW = box.width.toInt();
          roiH = box.height.toInt();
        }

        // C++ Bridge - Optical Flow + Kalman
        final mag = _pipeline!.processFrame(
            _prevFrame!, frame, width, height, roiX, roiY, roiW, roiH, imuDx, imuDy, dx, dy);

        _currentDx = dx[0];
        _currentDy = dy[0];
        
        // Joriy kadrning amplitudasini (mm) avval hisoblaymiz — Point Cloud
        // ga TZ §3.4 Heatmap intensity sifatida uzatish uchun ham, pastdagi
        // _currentAmplitudeMm yangilanishi uchun ham foydalanamiz.
        final freshAmpMm = _depth.convertPixelShiftToMillimeters(
            mag, _activeObject?.box);

        // Skanerlash (Point cloud) jarayoniga uzatamiz — TZ §3.2 + §3.4.
        // Asosiy yo'l: YOLO segmentation poligoni (haqiqiy obyekt shakli).
        // Agar poligon yo'q bo'lsa, Bounding Box fallback ishlaydi.
        // Heatmap intensity = amplituda / 3 mm (3 mm = juda xavfli sanoatda).
        if (_pointCloud.isScanning && _activeObject != null) {
          final heatIntensity = (freshAmpMm / 3.0).clamp(0.0, 1.0);
          _pointCloud.processMovement(
            _currentDx,
            _currentDy,
            _activeObject!.polygons,
            fallbackBox: _activeObject!.box,
            vibrationIntensity: heatIntensity,
          );
        }
        
        // 1-QADAM: 2D Optical Anchor & Anti-Drift Tizimi (Sanoat Gologrammasi)
        if (!isNewYoloFrame && _activeObject != null) {
          // YOLO model hali yangi kadr hisoblamadi (Oraliq kadr 60 FPS)
          // Shuning uchun, obyektni (LOCKED HUD) C++ ga kelgan sof piksel harakati 
          // (dx[0]) va telefonning qo'ldagi titrashi (imu) qadar teskari siljitamiz.
          
          // Izoh: C++ Optical Flow dx[0] = ob'ekt siljishi - imu titrashi bo'lib tozalangan.
          // Haqiqiy ekrandagi global piksel o'zgarishi = dx[0] + imuDx bo'ladi.
          // Masalan, siz telefonni o'ngga qilsangiz, tasvir chapga (-X) yuradi, 
          // ya'ni imuDx musbat bo'lsa, uni biz markazga qat'iy tiklash uchun shuncha piksellarga qo'shamiz.
          final shiftX = (_currentDx + imuDx) * 0.5; // Smooth factor
          final shiftY = (_currentDy + imuDy) * 0.5; 
          
          if (shiftX.abs() > 0.1 || shiftY.abs() > 0.1) {
            final shiftedBox = _activeObject!.box.shift(Offset(shiftX, shiftY));
            final shiftedPolygons = _activeObject!.polygons?.map((p) => p + Offset(shiftX, shiftY)).toList();
            
            _activeObject = DetectedObject(
               label: _activeObject!.label,
               rawLabel: _activeObject!.rawLabel,
               classIndex: _activeObject!.classIndex,
               confidence: _activeObject!.confidence,
               box: shiftedBox,
               polygons: shiftedPolygons,
            );
            _lockedCenter = shiftedBox.center;
          }
        }

        _currentAmplitude = mag;
        _currentAmplitudeMm = freshAmpMm;
        _frameCount++;
        final elapsed = _frameCount / 30.0;

        _rawTime.add(elapsed);
        _rawAmplitude.add(mag);

        if (_rawTime.length > 30) {
          _rawTime.removeAt(0);
          _rawAmplitude.removeAt(0);
        }

        _riskPercent = _calculateRisk();

        // §6.4 Predictive buffer — vaqt SOATda (wall-clock), amplituda MMda.
        if (_isMonitoring && _monitorStart != null) {
          final tH = DateTime.now()
                  .difference(_monitorStart!)
                  .inMilliseconds /
              3600000.0;
          _predTimeH.add(tH);
          _predAmpMm.add(_currentAmplitudeMm);
          if (_predTimeH.length > _predMaxSamples) {
            _predTimeH.removeAt(0);
            _predAmpMm.removeAt(0);
          }

          // Monitoring LIVE tab uchun amplituda oynasi (oxirgi ~5 sek)
          _live.pushAmpWindow(List<double>.from(_predAmpMm));
        }

        // So'nggi bashorat natijasini boshqa servislarga uzatish
        final pred = _lastPrediction;
        final hasPred = pred != null && _predTimeH.length >= 3;
        final trendStr = hasPred
            ? (pred.direction == 1
                ? 'OSHMOQDA'
                : pred.direction == -1
                    ? 'KAMAYMOQDA'
                    : 'BARQAROR')
            : 'BARQAROR';
        final trendDir = hasPred
            ? (pred.direction == 1
                ? TrendDir.rising
                : pred.direction == -1
                    ? TrendDir.falling
                    : TrendDir.stable)
            : TrendDir.stable;
        final rulHours = hasPred ? pred.hoursToCritical : -1.0;

        final mat = _material.current.value;

        // Gemini LLM uchun joriy holatni muntazam yetkazib turish
        _aiAssistant.updateContext(
          _currentAmplitudeMm,
          _currentFreq,
          _riskPercent,
          objectName: _activeObject?.label,
          hoursToCritical: rulHours,
          trend: trendStr,
          materialName: mat.displayName,
          materialTechnical: mat.technicalName,
          failureModes: mat.failureModes,
        );

        // DigitalTwin va boshqa ekranlar uchun live snapshot
        _live.push(
          label: _activeObject?.label,
          risk: _riskPercent,
          freq: _currentFreq,
          ampMm: _currentAmplitudeMm,
          monitoring: _isMonitoring,
          pointCount: _pointCloud.points.length,
          hoursToCritical: rulHours,
          trend: trendDir,
          trendA: hasPred ? pred.a : 0,
          trendB: hasPred ? pred.b : 0,
          trendC: hasPred ? pred.c : 0,
          hasPrediction: hasPred,
          materialId: mat.id,
          materialName: mat.displayName,
          criticalAmpMm: mat.criticalAmplitudeMm,
        );

        // Sprint 15 — TRUE SENSOR FUSION
        // Har frame'da kamera hodisasini arbiter ga push qilamiz.
        // Arbiter ±200ms oyna ichida Edge reading bilan korrelyatsiya qiladi.
        _arbiter.pushCameraEvent(
          amplitudeMm: _currentAmplitudeMm,
          frequencyHz: _currentFreq,
          riskPercent: _riskPercent,
        );
        final fusionState = _arbiter.verdict.value;

        // Critical Alert FAQAT consensusCritical paytida (vision + edge konsensus).
        // cameraOnly / hardwareOnly / falsePositive — alert ko'tarilmaydi
        // (HUD fusion chip orqali holatlar ko'rsatiladi).
        bool isAlert = fusionState.verdict == FusionVerdict.consensusCritical;
        if (isAlert != _showRedAlert) {
          _showRedAlert = isAlert;
          if (isAlert && !_aiTriggered) {
            _aiAssistant.triggerAutoAnalysis(
                _currentAmplitudeMm, _currentFreq, 0.0);
            _aiTriggered = true;
          }
        }

        // System Alert ham faqat fused critical paytda — false positive ni
        // Gemini ga yubormaymiz.
        if (fusionState.verdict == FusionVerdict.consensusCritical &&
            _riskPercent > 80.0) {
          _aiAssistant.triggerSystemAlert(
            riskPercent: _riskPercent,
            frequencyHz: _currentFreq,
            amplitudeMm: _currentAmplitudeMm,
          );
        }

        if (mounted) _frameTrigger.value++;
      } else {
        if (mounted) _frameTrigger.value++;
      }
      _prevFrame = Uint8List.fromList(frame);
    } catch (e) {
      debugPrint('Dashboard frame err: $e');
    }
  }

  /// Material profili asosida xavf foizi.
  /// Po'lat uchun 3 mm kritik bo'lsa, beton uchun 0.5 mm, yog'och uchun 12 mm.
  double _calculateRisk() {
    return _material.current.value
        .calculateRisk(_currentAmplitudeMm, _currentFreq);
  }

  @override
  void dispose() {
    // Sprint 18 — Command bus listener'larini olib tashlash
    _commandBus.startScanTrigger.removeListener(_onStartScanCommand);
    _commandBus.stopScanTrigger.removeListener(_onStopScanCommand);
    _commandBus.snapshotTrigger.removeListener(_onSnapshotCommand);
    _commandBus.notifyEvent.removeListener(_onNotifyEvent);
    _stopMonitoring();
    _predictionTimer?.cancel();
    _magnet.stop();
    _camera.dispose(); // Isolate va ReceivePort larni to'liq tozalash
    _imu.dispose();
    _audio.dispose();
    _vision.dispose();
    _fft?.dispose();
    _approx?.dispose();
    _pipeline?.dispose();
    _spline?.dispose();
    _frameTrigger.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Orqa Fon: 100% Kamera oqimi
          ValueListenableBuilder<int>(
            valueListenable: _frameTrigger,
            builder: (context, _, __) {
              return CameraPreviewWidget(
                dx: _currentDx,
                dy: _currentDy,
                magnitude: _currentAmplitude,
                isMonitoring: _isMonitoring,
                activeBox: _activeObject?.box,
                bracketColor: _material.current.value.color,
              );
            },
          ),

          if (_isMonitoring) ...[
            // Skanerlash vaqtida Point Cloud Gologrammasi
            ValueListenableBuilder<int>(
              valueListenable: _frameTrigger,
              builder: (context, _, __) {
                if (_pointCloud.points.isEmpty) return const SizedBox.shrink();
                return Positioned.fill(
                  child: CustomPaint(
                    painter: _PointCloudPainter(_pointCloud.points),
                  ),
                );
              },
            ),

            // 2. YOLO Instance Segmentation Maskalari (Poligonlar)
            ValueListenableBuilder<int>(
              valueListenable: _frameTrigger,
              builder: (context, _, __) {
                if (_vision.currentObjects.isEmpty) return const SizedBox.shrink();
                return GestureDetector(
                  onTapDown: (details) {
                    // Ekranga bosilganda (Tap-to-Lock) bosilgan obyektni qidirish
                    final RenderBox box = context.findRenderObject() as RenderBox;
                    final Offset localPosition = box.globalToLocal(details.globalPosition);

                    for (var obj in _vision.currentObjects) {
                      if (obj.box.contains(localPosition)) {
                        _lockedCenter = obj.box.center;
                        _activeObject = obj;
                        _frameTrigger.value++;
                        break;
                      }
                    }
                  },
                  child: CustomPaint(
                    painter: _MaskPainter(
                      objects: _vision.currentObjects,
                      activeObject: _activeObject,
                      isAlert: _showRedAlert,
                    ),
                    child: Container(),
                  ),
                );
              },
            ),

            // Yengil gradient (faqat HUD o'qish uchun)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.background.withValues(alpha: 0.5),
                      Colors.transparent,
                      Colors.transparent,
                      AppTheme.background.withValues(alpha: 0.6),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.2, 0.65, 1.0],
                  ),
                ),
              ),
            ),
          ] else ...[
            // Kutish rejimida — yengil gradient (kamera to'liq ko'rinadi)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.background.withValues(alpha: 0.4),
                      Colors.transparent,
                      Colors.transparent,
                      AppTheme.background.withValues(alpha: 0.5),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.15, 0.7, 1.0],
                  ),
                ),
              ),
            ),
          ],

          // 3. HUD Glassmorphism Panel (Tepada)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 20,
            left: 16,
            right: 16,
            child: ValueListenableBuilder<int>(
              valueListenable: _frameTrigger,
              builder: (context, _, __) {
                return _buildGlassHudPanel();
              },
            ),
          ),

          // 4. Boshqaruv Tugmalari (Pastda)
          Positioned(
            bottom: max(MediaQuery.paddingOf(context).bottom + 20, 20),
            left: 20,
            right: 20,
            child: _buildBottomControls(),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassHudPanel() {
    return Container(
      decoration: AppTheme.glassCard,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        children: [
          // Sarlavha
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'SENSOR FUSION HUD',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _isMonitoring
                          ? (_showRedAlert ? AppTheme.danger : AppTheme.success)
                          : AppTheme.textMuted,
                      shape: BoxShape.circle,
                      boxShadow: _isMonitoring
                          ? [
                              BoxShadow(
                                  color: _showRedAlert
                                      ? AppTheme.danger
                                      : AppTheme.success,
                                  blurRadius: 8)
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isMonitoring
                        ? (_showRedAlert ? 'KRITIK XAVF' : 'FAOL')
                        : 'KUTISH',
                    style: TextStyle(
                      color: _isMonitoring
                          ? (_showRedAlert ? AppTheme.danger : AppTheme.success)
                          : AppTheme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Material chip — auto-infer yoki qo'lda tanlash
          const Align(
            alignment: Alignment.centerLeft,
            child: MaterialChip(),
          ),
          const SizedBox(height: 10),
          // Phase 3 — Sensorlar qatori: magnetometer, flash, GPS
          _buildSensorRow(),
          const SizedBox(height: 8),
          // Sprint 15 — Fusion verdikt qatori (Edge + Camera konsensus holati)
          _buildFusionRow(),
          const SizedBox(height: 12),

          // Datchiklar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildHudIndicator(
                title: 'Obyekt (AI)',
                value: _activeObject?.label ?? 'Kutilmoqda',
                metric: '',
                icon: Icons.filter_center_focus,
                color: AppTheme.primary,
              ),
              Container(width: 1, height: 40, color: AppTheme.surfaceLight),
              _buildHudIndicator(
                title: 'Tebranish (LiDAR)',
                value: _currentAmplitudeMm.toStringAsFixed(2),
                metric: 'mm',
                icon: Icons.height,
                color: _showRedAlert ? AppTheme.danger : AppTheme.warning,
              ),
              Container(width: 1, height: 40, color: AppTheme.surfaceLight),
              _buildHudIndicator(
                title: 'Akustika (MFCC)',
                value: _currentFreq.toStringAsFixed(0),
                metric: 'Hz',
                icon: Icons.graphic_eq,
                color: AppTheme.success,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: AppTheme.surfaceLight.withValues(alpha: 0.5), height: 1),
          const SizedBox(height: 14),
          // §6.4 Predictive — Trend va Kritikgacha qolgan vaqt
          _buildPredictionRow(),
        ],
      ),
    );
  }

  /// Phase 3 — Magnetometer, Flash va GPS indikatorlari qatori
  Widget _buildSensorRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Magnetometer chip
        Expanded(
          child: ValueListenableBuilder<MagneticReading>(
            valueListenable: _magnet.reading,
            builder: (context, mag, _) {
              final hasData = mag.magnitudeUt > 0;
              final color = mag.isAnomalous
                  ? AppTheme.danger
                  : (hasData ? AppTheme.success : AppTheme.textMuted);
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      mag.isAnomalous
                          ? Icons.warning_amber_rounded
                          : Icons.explore,
                      color: color,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      hasData
                          ? '${mag.magnitudeUt.toStringAsFixed(0)}µT'
                          : 'MAG —',
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (mag.isAnomalous) ...[
                      const SizedBox(width: 4),
                      Text(
                        'FERROUS',
                        style: TextStyle(
                          color: color,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        // Flash toggle
        ValueListenableBuilder<AppFlashMode>(
          valueListenable: _flash.mode,
          builder: (context, m, _) {
            final color = m == AppFlashMode.off
                ? AppTheme.textMuted
                : AppTheme.warning;
            final label = switch (m) {
              AppFlashMode.off => 'OFF',
              AppFlashMode.auto => 'AUTO',
              AppFlashMode.torch => 'TORCH',
            };
            final icon = switch (m) {
              AppFlashMode.off => Icons.flash_off,
              AppFlashMode.auto => Icons.flash_auto,
              AppFlashMode.torch => Icons.flashlight_on,
            };
            return GestureDetector(
              onTap: () => _flash.cycle(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: color, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        // GPS chip
        ValueListenableBuilder<GeoLocation?>(
          valueListenable: _geo.lastLocation,
          builder: (context, loc, _) {
            final color =
                loc != null ? AppTheme.primary : AppTheme.textMuted;
            return GestureDetector(
              onTap: () => _geo.getCurrent(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      loc != null ? Icons.gps_fixed : Icons.gps_off,
                      color: color,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      loc != null ? 'GPS' : 'GPS —',
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        // BLE chip — Phase 5
        const BleStatusChip(),
      ],
    );
  }

  /// Sprint 15 — True Sensor Fusion verdikt qatori.
  /// Edge (ESP32 MQTT) + kamera optical-flow konsensus holatini ko'rsatadi.
  /// ValueListenableBuilder orqali — main thread bloklanmaydi.
  Widget _buildFusionRow() {
    return ValueListenableBuilder<FusionState>(
      valueListenable: _arbiter.verdict,
      builder: (context, state, _) {
        Color color;
        IconData icon;
        String label;
        switch (state.verdict) {
          case FusionVerdict.consensusCritical:
            color = AppTheme.danger;
            icon = Icons.verified;
            label = 'FUSED CRITICAL';
            break;
          case FusionVerdict.falsePositive:
            color = AppTheme.textMuted;
            icon = Icons.block;
            label = 'FALSE POSITIVE';
            break;
          case FusionVerdict.cameraOnly:
            color = AppTheme.warning;
            icon = Icons.videocam;
            label = 'CAM ONLY';
            break;
          case FusionVerdict.hardwareOnly:
            color = AppTheme.primary;
            icon = Icons.sensors;
            label = 'HW ONLY';
            break;
          case FusionVerdict.idle:
            color = AppTheme.textMuted;
            icon = Icons.merge_type;
            label = 'FUSION IDLE';
            break;
        }
        return ValueListenableBuilder<MqttConnectionState>(
          valueListenable: _mqtt.state,
          builder: (context, mqttState, _) {
            final mqttLabel = _mqtt.statusLabel;
            final confPct = (state.confidence * 100).toStringAsFixed(0);
            final deviceCount = _mqtt.devices.value.length;
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Icon(icon, color: color, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (state.verdict != FusionVerdict.idle)
                    Text(
                      '· $confPct%',
                      style: TextStyle(
                        color: color.withValues(alpha: 0.9),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  const Spacer(),
                  Text(
                    '$mqttLabel · ${deviceCount}d',
                    style: TextStyle(
                      color: mqttState == MqttConnectionState.error
                          ? AppTheme.danger
                          : AppTheme.textSecondary,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// §6.4 — Trend yo'nalishi va "Time-to-Critical" RUL ko'rsatkichi
  Widget _buildPredictionRow() {
    final pred = _lastPrediction;
    final hasPred = pred != null && _predTimeH.length >= 3;

    // Trend rangi va matnlari
    Color trendColor;
    IconData trendIcon;
    String trendLabel;
    if (!hasPred) {
      trendColor = AppTheme.textMuted;
      trendIcon = Icons.hourglass_empty;
      trendLabel = "MA'LUMOT YIG'ILMOQDA";
    } else if (pred.direction == 1) {
      trendColor = AppTheme.danger;
      trendIcon = Icons.trending_up;
      trendLabel = 'OSHMOQDA';
    } else if (pred.direction == -1) {
      trendColor = AppTheme.success;
      trendIcon = Icons.trending_down;
      trendLabel = 'KAMAYMOQDA';
    } else {
      trendColor = AppTheme.primary;
      trendIcon = Icons.trending_flat;
      trendLabel = 'BARQAROR';
    }

    // RUL matni
    String rulValue;
    String rulMetric;
    Color rulColor;
    if (!hasPred || pred.direction != 1 || pred.hoursToCritical < 0) {
      rulValue = '—';
      rulMetric = '';
      rulColor = AppTheme.textMuted;
    } else {
      final h = pred.hoursToCritical;
      if (h < 1) {
        rulValue = (h * 60).toStringAsFixed(0);
        rulMetric = 'daq';
        rulColor = AppTheme.danger;
      } else if (h < 48) {
        rulValue = h.toStringAsFixed(1);
        rulMetric = 'soat';
        rulColor = h < 24 ? AppTheme.danger : AppTheme.warning;
      } else {
        rulValue = (h / 24.0).toStringAsFixed(1);
        rulMetric = 'kun';
        rulColor = AppTheme.success;
      }
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildHudIndicator(
          title: 'TREND (§6.4)',
          value: trendLabel,
          metric: '',
          icon: trendIcon,
          color: trendColor,
        ),
        Container(width: 1, height: 40, color: AppTheme.surfaceLight),
        _buildHudIndicator(
          title: 'KRITIKGACHA',
          value: rulValue,
          metric: rulMetric,
          icon: Icons.schedule,
          color: rulColor,
        ),
      ],
    );
  }

  Widget _buildHudIndicator({
    required String title,
    required String value,
    required String metric,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(
              color: AppTheme.textMuted, fontSize: 10, letterSpacing: 1),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(color: color.withValues(alpha: 0.5), blurRadius: 10)
                ],
              ),
            ),
            if (metric.isNotEmpty) ...[
              const SizedBox(width: 2),
              Text(
                metric,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 10),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildBottomControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // AI Chat / Digital Twin
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  // Digital twin oynasiga otish. Modul Navigation yoziladi.
                  // Navigator.pushNamed(context, '/digital_twin');
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceLight.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.secondary.withValues(alpha: 0.5)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.view_in_ar,
                          color: AppTheme.secondary, size: 20),
                      SizedBox(width: 8),
                      Text('3D EGIzAK',
                          style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          AiChatScreen(aiService: _aiAssistant),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceLight.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.5)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline,
                          color: AppTheme.primary, size: 20),
                      SizedBox(width: 8),
                      Text('AI CONSULT',
                          style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Start/Stop Boshqaruv
        if (_isMonitoring)
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (_pointCloud.isScanning) {
                      _pointCloud.pauseScanning();
                    } else {
                      _pointCloud.resumeScanning();
                    }
                    setState(() {});
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _pointCloud.isScanning ? AppTheme.warning : AppTheme.success,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _pointCloud.isScanning ? Icons.pause : Icons.play_arrow,
                          color: _pointCloud.isScanning ? AppTheme.warning : AppTheme.success,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _pointCloud.isScanning ? 'PAUZA' : 'DAVOM ETISH',
                          style: TextStyle(
                            color: _pointCloud.isScanning ? AppTheme.warning : AppTheme.success,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: _saveAndFinishScan,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryDark,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.primary, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.4),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.save, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          '3D MAKETNI SAQLASH',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          )
        else ...[
          // Material aniqlash zondlari (faqat kutish rejimida)
          if (_engineReady && _engine != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                AcousticProbeButton(
                  engine: _engine!,
                  onCompleted: () {
                    if (mounted) setState(() {});
                  },
                ),
                const SizedBox(width: 8),
                VibrationProbeButton(
                  onCompleted: () {
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _engineReady ? _toggleMonitoring : null,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.cyanAccent,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.cyanAccent.withValues(alpha: 0.3),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.radar,
                    color: Colors.cyanAccent,
                    size: 24,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'SKANERLASHNI BOSHLASH',
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// YOLOv8 Segmentation Mask (Poligon) chizuvchi CustomPainter
class _MaskPainter extends CustomPainter {
  final List<DetectedObject> objects;
  final DetectedObject? activeObject;
  final bool isAlert;

  _MaskPainter({
    required this.objects,
    required this.activeObject,
    required this.isAlert,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (objects.isEmpty) return;

    for (var obj in objects) {
      // DRIFT Compensation: Agar bu obyekt activeObject bilan bir xil bo'lsa (overlap), 
      // biz uni skip qilamiz, chunki activeObject (shifited) versiyasini alohida chizamiz.
      bool isRepresentedByActive = false;
      if (activeObject != null) {
        final intersection = obj.box.intersect(activeObject!.box);
        if (intersection.width > 0 && intersection.height > 0) {
           final overlapArea = intersection.width * intersection.height;
           final objArea = obj.box.width * obj.box.height;
           if (overlapArea / objArea > 0.8 && obj.label == activeObject!.label) {
             isRepresentedByActive = true;
           }
        }
      }
      
      if (isRepresentedByActive) continue;

      final color = AppTheme.textMuted.withValues(alpha: 0.5);

      final paintLine = Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      final paintFill = Paint()
        ..color = color.withValues(alpha: 0.1)
        ..style = PaintingStyle.fill;

      // Agar poligonlari bo'lsa (Segmentation modeli ishlagan bo'lsa) Poligon chizamiz
      if (obj.polygons != null && obj.polygons!.isNotEmpty) {
        final path = Path();
        path.moveTo(obj.polygons!.first.dx, obj.polygons!.first.dy);
        for (int i = 1; i < obj.polygons!.length; i++) {
          path.lineTo(obj.polygons![i].dx, obj.polygons![i].dy);
        }
        path.close();

        canvas.drawPath(path, paintFill);
        canvas.drawPath(path, paintLine);
      } else {
        // Poligin yo'q bo'lsa, xavfsizlik uchun faqat quti chizamiz
        canvas.drawRect(obj.box, paintFill);
        canvas.drawRect(obj.box, paintLine);
      }
    }

    // Nihoyat, Faol (Active) obyektni eng ustidan va Drift-to'g'irlangan (Shifted) xolatda chizamiz
    if (activeObject != null) {
      final color = isAlert ? AppTheme.danger : AppTheme.primary;
      final paintLine = Paint()
        ..color = color
        ..strokeWidth = 3.0
        ..style = PaintingStyle.stroke;

      final paintFill = Paint()
        ..color = color.withValues(alpha: 0.35)
        ..style = PaintingStyle.fill;

      if (activeObject!.polygons != null && activeObject!.polygons!.isNotEmpty) {
        final path = Path();
        path.moveTo(activeObject!.polygons!.first.dx, activeObject!.polygons!.first.dy);
        for (int i = 1; i < activeObject!.polygons!.length; i++) {
          path.lineTo(activeObject!.polygons![i].dx, activeObject!.polygons![i].dy);
        }
        path.close();
        canvas.drawPath(path, paintFill);
        canvas.drawPath(path, paintLine);
      } else {
        canvas.drawRect(activeObject!.box, paintFill);
        canvas.drawRect(activeObject!.box, paintLine);
      }

      final textPainter = TextPainter(
        text: TextSpan(
          text: ' ${activeObject!.label.toUpperCase()} [LOCKED] ',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            background: Paint()..color = color,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      double topY = activeObject!.box.top;
      if (activeObject!.polygons != null && activeObject!.polygons!.isNotEmpty) {
        topY = activeObject!.polygons!.map((e) => e.dy).reduce((a, b) => a < b ? a : b);
      }
      textPainter.paint(canvas, Offset(activeObject!.box.left, topY - 18));
    }
  }

  @override
  bool shouldRepaint(covariant _MaskPainter oldDelegate) {
    return true; // Har doim jonli yangilanadi
  }
}

class _PointCloudPainter extends CustomPainter {
  final List<Point3D> points;

  _PointCloudPainter(this.points);

  /// TZ §3.4: cyan (sovuq/normal) → red (qizg'in/kritik) HSV gradient.
  /// Sanoat heatmap palitrasi — cyan(180°)→green(120°)→yellow(60°)→red(0°).
  static Color heatmapColor(double intensity) {
    final i = intensity.clamp(0.0, 1.0);
    final hue = 180.0 - 180.0 * i;
    return HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final paint = Paint()..style = PaintingStyle.fill;
    final glowPaint = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    for (var p in points.toList()) {
      // Markazga nisbatan proeksiya
      double scale = 1.0;
      if (p.z != 0) {
        scale = 300 / (300 + p.z);
      }
      if (scale < 0) scale = 0; // Obyekt ortida qolgan nuqtalar

      double rx = size.width / 2 + p.x * scale;
      double ry = size.height / 2 + p.y * scale;

      final color = heatmapColor(p.intensity);
      final baseR = (2.0 * scale).clamp(0.5, 5.0);
      final isHot = p.intensity > PointCloudService.pulseThreshold;
      final radius = isHot ? baseR * 1.6 : baseR;

      if (isHot) {
        glowPaint.color = color.withValues(alpha: 0.45);
        canvas.drawCircle(Offset(rx, ry), radius * 2.2, glowPaint);
      }

      paint.color = color.withValues(alpha: 0.9);
      canvas.drawCircle(Offset(rx, ry), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PointCloudPainter oldDelegate) => true;
}
