import 'package:flutter/material.dart';

/// EigenGuard Professional Dark Theme
/// Premium monitoring dastur uchun maxsus dizayn tizimi
class AppTheme {
  AppTheme._();

  // ============================================================
  // Ranglar
  // ============================================================
  static const Color background = Color(0xFF0A0E1A);
  static const Color surface = Color(0xFF111827);
  static const Color surfaceLight = Color(0xFF1E293B);
  static const Color cardColor = Color(0xFF151D2E);

  static const Color primary = Color(0xFF00E5FF);
  static const Color primaryDark = Color(0xFF0097A7);
  static const Color secondary = Color(0xFF7C3AED);

  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color critical = Color(0xFFDC2626);

  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  static const Color gridLine = Color(0xFF1E293B);
  static const Color chartLine = Color(0xFF00E5FF);
  static const Color chartDot = Color(0xFF06B6D4);
  static const Color chartFill = Color(0x1A00E5FF);

  // ============================================================
  // Risk Level ranglari
  // ============================================================
  static Color getRiskColor(double riskPercent) {
    if (riskPercent < 30) return success;
    if (riskPercent < 60) return warning;
    if (riskPercent < 85) return const Color(0xFFFF6B35);
    return danger;
  }

  static String getRiskLabel(double riskPercent) {
    if (riskPercent < 30) return 'NORMAL';
    if (riskPercent < 60) return 'OGOHLANTIRISH';
    if (riskPercent < 85) return 'YUQORI XAVF';
    return 'KRITIK';
  }

  // ============================================================
  // Dekoratsiyalar
  // ============================================================
  static BoxDecoration get glassCard => BoxDecoration(
    color: cardColor.withValues(alpha: 0.7),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: primary.withValues(alpha: 0.1), width: 1),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.3),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  );

  static BoxDecoration glassCardWithGlow(Color glowColor) => BoxDecoration(
    color: cardColor.withValues(alpha: 0.7),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: glowColor.withValues(alpha: 0.2), width: 1),
    boxShadow: [
      BoxShadow(
        color: glowColor.withValues(alpha: 0.1),
        blurRadius: 20,
        offset: const Offset(0, 4),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.3),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  );

  // ============================================================
  // ThemeData
  // ============================================================
  static ThemeData get darkTheme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    primaryColor: primary,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      secondary: secondary,
      surface: surface,
      error: danger,
    ),
    fontFamily: null, // Platforma default fonti (Roboto Android, SF Pro iOS)
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
      iconTheme: IconThemeData(color: primary),
    ),
    cardTheme: CardThemeData(
      color: cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        color: textPrimary,
        fontSize: 28,
        fontWeight: FontWeight.bold,
      ),
      headlineMedium: TextStyle(
        color: textPrimary,
        fontSize: 22,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: TextStyle(
        color: textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: TextStyle(
        color: textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      bodyLarge: TextStyle(color: textPrimary, fontSize: 15),
      bodyMedium: TextStyle(color: textSecondary, fontSize: 13),
      labelLarge: TextStyle(
        color: primary,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    ),
  );
}
