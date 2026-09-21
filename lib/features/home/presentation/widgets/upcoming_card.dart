import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/home_digest.dart';

/// A dated commitment in the "Coming up" strip.
///
/// Colour follows the kind, so a quiz and an assignment are tellable apart
/// without reading.
class UpcomingCard extends StatelessWidget {
  final UpcomingItem item;
  final VoidCallback onTap;

  /// Fills the available width instead of sitting at the strip's fixed size,
  /// for the stacked list on the Quizzes screen.
  final bool fullWidth;

  const UpcomingCard({
    super.key,
    required this.item,
    required this.onTap,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (background, ink) = switch (item.kind) {
      UpcomingKind.quiz => (AppColors.tintLavender, AppColors.inkLavender),
      UpcomingKind.assignment => (AppColors.tintPink, AppColors.error),
      UpcomingKind.other => (AppColors.tintCream, AppColors.warning),
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: Container(
        width: fullWidth ? double.infinity : 224,
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    item.kind.label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: ink,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  _countdown(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ink.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                color: ink,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (item.subjectName != null) item.subjectName!,
                _dateLabel(),
              ].where((part) => part.isNotEmpty).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: ink.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _countdown() {
    final days = item.daysAway;
    return switch (days) {
      null => '',
      0 => 'Today',
      1 => 'Tomorrow',
      _ => 'in $days days',
    };
  }

  String _dateLabel() {
    final date = item.date;
    if (date == null) return item.rawDate;

    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${days[date.weekday - 1]} ${date.day} ${months[date.month - 1]}';
  }
}
