import 'package:flutter/material.dart';

/// DepthService — Sanoat uskunasi qanday uzoqlikda ekanini topish (Proksi LiDAR)
/// U obyektni bounding boxiga (Rect) asoslanib monokulyar chuqurlik topadi (Monocular Depth Estimation).
/// So'ng Optical Flow bergan pikselli tebranishi Dx, Dy ni haqiqiy millimetrlarga (mm) o'girib beradi.
class DepthService {
  // O'rtacha telefon kamerasining ekvivalent fokus uzunligi (piksellarda)
  final double _focalLength = 800.0;

  // Haqiqiy obyektning taxminiy o'lchami (Masalan Nasos: 500 mm balandligi)
  final double _realObjectHeightMm = 500.0;

  /// Kadrda ko'rinayotgan obyekt Bounding Box asnosida kameradan obyektgacha bo'lgan masofani (Z) mm da hisoblash
  double estimateDistance(Rect? boundingBox) {
    if (boundingBox == null || boundingBox.height <= 0) {
      return 1000.0; // Obyekt topilmasa standart 1 metr (1000mm)
    }

    // Z (Masofa) = (f * H) / h
    return (_focalLength * _realObjectHeightMm) / boundingBox.height;
  }

  /// Kameradagi piksellar asosida o'lchangan amplitudani xaqiqiy millimetr / sekund o'lchoviga o'girish.
  /// magnitudePixels — Optical Flow + Kalman dagi `processFrame` dan qaytgan natija.
  double convertPixelShiftToMillimeters(
      double magnitudePixels, Rect? boundingBox) {
    if (magnitudePixels <= 0) return 0.0;

    // Chuqurlikni topamiz
    double distanceMm = estimateDistance(boundingBox);

    // Haqiqiy ko'chish (mm) = (dx * Z) / f
    return (magnitudePixels * distanceMm) / _focalLength;
  }
}
