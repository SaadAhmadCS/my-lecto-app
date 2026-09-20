import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// Storage left and how much of the lecture is safely written to disk.
///
/// There is no connectivity indicator: the app has no network permission, so
/// online or offline makes no difference to anything it does.
class StorageStatusBar extends StatelessWidget {
  final int availableMB;
  final bool isStorageLow;
  final int completedChunks;

  const StorageStatusBar({
    super.key,
    required this.availableMB,
    required this.isStorageLow,
    required this.completedChunks,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: isStorageLow
            ? AppColors.warningBg
            : AppColors.darkSurface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isStorageLow
              ? AppColors.warning.withValues(alpha: 0.3)
              : AppColors.textTertiaryDark.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Storage
          _buildIndicator(
            icon: Icons.storage_rounded,
            label: _formatStorage(),
            color: isStorageLow ? AppColors.warning : AppColors.textSecondaryDark,
          ),

          // Separator
          Container(
            height: 16,
            width: 1,
            color: AppColors.textTertiaryDark.withValues(alpha: 0.2),
          ),

          // Parts written to disk. Nothing is uploaded, so a cloud icon here
          // would suggest something the app does not do.
          _buildIndicator(
            icon: Icons.save_rounded,
            label: '$completedChunks saved',
            color: AppColors.success,
          ),
        ],
      ),
    );
  }

  Widget _buildIndicator({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }

  String _formatStorage() {
    if (availableMB < 0) return 'Unknown';
    if (availableMB >= 1024) {
      return '${(availableMB / 1024).toStringAsFixed(1)}GB';
    }
    return '${availableMB}MB';
  }
}
