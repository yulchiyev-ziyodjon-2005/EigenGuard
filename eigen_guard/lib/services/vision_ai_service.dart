import 'dart:async';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// YOLO2026 NMS-FREE END-TO-END VISION ENGINE (ONNX Runtime)
// ═══════════════════════════════════════════════════════════════════════════════
// Model:        yolo26n-seg.onnx (NMS-Free End-to-End, Segmentation)
// Input:        [1, 3, 640, 640] float32, RGB, normalized [0..1], NCHW
// Output0:      [1, 300, 38] — 300 ta yakuniy detection
//               [0:4]  = bbox xyxy (640px makonida)
//               [4]    = confidence
//               [5]    = class index (0-79 COCO)
//               [6:38] = 32 mask koefitsientlari
// Output1:      [1, 32, 160, 160] — prototype masklar
// Mask sintezi: sigmoid(sum(coeffs[i] * proto[i])) → 160×160 mask → bbox ichida kesilib resize
// Delegate:     NNAPI (Android NPU/GPU) → CPU XNNPACK fallback
// ═══════════════════════════════════════════════════════════════════════════════

/// O'ZBEK SANOAT LUG'ATI — COCO klasslarini sanoat terminlariga mapping
const Map<String, String> _industrialLabelMap = {
  'person': '[Texnik Xodim]',
  'bicycle': '[Ikki G\'ildirakli Transport]',
  'car': '[Xizmat Avtomobili]',
  'motorcycle': '[Mototexnika]',
  'airplane': '[Havo Kemasi]',
  'bus': '[Xizmat Avtobusi]',
  'train': '[Temir Yo\'l Transporti]',
  'truck': '[Yuk Tashuvchi]',
  'boat': '[Suv Transporti]',
  'traffic light': '[Signal Chiroq]',
  'fire hydrant': '[Sanoat Gidranti]',
  'stop sign': '[To\'xtatish Belgisi]',
  'parking meter': '[Hisoblagich]',
  'bench': '[Texnik Skameyka]',
  'bird': '[Qush — Xavfsizlik Zonasi]',
  'cat': '[Mushuk — Xavfsizlik Zonasi]',
  'dog': '[It — Xavfsizlik Zonasi]',
  'horse': '[Ot — Xavfsizlik Zonasi]',
  'sheep': '[Qo\'y — Xavfsizlik Zonasi]',
  'cow': '[Sigir — Xavfsizlik Zonasi]',
  'elephant': '[Fil — Xavfsizlik Zonasi]',
  'bear': '[Ayiq — Xavfsizlik Zonasi]',
  'zebra': '[Zebra — Xavfsizlik Zonasi]',
  'giraffe': '[Jirafa — Xavfsizlik Zonasi]',
  'backpack': '[Texnik Ryukzak]',
  'umbrella': '[Himoya Soyaboni]',
  'handbag': '[Jihoz Sumkasi]',
  'tie': '[Xavfsizlik Lentasi]',
  'suitcase': '[Asbob-uskunalar Qutisi]',
  'frisbee': '[Disk Shaklidagi Element]',
  'skis': '[Uzun Profil]',
  'snowboard': '[Yassi Profil]',
  'sports ball': '[Sferik Element]',
  'kite': '[Aerodynamik Sirt]',
  'baseball bat': '[Silindrsimon Asbob]',
  'baseball glove': '[Himoya Qo\'lqopi]',
  'skateboard': '[Platformali Mexanizm]',
  'surfboard': '[Uzun Yassi Panel]',
  'tennis racket': '[Setka Konstruksiya]',
  'bottle': '[Suyuqlik Idishi]',
  'wine glass': '[Laboratoriya Stakani]',
  'cup': '[O\'lchov Stakan]',
  'fork': '[Vilka Shaklidagi Instrument]',
  'knife': '[Pichoq / Kesish Asbobi]',
  'spoon': '[Qoshiq Shaklidagi Instrument]',
  'bowl': '[Yig\'ish Idishi]',
  'banana': '[Yot Jism — Organik]',
  'apple': '[Yot Jism — Organik]',
  'sandwich': '[Yot Jism — Organik]',
  'orange': '[Yot Jism — Organik]',
  'broccoli': '[Yot Jism — Organik]',
  'carrot': '[Yot Jism — Organik]',
  'hot dog': '[Yot Jism — Organik]',
  'pizza': '[Yot Jism — Organik]',
  'donut': '[Yot Jism — Organik]',
  'cake': '[Yot Jism — Organik]',
  'chair': '[Operator Kursisi]',
  'couch': '[Dam Olish Zonasi]',
  'potted plant': '[O\'simlik — Zonalash]',
  'bed': '[Dam Olish Joyi]',
  'dining table': '[Ish Stoli]',
  'toilet': '[Sanitariya Uskunasi]',
  'tv': '[Monitoring Ekrani]',
  'laptop': '[Boshqaruv Terminali]',
  'mouse': '[Kiritish Qurilmasi]',
  'remote': '[Masofaviy Boshqarish Pulti]',
  'keyboard': '[Kiritish Paneli]',
  'cell phone': '[Mobil Terminal]',
  'microwave': '[Termal Kamera / Isitgich]',
  'oven': '[Sanoat Pechi]',
  'toaster': '[Elektr Isitgich]',
  'sink': '[Sanoat Lavabosi]',
  'refrigerator': '[Sovutgich Agregat]',
  'book': '[Texnik Qo\'llanma]',
  'clock': '[Manometr / Soat]',
  'vase': '[Laboratoriya Idishi]',
  'scissors': '[Kesish Asbobi]',
  'teddy bear': '[Yot Jism — Nostandart]',
  'hair drier': '[Issiq Havo Qurilmasi]',
  'toothbrush': '[Tozalash Cho\'tkasi]',
};

