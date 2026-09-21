import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// One task on the dashboard, with the lecture it came from.
///
/// Tapping opens that lecture rather than ticking the box: the tick lives with
/// the notes, which is where the markdown that holds it is rewritten.
class HomeTaskRow extends StatelessWidget {
  final String text;
  final bool done;

  /// Subject or lecture title, so a task is traceable to its source.
  final String context;
  final VoidCallback onTap;

  const HomeTaskRow({
    super.key,
    required this.text,
    required this.done,
    required this.context,
    required this.onTap,
  });

  @override
  Widget build(BuildContext buildContext) {
    final theme = Theme.of(buildContext);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(
              done
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
              size: 22,
              color: done ? AppColors.success : AppColors.borderStrong,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: done ? AppColors.textMuted : AppColors.textPrimary,
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
