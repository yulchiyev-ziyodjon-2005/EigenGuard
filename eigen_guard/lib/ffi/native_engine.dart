/// EigenGuard Native Engine — Dart FFI Bridge
///
/// C++ hisoblash yadrosini Dart orqali chaqirish uchun FFI interfeysi.
/// 5 Bosqichli Pipeline: OpticalFlow → Kalman → Spline → FFT → Approximation
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

/// C++ DLL dan eksport qilingan funksiyalarni yuklash
class NativeEngine {
  static NativeEngine? _instance;
  late final DynamicLibrary _lib;

  // ============================================
  // SplineProcessor FFI (Bosqich 3)
  // ============================================
  late final Pointer<Void> Function() _splineCreate;
  late final void Function(Pointer<Void>) _splineDestroy;
  late final int Function(Pointer<Void>, Pointer<Double>, Pointer<Double>, int)
      _splineSetData;
  late final int Function(Pointer<Void>) _splineCompute;
  late final double Function(Pointer<Void>, double) _splineEvaluate;
  late final double Function(Pointer<Void>, double) _splineEvaluateDerivative;
  late final int Function(
    Pointer<Void>,
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Double>,
    int,
  ) _splineGetCoefficients;
  late final int Function(Pointer<Void>) _splineGetPointCount;
  late final int Function(Pointer<Void>, Pointer<Double>, Pointer<Double>, int)
      _splineEvaluateBatch;
  late final Pointer<Utf8> Function() _eigenguardVersion;

