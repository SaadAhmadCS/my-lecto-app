import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/home_digest.dart';

/// One task on the dashboard, with its subject and how long is left.
///
/// Tapping opens the lecture it came from rather than ticking the box: the
/// tick lives with the notes, where the markdown holding it is rewritten.
class HomeTaskRow extends StatelessWidget {
  final HomeTask task;
  final VoidCallback onTap;

  const HomeTaskRow({super.key, required this.task, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badge = _badge();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          color: task.done ? AppColors.surfaceMuted : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            _Tick(done: task.done),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: task.done
                          ? AppColors.textMuted
                          : AppColors.textPrimary,
                      decoration:
                          task.done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: task.done
                              ? AppColors.textMuted
                              : AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          task.subjectName ?? task.recordingTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: AppSpacing.sm),
              badge,
            ],
          ],
        ),
      ),
    );
  }

  /// How long is left, when the lecture's notes gave a date to work from.
  Widget? _badge() {
    if (task.done) return null;
    final due = task.dueAt;
    if (due == null) return null;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = DateTime(due.year, due.month, due.day).difference(today).inDays;

    final (label, background, ink) = switch (days) {
      < 0 => ('Overdue', AppColors.errorBg, AppColors.error),
      0 => ('Today', AppColors.tintYellow, AppColors.warning),
      1 => ('Tomorrow', AppColors.tintYellow, AppColors.warning),
      < 7 => ('${days}d left', AppColors.surfaceMuted, AppColors.textSecondary),
      _ => ('', Colors.transparent, Colors.transparent),
    };

    if (label.isEmpty) return null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: ink,
        ),
      ),
    );
  }
}

class _Tick extends StatelessWidget {
  final bool done;

  const _Tick({required this.done});

  @override
  Widget build(BuildContext context) {
    if (done) {
      return Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppColors.success,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check_rounded,
            size: 16, color: AppColors.textOnPrimary),
      );
    }

    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.borderStrong, width: 2),
      ),
    );
  }
}
