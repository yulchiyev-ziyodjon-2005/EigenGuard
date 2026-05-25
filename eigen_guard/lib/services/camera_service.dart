import 'dart:async';
import 'dart:isolate';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// EigenGuard Camera Service — Real-time Camera to C++ Pipeline
/// Kamera kadrlarini Dart Isolate orqali oladi va callback ga uzatadi.
/// UI thread ni qotirmaslik uchun kadrlar alohida ipda tahlilga tayyorlanadi.
class CameraService {
  static final CameraService _instance = CameraService._internal();
  factory CameraService() => _instance;
  CameraService._internal();

  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isStreaming = false;
  bool _permissionDenied = false;

  // Frame throttle — sekundiga max N ta kadr chiqarish
  int maxFps = 10; // C++ va AI ga ortiqcha yuk tushmasligi uchun 10 FPS gacha kamaytirildi (har ~100ms)
  DateTime _lastFrameTime = DateTime.now();

  // Isolate resurslari
  Isolate? _processingIsolate;
  ReceivePort? _receivePort;
  SendPort? _isolateSendPort;

  // Frame handler callback (UI tomonidan o'rnatiladi)
  Function(Uint8List frameData, int width, int height)? onFrame;

  CameraController? get controller => _controller;
  bool get isInitialized => _isInitialized;
  bool get isStreaming => _isStreaming;
  bool get permissionDenied => _permissionDenied;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // ===== RUNTIME PERMISSION =====
      var cameraStatus = await Permission.camera.request();
      while (!cameraStatus.isGranted) {
        _permissionDenied = true;
        debugPrint('[CameraService] Kamera ruxsati zarur!');
        if (cameraStatus.isPermanentlyDenied) {
          await openAppSettings();
        }
        await Future.delayed(const Duration(seconds: 2));
        cameraStatus = await Permission.camera.request();
      }
      _permissionDenied = false;
      debugPrint('[CameraService] Kamera ruxsati berildi ✓');

      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        debugPrint('[CameraService] Kamera topilmadi');
        return;
      }

      // Orqa kamerani tanlaymiz (tebranish o'lchash uchun)
      final camera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      _controller = CameraController(
        camera,
        ResolutionPreset.medium, // 720p — tezlik va sifat balansi
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420, // Grayscale Y-plane kerak
      );

      await _controller!.initialize();
      await _controller!.setFocusMode(FocusMode.auto);
      _isInitialized = true;
      debugPrint('[CameraService] Kamera tayyor: ${camera.name}');
    } catch (e) {
      debugPrint('[CameraService] Xatolik: $e');
    }
  }

  /// Kadr oqimini boshlash (Isolate orqali asinxron)
  Future<void> startStream({
    required Function(Uint8List frame, int w, int h) onFrameData,
    Function(CameraImage image, int sensorOrientation)? onRawImage,
  }) async {
    if (!_isInitialized || _controller == null || _isStreaming) return;

    onFrame = onFrameData;
    _isStreaming = true;

    // Isolate ni boshlash
    await _startProcessingIsolate();

    await _controller!.startImageStream((CameraImage image) {
      if (!_isStreaming) return;

      onRawImage?.call(image, _controller!.description.sensorOrientation);

      // FPS Throttle — haddan tashqari kadr yo'llamaslik
      final now = DateTime.now();
      final elapsed = now.difference(_lastFrameTime).inMilliseconds;
      final minInterval = 1000 ~/ maxFps;
      if (elapsed < minInterval) return;
      _lastFrameTime = now;

      if (image.format.group == ImageFormatGroup.yuv420) {
        try {
          // YUV420 formatidagi birinchi plane (Y-plane) = GRAYSCALE
          final yPlane = image.planes[0].bytes;
          final width = image.width;
          final height = image.height;

          // Kadrni Isolate ga jo'natish (zero-copy tarzda)
          if (_isolateSendPort != null) {
            _isolateSendPort!.send(_FrameMessage(
              frameData: Uint8List.fromList(yPlane),
              width: width,
              height: height,
            ));
          }
        } catch (e) {
          debugPrint('[CameraService] Frame error: $e');
        }
      }
    });
    debugPrint('[CameraService] Kadr oqimi boshlandi (${maxFps}fps limit)');
  }

  /// Kadr oqimini to'xtatish
  Future<void> stopStream() async {
    if (!_isStreaming || _controller == null) return;
    _isStreaming = false;
    try {
      await _controller!.stopImageStream();
    } catch (_) {}
    _stopProcessingIsolate();
    debugPrint('[CameraService] Kadr oqimi to\'xtatildi');
  }

  /// Isolate ni boshlash — kameradagi kadrlarni asosiy UI oqimidan ajratib ishlash
  Future<void> _startProcessingIsolate() async {
    _receivePort = ReceivePort();

    _receivePort!.listen((message) {
      if (message is SendPort) {
        _isolateSendPort = message;
      } else if (message is _FrameMessage) {
        // Isolate dan qayta ishlangan kadr keldi — UI callback ga uzatamiz
        onFrame?.call(message.frameData, message.width, message.height);
      }
    });

    _processingIsolate = await Isolate.spawn(
      _isolateEntryPoint,
      _receivePort!.sendPort,
    );
  }

  /// Isolate ni to'xtatish
  void _stopProcessingIsolate() {
    _processingIsolate?.kill(priority: Isolate.immediate);
    _processingIsolate = null;
    _receivePort?.close();
    _receivePort = null;
    _isolateSendPort = null;
  }

  /// Isolate ichidagi jarayon — alohida ipda ishlaydi
  static void _isolateEntryPoint(SendPort mainSendPort) {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    receivePort.listen((message) {
      if (message is _FrameMessage) {
        // Bu yerda kelajakda kadr preprocessingi (masalan, o'lchamini kichraytirish) amalga oshirilishi mumkin.
        // Hozircha kadrni to'g'ridan-to'g'ri qaytaramiz.
        mainSendPort.send(_FrameMessage(
          frameData: message.frameData,
          width: message.width,
          height: message.height,
        ));
      }
    });
  }

  void dispose() {
    stopStream();
    _controller?.dispose();
    _controller = null;
    _isInitialized = false;
  }
}

/// Isolate xabar formati
class _FrameMessage {
  final Uint8List frameData;
  final int width;
  final int height;

  _FrameMessage({
    required this.frameData,
    required this.width,
    required this.height,
  });
}