  // ============================================
  // OpticalFlow FFI (Bosqich 1)
  // ============================================
  late final Pointer<Void> Function(int, int) _opticalFlowCreate;
  late final void Function(Pointer<Void>) _opticalFlowDestroy;
  late final double Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>,
      Pointer<Float>, Pointer<Float>) _opticalFlowCompute;

  // ============================================
  // KalmanFilter FFI (Bosqich 2)
  // ============================================
  late final Pointer<Void> Function(double, double, double, double)
      _kalmanCreate;
  late final void Function(Pointer<Void>) _kalmanDestroy;
  late final double Function(Pointer<Void>, double) _kalmanUpdate;

  // ============================================
  // FftProcessor FFI (Bosqich 4)
  // ============================================
  late final Pointer<Void> Function() _fftCreate;
  late final void Function(Pointer<Void>) _fftDestroy;
  late final double Function(Pointer<Void>, Pointer<Double>, int, double)
      _fftComputeDominant;
  late final int Function(Pointer<Void>, Pointer<Double>, int, double,
      Pointer<Double>, int, Pointer<Double>) _fftComputeSpectrum;

  // ============================================
  // ApproximationProcessor FFI (Bosqich 5 — §6.4)
  // ============================================
  late final Pointer<Void> Function() _approxCreate;
  late final void Function(Pointer<Void>) _approxDestroy;
  late final void Function(
      Pointer<Void>,
      Pointer<Double>,
      Pointer<Double>,
      int,
      double,
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Int32>) _approxPredict;

  // ============================================
  // Pipeline Chaqiruvi (Camera Frame → Natija)
  // ============================================
  late final double Function(
      Pointer<Void>,
      Pointer<Void>,
      Pointer<Void>,
      Pointer<Uint8>,
      Pointer<Uint8>,
      int,
      int,
      int,
      int,
      int,
      int,
      double,
      double,
      Pointer<Float>,
      Pointer<Float>) _processCameraFrame;

  // Singleton pattern
  factory NativeEngine() {
    _instance ??= NativeEngine._init();
    return _instance!;
  }

  NativeEngine._init() {
    _lib = _loadLibrary();
    _bindFunctions();
  }

  /// Platformaga mos DLL/SO yuklash
  static DynamicLibrary _loadLibrary() {
    if (Platform.isWindows) {
      return DynamicLibrary.open('eigenguard_engine.dll');
    } else if (Platform.isAndroid || Platform.isLinux) {
      return DynamicLibrary.open('libeigenguard_engine.so');
    } else if (Platform.isMacOS || Platform.isIOS) {
      return DynamicLibrary.open('libeigenguard_engine.dylib');
    }
    throw UnsupportedError(
      'EigenGuard: ${Platform.operatingSystem} qo\'llab-quvvatlanmaydi',
    );
  }

  /// C funksiyalarni bog'lash
  void _bindFunctions() {
    // --- Spline ---
    _splineCreate = _lib
        .lookup<NativeFunction<Pointer<Void> Function()>>('spline_create')
        .asFunction();

    _splineDestroy = _lib
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>('spline_destroy')
        .asFunction();

    _splineSetData = _lib
        .lookup<
            NativeFunction<
                Int32 Function(
                  Pointer<Void>,
                  Pointer<Double>,
                  Pointer<Double>,
                  Int32,
                )>>('spline_set_data')
        .asFunction();

    _splineCompute = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>('spline_compute')
        .asFunction();

    _splineEvaluate = _lib
        .lookup<NativeFunction<Double Function(Pointer<Void>, Double)>>(
          'spline_evaluate',
        )
        .asFunction();

    _splineEvaluateDerivative = _lib
        .lookup<NativeFunction<Double Function(Pointer<Void>, Double)>>(
          'spline_evaluate_derivative',
        )
        .asFunction();

    _splineGetCoefficients = _lib
        .lookup<
            NativeFunction<
                Int32 Function(
                  Pointer<Void>,
                  Pointer<Double>,
                  Pointer<Double>,
                  Pointer<Double>,
                  Pointer<Double>,
                  Int32,
                )>>('spline_get_coefficients')
        .asFunction();

    _splineGetPointCount = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>(
          'spline_get_point_count',
        )
        .asFunction();

    _splineEvaluateBatch = _lib
        .lookup<
            NativeFunction<
                Int32 Function(
                  Pointer<Void>,
                  Pointer<Double>,
                  Pointer<Double>,
                  Int32,
                )>>('spline_evaluate_batch')
        .asFunction();

    _eigenguardVersion = _lib
        .lookup<NativeFunction<Pointer<Utf8> Function()>>('eigenguard_version')
        .asFunction();

    // --- Optical Flow ---
    _opticalFlowCreate = _lib
        .lookup<NativeFunction<Pointer<Void> Function(Int32, Int32)>>(
            'optical_flow_create')
        .asFunction();

    _opticalFlowDestroy = _lib
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
            'optical_flow_destroy')
        .asFunction();

    _opticalFlowCompute = _lib
        .lookup<
            NativeFunction<
                Float Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>,
                    Pointer<Float>, Pointer<Float>)>>('optical_flow_compute')
        .asFunction();

    // --- Kalman Filter ---
    _kalmanCreate = _lib
        .lookup<
            NativeFunction<
                Pointer<Void> Function(
                    Double, Double, Double, Double)>>('kalman_create')
        .asFunction();

    _kalmanDestroy = _lib
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>('kalman_destroy')
        .asFunction();

    _kalmanUpdate = _lib
        .lookup<NativeFunction<Double Function(Pointer<Void>, Double)>>(
            'kalman_update')
        .asFunction();

    // --- FFT Processor ---
    _fftCreate = _lib
        .lookup<NativeFunction<Pointer<Void> Function()>>('fft_create')
        .asFunction();

    _fftDestroy = _lib
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>('fft_destroy')
        .asFunction();

    _fftComputeDominant = _lib
        .lookup<
            NativeFunction<
                Double Function(Pointer<Void>, Pointer<Double>, Int32,
                    Double)>>('fft_compute_dominant')
        .asFunction();

    _fftComputeSpectrum = _lib
        .lookup<
            NativeFunction<
                Int32 Function(
                    Pointer<Void>,
                    Pointer<Double>,
                    Int32,
                    Double,
                    Pointer<Double>,
                    Int32,
                    Pointer<Double>)>>('fft_compute_spectrum')
        .asFunction();

    // --- Approximation Processor ---
    _approxCreate = _lib
        .lookup<NativeFunction<Pointer<Void> Function()>>('approx_create')
        .asFunction();

    _approxDestroy = _lib
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>('approx_destroy')
        .asFunction();

    _approxPredict = _lib
        .lookup<
            NativeFunction<
                Void Function(
                    Pointer<Void>,
                    Pointer<Double>,
                    Pointer<Double>,
                    Int32,
                    Double,
                    Pointer<Double>,
                    Pointer<Double>,
                    Pointer<Double>,
                    Pointer<Double>,
                    Pointer<Int32>)>>('approx_predict')
        .asFunction();

    // --- Camera Pipeline (OpticalFlow + Kalman x, y) ---
    _processCameraFrame = _lib
        .lookup<
            NativeFunction<
                Float Function(
                    Pointer<Void>,
                    Pointer<Void>,
                    Pointer<Void>,
                    Pointer<Uint8>,
                    Pointer<Uint8>,
                    Int32,
                    Int32,
                    Int32,
                    Int32,
                    Int32,
                    Int32,
                    Float,
                    Float,
                    Pointer<Float>,
                    Pointer<Float>)>>('process_camera_frame')
        .asFunction();
  }

  /// Engine versiyasini olish
  String getVersion() {
    final ptr = _eigenguardVersion();
    return ptr.toDartString();
  }

  /// Yangi SplineProcessor yaratish
  SplineProcessor createSplineProcessor() {
    return SplineProcessor._(this);
  }

  /// Yangi OpticalFlowProcessor yaratish
  OpticalFlowProcessor createOpticalFlowProcessor(int width, int height) {
    return OpticalFlowProcessor._(this, width, height);
  }

  /// Yangi KalmanFilter yaratish
  KalmanFilterProcessor createKalmanFilter({
    double processNoise = 0.008,
    double measurementNoise = 0.1,
    double estimationError = 1.0,
    double initialValue = 0.0,
  }) {
    return KalmanFilterProcessor._(
        this, processNoise, measurementNoise, estimationError, initialValue);
  }

  /// Yangi FftProcessor yaratish
  FftProcessorWrapper createFftProcessor() {
    return FftProcessorWrapper._(this);
  }

  /// Yangi ApproximationProcessor yaratish
  ApproxProcessorWrapper createApproxProcessor() {
    return ApproxProcessorWrapper._(this);
  }

  /// Yangi CameraPipeline yaratish
  CameraPipelineWrapper createCameraPipeline(int width, int height) {
    return CameraPipelineWrapper._(this, width, height);
  }
}

