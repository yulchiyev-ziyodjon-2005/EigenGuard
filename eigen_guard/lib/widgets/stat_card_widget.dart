import 'package:flutter/material.dart';
import '../core/app_theme.dart';

/// Statistika kartochkasi — Chastota, Amplituda, Xatolik kabi parametrlar uchun
class StatCardWidget extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color? color;

  const StatCardWidget({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = color ?? AppTheme.primary;

    return Container(
      decoration: AppTheme.glassCardWithGlow(cardColor),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: cardColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: cardColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: TextStyle(
                    color: cardColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                unit,
                style: TextStyle(
                  color: cardColor.withValues(alpha: 0.6),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