String _localizeLabel(String rawLabel) {
  final normalized = rawLabel.trim().toLowerCase();
  return _industrialLabelMap[normalized] ?? '[${rawLabel.toUpperCase()}]';
}

// ═══════════════════════════════════════════════════════════════════════════════
// PIPELINE KONSTANTALARI
// ═══════════════════════════════════════════════════════════════════════════════
const int _kInputSize = 640;
const int _kMaxDetections = 300;
const int _kRowStride = 38; // 4 box + 1 conf + 1 cls + 32 mask
const int _kMaskCoeffs = 32;
const int _kProtoSize = 160;
const int _kNumClasses = 80;

// ═══════════════════════════════════════════════════════════════════════════════

/// VisionAiService — YOLO2026 NMS-Free End-to-End (ONNX Runtime + NNAPI)
class VisionAiService {
  OrtSession? _session;
  bool _isInitialized = false;
  bool _isBusy = false;
  bool _ortEnvReady = false;

  /// Joriy kadrdagi label ro'yxati (COCO-80)
  List<String> _cocoLabels = const [];

  /// Tanib olish (NMS-free) chegarasi — model o'zi NMS qiladi, biz faqat past
  /// confidence ni kesib tashlaymiz.
  double confThreshold = 0.30;

  /// Mask binarizatsiya chegarasi (sigmoid natijasi ustida)
  double maskThreshold = 0.50;

  /// Barcha aniqlangan obyektlar (har kadr yangilanadi)
  List<DetectedObject> currentObjects = [];

  /// YOLO natijasi yangilanganligini bilish uchun monotonik counter
  int updateCount = 0;

  /// Diagnostika — oxirgi inference davomiyligi (ms)
  int lastInferenceMs = 0;

  /// Diagnostika — ishlatilayotgan provider nomi
  String activeProvider = 'unknown';

  // Qulaylik getterlar (birinchi obyekt uchun)
  Rect? get currentBoundingBox =>
      currentObjects.isNotEmpty ? currentObjects.first.box : null;
  String? get currentObjectLabel =>
      currentObjects.isNotEmpty ? currentObjects.first.label : null;
  double get confidence =>
      currentObjects.isNotEmpty ? currentObjects.first.confidence : 0.0;
  List<Offset>? get currentPolygons =>
      currentObjects.isNotEmpty ? currentObjects.first.polygons : null;

  /// Modelni yuklash. NNAPI → XNNPACK CPU fallback.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 1) ONNX Runtime env (bir martalik global)
      if (!_ortEnvReady) {
        OrtEnv.instance.init();
        _ortEnvReady = true;
      }

