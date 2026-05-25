import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../models/material_profile.dart';
import '../services/material_service.dart';

/// HUD da kompakt material indikatori — tap bo'lganda BottomSheet ochiladi.
class MaterialChip extends StatelessWidget {
  const MaterialChip({super.key});

  @override
  Widget build(BuildContext context) {
    final service = MaterialService();
    return ValueListenableBuilder<MaterialProfile>(
      valueListenable: service.current,
      builder: (context, profile, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: service.isManualOverride,
          builder: (context, isManual, __) {
            return GestureDetector(
              onTap: () => showMaterialPickerSheet(context),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: profile.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: profile.color.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(profile.icon, color: profile.color, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      profile.displayName.toUpperCase(),
                      style: TextStyle(
                        color: profile.color,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: isManual
                            ? AppTheme.warning.withValues(alpha: 0.25)
                            : AppTheme.success.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isManual ? 'QO\'L' : 'AUTO',
                        style: TextStyle(
                          color: isManual
                              ? AppTheme.warning
                              : AppTheme.success,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Material tanlash uchun BottomSheet — 12 ta preset grid.
void showMaterialPickerSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.background,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => const _MaterialPickerSheet(),
  );
}

class _MaterialPickerSheet extends StatelessWidget {
  const _MaterialPickerSheet();

  @override
  Widget build(BuildContext context) {
    final service = MaterialService();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: ValueListenableBuilder<MaterialProfile>(
          valueListenable: service.current,
          builder: (context, currentProfile, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.textMuted.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.category_outlined,
                        color: AppTheme.primary, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'MATERIAL TANLASH',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        service.enableAutoInfer();
                      },
                      icon: const Icon(Icons.auto_awesome,
                          color: AppTheme.success, size: 16),
                      label: const Text('AUTO',
                          style: TextStyle(
                              color: AppTheme.success,
                              fontSize: 11,
                              fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Hozir: ${currentProfile.displayName} · Kritik amplituda: ${currentProfile.criticalAmplitudeMm.toStringAsFixed(1)} mm · Rezonans: ${currentProfile.resonanceMinHz.toStringAsFixed(0)}–${currentProfile.resonanceMaxHz.toStringAsFixed(0)} Hz',
                  style: const TextStyle(
                      color: AppTheme.textMuted, fontSize: 11),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.95,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: MaterialPresets.all.length,
                    itemBuilder: (ctx, i) {
                      final p = MaterialPresets.all[i];
                      final isSelected = p.id == currentProfile.id;
                      return _MaterialCard(
                        profile: p,
                        isSelected: isSelected,
                        onTap: () {
                          service.setManual(p);
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MaterialCard extends StatelessWidget {
  final MaterialProfile profile;
  final bool isSelected;
  final VoidCallback onTap;

  const _MaterialCard({
    required this.profile,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected
              ? profile.color.withValues(alpha: 0.2)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? profile.color
                : profile.color.withValues(alpha: 0.25),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(profile.icon, color: profile.color, size: 28),
            const SizedBox(height: 6),
            Text(
              profile.displayName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSelected
                    ? AppTheme.textPrimary
                    : AppTheme.textSecondary,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${profile.criticalAmplitudeMm.toStringAsFixed(1)} mm',
              style: TextStyle(
                color: profile.color,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
