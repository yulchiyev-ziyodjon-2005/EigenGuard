import 'package:flutter/foundation.dart';
import '../models/material_profile.dart';

/// MaterialService — joriy material profili Singleton.
///
/// • Auto-infer: YOLO label (COCO klassi) dan material tipini taxminlaydi.
/// • Manual override: foydalanuvchi tanlaganda auto-infer to'xtaydi.
/// • `current` ga `ValueListenableBuilder` orqali ulanib turish mumkin.
class MaterialService {
  static final MaterialService _instance = MaterialService._internal();
  factory MaterialService() => _instance;
  MaterialService._internal();

  /// Joriy material profili
  final ValueNotifier<MaterialProfile> current =
      ValueNotifier<MaterialProfile>(MaterialPresets.universal);

  /// Foydalanuvchi qo'lda tanladimi (true bo'lsa auto-infer ishlamaydi)
  final ValueNotifier<bool> isManualOverride = ValueNotifier<bool>(false);

  /// So'nggi YOLO label (debug uchun)
  String? _lastInferredFrom;
  String? get lastInferredFrom => _lastInferredFrom;

  // ═════════════════════════════════════════════════════════════════════════
  // YOLO COCO label → MaterialProfile mapping
  // ═════════════════════════════════════════════════════════════════════════
  /// COCO 80 klassidagi har bir label uchun eng ehtimoliy material.
  /// Aniqlanmagan label → universal.
  static const Map<String, String> _labelToMaterialId = {
    // Yog'och predmetlar (mebel, tabiiy)
    'chair': 'wood',
    'bench': 'wood',
    'couch': 'wood',
    'dining table': 'wood',
    'bed': 'wood',
    'book': 'wood',
    'potted plant': 'wood',

    // Po'lat / metall sanoat
    'refrigerator': 'steel',
    'oven': 'steel',
    'microwave': 'steel',
    'toaster': 'steel',
    'sink': 'steel',
    'fire hydrant': 'steel',
    'parking meter': 'steel',
    'truck': 'steel',
    'bus': 'steel',
    'train': 'steel',
    'airplane': 'aluminum',
    'car': 'steel',
    'motorcycle': 'steel',
    'bicycle': 'aluminum',
    'boat': 'composite',

    // Shisha
    'wine glass': 'glass',
    'bottle': 'glass',
    'vase': 'ceramic',
    'cup': 'ceramic',

    // Plastik / kompozit
    'frisbee': 'plastic',
    'sports ball': 'composite',
    'kite': 'composite',
    'surfboard': 'composite',
    'snowboard': 'composite',
    'skis': 'composite',
    'skateboard': 'composite',
    'tennis racket': 'composite',

    // Elektronika (po'lat korpus + ceramic ichi — eng yaqin: aluminum)
    'tv': 'aluminum',
    'laptop': 'aluminum',
    'cell phone': 'aluminum',
    'keyboard': 'plastic',
    'mouse': 'plastic',
    'remote': 'plastic',
    'clock': 'steel',

    // Ceramic / chinni
    'bowl': 'ceramic',
    'toilet': 'ceramic',

    // Aralash — universal
    'traffic light': 'aluminum',
    'stop sign': 'aluminum',
    'umbrella': 'composite',
    'handbag': 'composite',
    'backpack': 'composite',
    'suitcase': 'composite',
    'tie': 'composite',

    // Tirik mavjudotlar va boshqalar — universal
    'person': 'universal',
    'cat': 'universal',
    'dog': 'universal',
    'bird': 'universal',
    'horse': 'universal',
    'sheep': 'universal',
    'cow': 'universal',
    'elephant': 'universal',
    'bear': 'universal',
    'zebra': 'universal',
    'giraffe': 'universal',
  };

  /// YOLO modelidan kelgan raw label (inglizcha, lowercase) asosida
  /// material profilini avtomatik aniqlash. Foydalanuvchi qo'lda tanlagan
  /// bo'lsa — bu ishlamaydi.
  void inferFromYoloLabel(String? rawLabel) {
    if (isManualOverride.value) return;
    if (rawLabel == null || rawLabel.isEmpty) return;

    final normalized = rawLabel.trim().toLowerCase();
    if (_lastInferredFrom == normalized) return;
    _lastInferredFrom = normalized;

    final materialId = _labelToMaterialId[normalized] ?? 'universal';
    final newProfile = MaterialPresets.byId(materialId);

    if (current.value.id != newProfile.id) {
      current.value = newProfile;
    }
  }

  /// Foydalanuvchi qo'lda material tanlaydi.
  /// Bu paytda auto-infer to'xtaydi.
  void setManual(MaterialProfile profile) {
    isManualOverride.value = true;
    current.value = profile;
  }

  /// Auto-infer ni qayta yoqish (manual rejimni o'chirish).
  void enableAutoInfer() {
    isManualOverride.value = false;
    _lastInferredFrom = null;
  }

  /// Reset — universal ga qaytarish va auto-infer ni yoqish
  void reset() {
    isManualOverride.value = false;
    _lastInferredFrom = null;
    current.value = MaterialPresets.universal;
  }
}