// ============================================================
// CameraPipelineWrapper (Optical Flow + 2x Kalman)
// ============================================================
class CameraPipelineWrapper {
  final NativeEngine _engine;
  Pointer<Void>? _flowHandle;
  Pointer<Void>? _kalmanDxHandle;
  Pointer<Void>? _kalmanDyHandle;
  bool _isDisposed = false;

  CameraPipelineWrapper._(this._engine, int width, int height) {
    _flowHandle = _engine._opticalFlowCreate(width, height);
    _kalmanDxHandle = _engine._kalmanCreate(0.008, 0.1, 1.0, 0.0);
    _kalmanDyHandle = _engine._kalmanCreate(0.008, 0.1, 1.0, 0.0);

    if (_flowHandle == nullptr ||
        _kalmanDxHandle == nullptr ||
        _kalmanDyHandle == nullptr) {
      throw StateError('CameraPipeline yaratib bo\'lmadi');
    }
  }

  /// process_camera_frame orqali O(1) tarzda Optical Flow va Kalman filtr
  double processFrame(
      Uint8List prevFrame,
      Uint8List currFrame,
      int width,
      int height,
      int roiX,
      int roiY,
      int roiW,
      int roiH,
      double imuDx,
      double imuDy,
      Float32List dxOut,
      Float32List dyOut) {
    _checkDisposed();
    if (prevFrame.length != currFrame.length) return 0.0;

    final pPtr = calloc<Uint8>(prevFrame.length);
    final cPtr = calloc<Uint8>(currFrame.length);
    final dxPtr = calloc<Float>();
    final dyPtr = calloc<Float>();

    try {
      pPtr.asTypedList(prevFrame.length).setAll(0, prevFrame);
      cPtr.asTypedList(currFrame.length).setAll(0, currFrame);

      final mag = _engine._processCameraFrame(
          _flowHandle!,
          _kalmanDxHandle!,
          _kalmanDyHandle!,
          pPtr,
          cPtr,
          width,
          height,
          roiX,
          roiY,
          roiW,
          roiH,
          imuDx,
          imuDy,
          dxPtr,
          dyPtr);

      if (dxOut.isNotEmpty) dxOut[0] = dxPtr.value;
      if (dyOut.isNotEmpty) dyOut[0] = dyPtr.value;

      return mag;
    } finally {
      calloc.free(pPtr);
      calloc.free(cPtr);
      calloc.free(dxPtr);
      calloc.free(dyPtr);
    }
  }

  void dispose() {
    if (!_isDisposed) {
      if (_flowHandle != null) {
        _engine._opticalFlowDestroy(_flowHandle!);
      }
      if (_kalmanDxHandle != null) {
        _engine._kalmanDestroy(_kalmanDxHandle!);
      }
      if (_kalmanDyHandle != null) {
        _engine._kalmanDestroy(_kalmanDyHandle!);
      }
      _flowHandle = null;
      _kalmanDxHandle = null;
      _kalmanDyHandle = null;
      _isDisposed = true;
    }
  }