      // 2) Labels (COCO-80) ni yuklash
      final labelsRaw = await rootBundle.loadString('assets/models/labels.txt');
      _cocoLabels = labelsRaw
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);

      // 3) Modelni bayt qatori sifatida o'qish
      final modelBytes =
          await rootBundle.load('assets/models/yolo26n-seg.onnx');
      final modelData = modelBytes.buffer.asUint8List();

      // 4) Session options — Android NNAPI delegate (NPU/GPU)
      final options = OrtSessionOptions();
      try {
        options.appendNnapiProvider(NnapiFlags.useFp16);
        activeProvider = 'NNAPI (FP16)';
      } catch (e) {
        debugPrint(
            '[VisionAI] NNAPI provider qo\'shilmadi: $e — XNNPACK CPU ishlaydi');
        activeProvider = 'XNNPACK CPU';
      }
      try {
        options.appendXnnpackProvider();
      } catch (_) {/* ixtiyoriy, mavjud bo'lmasa o'tib ketamiz */}
      options.setIntraOpNumThreads(4);
      options.setInterOpNumThreads(2);
      options.setSessionGraphOptimizationLevel(
          GraphOptimizationLevel.ortEnableAll);

      _session = OrtSession.fromBuffer(modelData, options);
      _isInitialized = true;
      debugPrint(
          '[VisionAI] YOLO2026 yuklandi ✓  Provider=$activeProvider  Labels=${_cocoLabels.length}');
    } catch (e, st) {
      debugPrint('[VisionAI] Yuklashda KRITIK xato: $e\n$st');
      _isInitialized = false;
    }
  }

  /// Kadrni tahlil qilish — ONNX inference + post-processing.
  /// Eski API ni saqlaydi (`processCameraImage`) — DashboardScreen ga
  /// hech qanday o'zgartirish kerak emas.
  Future<void> processCameraImage(
      CameraImage image, int sensorOrientation) async {
    if (!_isInitialized || _session == null || _isBusy) return;
    _isBusy = true;
    final t0 = DateTime.now();

    try {
      // 1) Kadrni image.Image (RGB) ga konvertatsiya qilish
      final rgb = _cameraImageToImage(image, sensorOrientation);
      if (rgb == null) {
        _isBusy = false;
        return;
      }

      // 2) Letterbox 640×640 + Float32 NCHW normalizatsiya
      final letterbox = _letterbox(rgb, _kInputSize);

      // 3) Inference
      final inputTensor = OrtValueTensor.createTensorWithDataList(
        letterbox.tensor,
        [1, 3, _kInputSize, _kInputSize],
      );
      final runOptions = OrtRunOptions();
      final outputs =
          await _session!.runAsync(runOptions, {'images': inputTensor});
      inputTensor.release();
      runOptions.release();

      if (outputs == null || outputs.length < 2) {
        _isBusy = false;
        return;
      }

      // 4) Outputlarni parse qilish
      final out0 = outputs[0]?.value;
      final out1 = outputs[1]?.value;
      if (out0 == null || out1 == null) {
        _releaseOutputs(outputs);
        _isBusy = false;
        return;
      }

      final detections = _parseDetections(
        out0 as List<List<List<double>>>,
        out1 as List<List<List<List<double>>>>,
        srcW: rgb.width.toDouble(),
        srcH: rgb.height.toDouble(),
        letterbox: letterbox,
      );

      _releaseOutputs(outputs);

      currentObjects = detections;
      updateCount++;
    } catch (e, st) {
      debugPrint('[VisionAI] Inference xato: $e\n$st');
      currentObjects = [];
      updateCount++;
    } finally {
      lastInferenceMs = DateTime.now().difference(t0).inMilliseconds;
      _isBusy = false;
    }
  }

  void _releaseOutputs(List<OrtValue?> outs) {
    for (final v in outs) {
      try {
        v?.release();
      } catch (_) {}
    }
  }

  void dispose() {
    try {
      _session?.release();
    } catch (_) {}
    _session = null;
    _isInitialized = false;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // YUV420 → RGB konvertatsiya (CameraImage → image.Image)
  // ═════════════════════════════════════════════════════════════════════════
  /// Android CameraImage YUV420 → RGB image.Image.
  /// Sensor orientation ga ko'ra avtomatik aylantiriladi (portret rejim).
  img.Image? _cameraImageToImage(CameraImage image, int sensorOrientation) {
    try {
      final w = image.width;
      final h = image.height;

      if (image.format.group != ImageFormatGroup.yuv420 ||
          image.planes.length < 3) {
        return null;
      }

      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];

      final yRow = yPlane.bytesPerRow;
      final uvRow = uPlane.bytesPerRow;
      final uvPix = uPlane.bytesPerPixel ?? 1;

      final yBytes = yPlane.bytes;
      final uBytes = uPlane.bytes;
      final vBytes = vPlane.bytes;

      final dst = img.Image(width: w, height: h);

      for (int y = 0; y < h; y++) {
        final yOff = y * yRow;
        final uvOff = (y >> 1) * uvRow;
        for (int x = 0; x < w; x++) {
          final yIdx = yOff + x;
          final uvIdx = uvOff + (x >> 1) * uvPix;
          if (yIdx >= yBytes.length ||
              uvIdx >= uBytes.length ||
              uvIdx >= vBytes.length) {
            continue;
          }

          final yVal = yBytes[yIdx];
          final uVal = uBytes[uvIdx];
          final vVal = vBytes[uvIdx];

          // BT.601 YUV → RGB
          final yc = yVal & 0xFF;
          final uc = (uVal & 0xFF) - 128;
          final vc = (vVal & 0xFF) - 128;

          int r = (yc + (1.370705 * vc)).round();
          int g = (yc - (0.337633 * uc) - (0.698001 * vc)).round();
          int b = (yc + (1.732446 * uc)).round();

          if (r < 0) {
            r = 0;
          } else if (r > 255) {
            r = 255;
          }
          if (g < 0) {
            g = 0;
          } else if (g > 255) {
            g = 255;
          }
          if (b < 0) {
            b = 0;
          } else if (b > 255) {
            b = 255;
          }

          dst.setPixelRgb(x, y, r, g, b);
        }
      }

      // Sensor orientation kompensatsiyasi
      img.Image rotated;
      switch (sensorOrientation) {
        case 90:
          rotated = img.copyRotate(dst, angle: 90);
          break;
        case 180:
          rotated = img.copyRotate(dst, angle: 180);
          break;
        case 270:
          rotated = img.copyRotate(dst, angle: 270);
          break;
        default:
          rotated = dst;
      }
      return rotated;
    } catch (e) {
      debugPrint('[VisionAI] YUV→RGB xato: $e');
      return null;
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // LETTERBOX (aspect-ratio saqlovchi resize) + Float32 NCHW
  // ═════════════════════════════════════════════════════════════════════════
  _Letterbox _letterbox(img.Image src, int target) {
    final srcW = src.width.toDouble();
    final srcH = src.height.toDouble();
    final scale = math.min(target / srcW, target / srcH);
    final newW = (srcW * scale).round();
    final newH = (srcH * scale).round();
    final padX = (target - newW) ~/ 2;
    final padY = (target - newH) ~/ 2;

    final resized = img.copyResize(src,
        width: newW, height: newH, interpolation: img.Interpolation.linear);

    // Float32 NCHW buffer
    final tensor = Float32List(3 * target * target);
    final planeSize = target * target;

    // 114 = YOLO standart letterbox padding
    for (int i = 0; i < planeSize; i++) {
      tensor[i] = 114.0 / 255.0;
      tensor[planeSize + i] = 114.0 / 255.0;
      tensor[2 * planeSize + i] = 114.0 / 255.0;
    }

    for (int y = 0; y < newH; y++) {
      for (int x = 0; x < newW; x++) {
        final p = resized.getPixel(x, y);
        final r = p.r.toDouble() / 255.0;
        final g = p.g.toDouble() / 255.0;
        final b = p.b.toDouble() / 255.0;
        final dstX = x + padX;
        final dstY = y + padY;
        final idx = dstY * target + dstX;
        tensor[idx] = r;
        tensor[planeSize + idx] = g;
        tensor[2 * planeSize + idx] = b;
      }
    }

    return _Letterbox(
      tensor: tensor,
      scale: scale,
      padX: padX.toDouble(),
      padY: padY.toDouble(),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // POST-PROCESSING — NMS-Free output parsing + mask sintez
  // ═════════════════════════════════════════════════════════════════════════
  List<DetectedObject> _parseDetections(
      List<List<List<double>>> out0, List<List<List<List<double>>>> out1,
      {required double srcW,
      required double srcH,
      required _Letterbox letterbox}) {
    final List<DetectedObject> result = [];
    final rows = out0[0]; // [300][38]
    final proto = out1[0]; // [32][160][160]

    for (int i = 0; i < rows.length && i < _kMaxDetections; i++) {
      final row = rows[i];
      if (row.length < _kRowStride) continue;

      final conf = row[4];
      if (conf < confThreshold) continue;

      final classIdx = row[5].round();
      if (classIdx < 0 || classIdx >= _kNumClasses) continue;

      // bbox xyxy (640px makonida) → original image (px) ga aylantirish
      final x1m = row[0];
      final y1m = row[1];
      final x2m = row[2];
      final y2m = row[3];

      final x1 = ((x1m - letterbox.padX) / letterbox.scale).clamp(0.0, srcW);
      final y1 = ((y1m - letterbox.padY) / letterbox.scale).clamp(0.0, srcH);
      final x2 = ((x2m - letterbox.padX) / letterbox.scale).clamp(0.0, srcW);
      final y2 = ((y2m - letterbox.padY) / letterbox.scale).clamp(0.0, srcH);

      if (x2 - x1 < 2 || y2 - y1 < 2) continue;

      final box = Rect.fromLTRB(x1, y1, x2, y2);

      // Mask koefitsientlari
      final coeffs = List<double>.generate(_kMaskCoeffs, (k) => row[6 + k],
          growable: false);

      // Mask sintezi: sum(coeffs[k] * proto[k][y][x]) → sigmoid → 160×160
      // Tezroq variant: faqat bbox sohasidagi piksellarni hisoblaymiz.
      final polygon = _buildMaskPolygon(
        coeffs: coeffs,
        proto: proto,
        boxModel: Rect.fromLTRB(x1m, y1m, x2m, y2m),
        letterbox: letterbox,
        srcW: srcW,
        srcH: srcH,
      );

      final rawLabel =
          classIdx < _cocoLabels.length ? _cocoLabels[classIdx] : 'unknown';

      result.add(DetectedObject(
        label: _localizeLabel(rawLabel),
        rawLabel: rawLabel,
        classIndex: classIdx,
        confidence: conf,
        box: box,
        polygons: polygon,
      ));
    }

    // confidence bo'yicha tartiblash
    result.sort((a, b) => b.confidence.compareTo(a.confidence));
    return result;
  }

  /// Mask koefitsientlaridan 160×160 mask sintezi va undan poligon (kontur)
  /// chiqarish. Poligon — bbox bo'ylab teng oraliqdagi ~24 nuqta.
  /// Telefon CPU sini qiynamaslik uchun faqat bbox ichidagi piksellar hisoblanadi.
  List<Offset>? _buildMaskPolygon({
    required List<double> coeffs,
    required List<List<List<double>>> proto,
    required Rect boxModel, // 640px makonida (letterbox)
    required _Letterbox letterbox,
    required double srcW,
    required double srcH,
  }) {
    try {
      // boxModel → 160×160 mask makonida ROI
      const scaleProto = _kProtoSize / _kInputSize; // 0.25
      final mx1 =
          (boxModel.left * scaleProto).floor().clamp(0, _kProtoSize - 1);
      final my1 = (boxModel.top * scaleProto).floor().clamp(0, _kProtoSize - 1);
      final mx2 = (boxModel.right * scaleProto).ceil().clamp(0, _kProtoSize);
      final my2 = (boxModel.bottom * scaleProto).ceil().clamp(0, _kProtoSize);
      final mw = mx2 - mx1;
      final mh = my2 - my1;
      if (mw <= 1 || mh <= 1) return null;

      // 160×160 maska ichidan bbox kesimini hisoblash (sigmoid linear sum)
      // Optimizatsiya: matritsa[ch][y][x] indeksini har gal qaytadan olmaslik
      // uchun har bir kanalga bir martalik pointerni o'rab olamiz.
      final mask = Float32List(mw * mh);
      for (int c = 0; c < _kMaskCoeffs; c++) {
        final w = coeffs[c];
        if (w.abs() < 1e-4) {
          continue; // kichik koefitsientlarni o'tkazib yuboramiz
        }
        final protoCh = proto[c];
        for (int yy = 0; yy < mh; yy++) {
          final protoRow = protoCh[my1 + yy];
          final dstOff = yy * mw;
          for (int xx = 0; xx < mw; xx++) {
            mask[dstOff + xx] += w * protoRow[mx1 + xx];
          }
        }
      }

      // Sigmoid + binarizatsiya
      final binMask = Uint8List(mw * mh);
      for (int i = 0; i < mask.length; i++) {
        final s = 1.0 / (1.0 + math.exp(-mask[i]));
        binMask[i] = s > maskThreshold ? 1 : 0;
      }

      // Kontur — bbox bo'ylab teng oraliqdagi 24 nuqta. Har vertikal/gorizontal
      // skanerlash chizig'idan mask chegarasini topib, original image
      // koordinatalariga qaytaramiz.
      const samples = 24;
      final pts = <Offset>[];

      // Yuqori chegara (chap→o'ng)
      for (int s = 0; s < samples; s++) {
        final fx = s / (samples - 1);
        final mxLocal = (fx * (mw - 1)).round();
        int? hitY;
        for (int yy = 0; yy < mh; yy++) {
          if (binMask[yy * mw + mxLocal] == 1) {
            hitY = yy;
            break;
          }
        }
        if (hitY != null) {
          pts.add(
              _maskToImage(mx1 + mxLocal, my1 + hitY, letterbox, srcW, srcH));
        }
      }

      // O'ng chegara (yuqori→past)
      for (int s = 1; s < samples - 1; s++) {
        final fy = s / (samples - 1);
        final myLocal = (fy * (mh - 1)).round();
        int? hitX;
        for (int xx = mw - 1; xx >= 0; xx--) {
          if (binMask[myLocal * mw + xx] == 1) {
            hitX = xx;
            break;
          }
        }
        if (hitX != null) {
          pts.add(
              _maskToImage(mx1 + hitX, my1 + myLocal, letterbox, srcW, srcH));
        }
      }

      // Pastki chegara (o'ng→chap)
      for (int s = samples - 1; s >= 0; s--) {
        final fx = s / (samples - 1);
        final mxLocal = (fx * (mw - 1)).round();
        int? hitY;
        for (int yy = mh - 1; yy >= 0; yy--) {
          if (binMask[yy * mw + mxLocal] == 1) {
            hitY = yy;
            break;
          }
        }
        if (hitY != null) {
          pts.add(
              _maskToImage(mx1 + mxLocal, my1 + hitY, letterbox, srcW, srcH));
        }
      }

      // Chap chegara (past→yuqori)
      for (int s = samples - 2; s > 0; s--) {
        final fy = s / (samples - 1);
        final myLocal = (fy * (mh - 1)).round();
        int? hitX;
        for (int xx = 0; xx < mw; xx++) {
          if (binMask[myLocal * mw + xx] == 1) {
            hitX = xx;
            break;
          }
        }
        if (hitX != null) {
          pts.add(
              _maskToImage(mx1 + hitX, my1 + myLocal, letterbox, srcW, srcH));
        }
      }

      return pts.length >= 6 ? pts : null;
    } catch (e) {
      debugPrint('[VisionAI] Mask sintezda xato: $e');
      return null;
    }
  }

  /// 160×160 mask koordinatasi → original image piksel koordinatasi
  Offset _maskToImage(int mx, int my, _Letterbox lb, double srcW, double srcH) {
    // mask (160) → letterbox (640) → image source
    const scaleProtoInv = _kInputSize / _kProtoSize; // 4.0
    final x640 = mx * scaleProtoInv;
    final y640 = my * scaleProtoInv;
    final imgX = ((x640 - lb.padX) / lb.scale).clamp(0.0, srcW);
    final imgY = ((y640 - lb.padY) / lb.scale).clamp(0.0, srcH);
    return Offset(imgX, imgY);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MA'LUMOT MODELI
// ═══════════════════════════════════════════════════════════════════════════════

class DetectedObject {
  /// Lokalizatsiya qilingan label ([Texnik Xodim] kabi)
  final String label;

  /// Original COCO inglizcha label
  final String rawLabel;

  /// COCO klass indeksi (0..79)
  final int classIndex;
  final double confidence;

  /// Original image piksel makonidagi bbox
  final Rect box;

  /// Original image piksel makonidagi mask poligoni (Drawn directly)
  final List<Offset>? polygons;

  DetectedObject({
    required this.label,
    required this.rawLabel,
    required this.classIndex,
    required this.confidence,
    required this.box,
    required this.polygons,
  });
}

class _Letterbox {
  final Float32List tensor;
  final double scale;
  final double padX;
  final double padY;
  _Letterbox({
    required this.tensor,
    required this.scale,
    required this.padX,
    required this.padY,
  });
}