  void _checkDisposed() {
    if (_isDisposed) {
      throw StateError('CameraPipeline allaqachon dispose qilingan');
    }
  }
}

// ============================================================
// Kubik Splayn koeffitsiyentlari
// ============================================================
class SplineCoefficients {
  final Float64List a;
  final Float64List b;
  final Float64List c;
  final Float64List d;
  final int n;

  SplineCoefficients({
    required this.a,
    required this.b,
    required this.c,
    required this.d,
    required this.n,
  });

  @override
  String toString() {
    final buffer = StringBuffer('SplineCoefficients (n=$n):\n');
    for (int i = 0; i < n; i++) {
      buffer.writeln(
        '  S_$i(x) = ${a[i].toStringAsFixed(4)} + ${b[i].toStringAsFixed(4)}·(x-xᵢ) '
        '+ ${c[i].toStringAsFixed(4)}·(x-xᵢ)² + ${d[i].toStringAsFixed(4)}·(x-xᵢ)³',
      );
    }
    return buffer.toString();
  }
}

// ============================================================
// SplineProcessor Wrapper (Bosqich 3)
// ============================================================
class SplineProcessor {
  final NativeEngine _engine;
  Pointer<Void>? _handle;
  bool _isDisposed = false;

  SplineProcessor._(this._engine) {
    _handle = _engine._splineCreate();
    if (_handle == nullptr) {
      throw StateError('SplineProcessor yaratib bo\'lmadi');
    }
  }

  bool setDataPoints(Float64List t, Float64List y) {
    _checkDisposed();
    if (t.length != y.length || t.length < 3) return false;
    final tPtr = calloc<Double>(t.length);
    final yPtr = calloc<Double>(y.length);
    try {
      for (int i = 0; i < t.length; i++) {
        tPtr[i] = t[i];
        yPtr[i] = y[i];
      }
      return _engine._splineSetData(_handle!, tPtr, yPtr, t.length) == 1;
    } finally {
      calloc.free(tPtr);
      calloc.free(yPtr);
    }
  }

  bool compute() {
    _checkDisposed();
    return _engine._splineCompute(_handle!) == 1;
  }

  double evaluate(double x) {
    _checkDisposed();
    return _engine._splineEvaluate(_handle!, x);
  }

  double evaluateDerivative(double x) {
    _checkDisposed();
    return _engine._splineEvaluateDerivative(_handle!, x);
  }

  Float64List evaluateBatch(Float64List xValues) {
    _checkDisposed();
    final xPtr = calloc<Double>(xValues.length);
    final yPtr = calloc<Double>(xValues.length);
    try {
      for (int i = 0; i < xValues.length; i++) {
        xPtr[i] = xValues[i];
      }
      _engine._splineEvaluateBatch(_handle!, xPtr, yPtr, xValues.length);
      final result = Float64List(xValues.length);
      for (int i = 0; i < xValues.length; i++) {
        result[i] = yPtr[i];
      }
      return result;
    } finally {
      calloc.free(xPtr);
      calloc.free(yPtr);
    }
  }

  SplineCoefficients getCoefficients() {
    _checkDisposed();
    final pointCount = _engine._splineGetPointCount(_handle!);
    final n = pointCount - 1;
    final aPtr = calloc<Double>(n);
    final bPtr = calloc<Double>(n);
    final cPtr = calloc<Double>(n);
    final dPtr = calloc<Double>(n);
    try {
      final resultN =
          _engine._splineGetCoefficients(_handle!, aPtr, bPtr, cPtr, dPtr, n);
      if (resultN < 0) {
        throw StateError('Koeffitsiyentlar hali hisoblanmagan');
      }
      final a = Float64List(resultN);
      final b = Float64List(resultN);
      final c = Float64List(resultN);
      final d = Float64List(resultN);
      for (int i = 0; i < resultN; i++) {
        a[i] = aPtr[i];
        b[i] = bPtr[i];
        c[i] = cPtr[i];
        d[i] = dPtr[i];
      }
      return SplineCoefficients(a: a, b: b, c: c, d: d, n: resultN);
    } finally {
      calloc.free(aPtr);
      calloc.free(bPtr);
      calloc.free(cPtr);
      calloc.free(dPtr);
    }
  }

  int getPointCount() {
    _checkDisposed();
    return _engine._splineGetPointCount(_handle!);
  }

  void dispose() {
    if (!_isDisposed && _handle != null) {
      _engine._splineDestroy(_handle!);
      _handle = null;
      _isDisposed = true;
    }
  }

  void _checkDisposed() {
    if (_isDisposed) {
      throw StateError('SplineProcessor allaqachon dispose qilingan');
    }
  }
}

// ============================================================
// OpticalFlowProcessor Wrapper (Bosqich 1)
// ============================================================
class OpticalFlowProcessor {
  final NativeEngine _engine;
  Pointer<Void>? _handle;
  bool _isDisposed = false;

  OpticalFlowProcessor._(this._engine, int width, int height) {
    _handle = _engine._opticalFlowCreate(width, height);
    if (_handle == nullptr) {
      throw StateError('OpticalFlowProcessor yaratib bo\'lmadi');
    }
  }

  double computeFlow(Uint8List frame1, Uint8List frame2, Float32List dxOut,
      Float32List dyOut) {
    _checkDisposed();
    if (frame1.length != frame2.length) return 0.0;
    final f1Ptr = calloc<Uint8>(frame1.length);
    final f2Ptr = calloc<Uint8>(frame2.length);
    final dxPtr = calloc<Float>();
    final dyPtr = calloc<Float>();
    try {
      f1Ptr.asTypedList(frame1.length).setAll(0, frame1);
      f2Ptr.asTypedList(frame2.length).setAll(0, frame2);
      final mag =
          _engine._opticalFlowCompute(_handle!, f1Ptr, f2Ptr, dxPtr, dyPtr);
      if (dxOut.isNotEmpty) dxOut[0] = dxPtr.value;
      if (dyOut.isNotEmpty) dyOut[0] = dyPtr.value;
      return mag;
    } finally {
      calloc.free(f1Ptr);
      calloc.free(f2Ptr);
      calloc.free(dxPtr);
      calloc.free(dyPtr);
    }
  }

  void dispose() {
    if (!_isDisposed && _handle != null) {
      _engine._opticalFlowDestroy(_handle!);
      _handle = null;
      _isDisposed = true;
    }
  }

  void _checkDisposed() {
    if (_isDisposed) {
      throw StateError('OpticalFlowProcessor allaqachon dispose qilingan');
    }
  }
}

// ============================================================
// KalmanFilter Wrapper (Bosqich 2)
// ============================================================
class KalmanFilterProcessor {
  final NativeEngine _engine;
  Pointer<Void>? _handle;
  bool _isDisposed = false;

  KalmanFilterProcessor._(this._engine, double processNoise,
      double measurementNoise, double estimationError, double initialValue) {
    _handle = _engine._kalmanCreate(
        processNoise, measurementNoise, estimationError, initialValue);
    if (_handle == nullptr) {
      throw StateError('KalmanFilter yaratib bo\'lmadi');
    }
  }

  /// Shovqinli o'lchov kiritib, tozalangan qiymat olish
  double update(double measurement) {
    _checkDisposed();
    return _engine._kalmanUpdate(_handle!, measurement);
  }

  void dispose() {
    if (!_isDisposed && _handle != null) {
      _engine._kalmanDestroy(_handle!);
      _handle = null;
      _isDisposed = true;
    }
  }

  void _checkDisposed() {
    if (_isDisposed) {
      throw StateError('KalmanFilter allaqachon dispose qilingan');
    }
  }
}

// ============================================================
// FftProcessor Wrapper (Bosqich 4)
// ============================================================

/// FFT Natijasi — dominant chastota va spektr
class FftResult {
  final double dominantFreq;
  final Float64List magnitudes;

  FftResult({required this.dominantFreq, required this.magnitudes});
}

class FftProcessorWrapper {
  final NativeEngine _engine;
  Pointer<Void>? _handle;
  bool _isDisposed = false;

  FftProcessorWrapper._(this._engine) {
    _handle = _engine._fftCreate();
    if (_handle == nullptr) {
      throw StateError('FftProcessor yaratib bo\'lmadi');
    }
  }

  /// Faqat dominant chastotani olish
  double computeDominant(Float64List signal, double sampleRate) {
    _checkDisposed();
    final sigPtr = calloc<Double>(signal.length);
    try {
      for (int i = 0; i < signal.length; i++) {
        sigPtr[i] = signal[i];
      }
      return _engine._fftComputeDominant(
          _handle!, sigPtr, signal.length, sampleRate);
    } finally {
      calloc.free(sigPtr);
    }
  }

  /// To'liq spektrni olish (dominant freq + magnitudes)
  FftResult computeSpectrum(Float64List signal, double sampleRate) {
    _checkDisposed();
    final sigPtr = calloc<Double>(signal.length);
    // Maksimal magnitudes soni = signal.length / 2
    final maxOut = signal.length ~/ 2 + 1;
    final magPtr = calloc<Double>(maxOut);
    final freqPtr = calloc<Double>();
    try {
      for (int i = 0; i < signal.length; i++) {
        sigPtr[i] = signal[i];
      }
      final outCount = _engine._fftComputeSpectrum(
          _handle!, sigPtr, signal.length, sampleRate, magPtr, maxOut, freqPtr);

      final magnitudes = Float64List(outCount);
      for (int i = 0; i < outCount; i++) {
        magnitudes[i] = magPtr[i];
      }
      return FftResult(dominantFreq: freqPtr.value, magnitudes: magnitudes);
    } finally {
      calloc.free(sigPtr);
      calloc.free(magPtr);
      calloc.free(freqPtr);
    }
  }

  void dispose() {
    if (!_isDisposed && _handle != null) {
      _engine._fftDestroy(_handle!);
      _handle = null;
      _isDisposed = true;
    }
  }

  void _checkDisposed() {
    if (_isDisposed) {
      throw StateError('FftProcessor allaqachon dispose qilingan');
    }
  }
}

// ============================================================
// ApproximationProcessor Wrapper (Bosqich 5 — §6.4)
// ============================================================

/// Bashorat natijasi
class PredictionResult {
  final double a;
  final double b;
  final double c;
  final double hoursToCritical;
  final int direction; // -1=Kamaymoqda, 0=Barqaror, 1=Oshmoqda

  PredictionResult({
    required this.a,
    required this.b,
    required this.c,
    required this.hoursToCritical,
    required this.direction,
  });

  String get directionLabel {
    switch (direction) {
      case 1:
        return 'OSHMOQDA ↑';
      case -1:
        return 'KAMAYMOQDA ↓';
      default:
        return 'BARQAROR →';
    }
  }

  bool get isCritical => hoursToCritical > 0 && hoursToCritical < 72;
}

class ApproxProcessorWrapper {
  final NativeEngine _engine;
  Pointer<Void>? _handle;
  bool _isDisposed = false;

  ApproxProcessorWrapper._(this._engine) {
    _handle = _engine._approxCreate();
    if (_handle == nullptr) {
      throw StateError('ApproximationProcessor yaratib bo\'lmadi');
    }
  }

  /// §6.4 — Parabolik fit va Time-to-Critical bashorat
  PredictionResult predict(Float64List t, Float64List y, double yLimit) {
    _checkDisposed();
    if (t.length != y.length || t.length < 3) {
      return PredictionResult(
          a: 0, b: 0, c: 0, hoursToCritical: -1, direction: 0);
    }

    final tPtr = calloc<Double>(t.length);
    final yPtr = calloc<Double>(y.length);
    final aPtr = calloc<Double>();
    final bPtr = calloc<Double>();
    final cPtr = calloc<Double>();
    final hPtr = calloc<Double>();
    final dPtr = calloc<Int32>();

    try {
      for (int i = 0; i < t.length; i++) {
        tPtr[i] = t[i];
        yPtr[i] = y[i];
      }

      _engine._approxPredict(
          _handle!, tPtr, yPtr, t.length, yLimit, aPtr, bPtr, cPtr, hPtr, dPtr);

      return PredictionResult(
        a: aPtr.value,
        b: bPtr.value,
        c: cPtr.value,
        hoursToCritical: hPtr.value,
        direction: dPtr.value,
      );
    } finally {
      calloc.free(tPtr);
      calloc.free(yPtr);
      calloc.free(aPtr);
      calloc.free(bPtr);
      calloc.free(cPtr);
      calloc.free(hPtr);
      calloc.free(dPtr);
    }
  }

  void dispose() {
    if (!_isDisposed && _handle != null) {
      _engine._approxDestroy(_handle!);
      _handle = null;
      _isDisposed = true;
    }
  }

  void _checkDisposed() {
    if (_isDisposed) {
      throw StateError('ApproximationProcessor allaqachon dispose qilingan');
    }
  }
}
