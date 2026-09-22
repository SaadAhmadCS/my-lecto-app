import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/ui/motion.dart';
import '../../data/home_digest.dart';

/// One dated thing from the notes: a calendar-page date block, what it is,
/// which subject, and how long until it.
class DeadlineTile extends StatelessWidget {
  final UpcomingItem item;
  final VoidCallback onTap;

  const DeadlineTile({super.key, required this.item, required this.onTap});

  static const _months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];
  static const _days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  /// Background and ink for each kind, matching the Home cards.
  static (Color, Color) kindColors(UpcomingKind kind) => switch (kind) {
    UpcomingKind.quiz => (AppColors.tintLavender, AppColors.inkLavender),
    UpcomingKind.assignment => (AppColors.tintPink, const Color(0xFF97245C)),
    UpcomingKind.other => (AppColors.tintCream, const Color(0xFFA66E0A)),
  };

  @override
  Widget build(BuildContext context) {
    final (tint, ink) = kindColors(item.kind);
    final date = item.date;

    return Pressable(
      scale: 0.98,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () {
            Feel.tap();
            onTap();
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                // Tear-off calendar page.
                Container(
                  width: 58,
                  height: 64,
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: date == null
                      ? Center(
                          child: Text(
                            '?',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: ink,
                            ),
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _days[date.weekday - 1],
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: ink.withValues(alpha: 0.75),
                              ),
                            ),
                            Text(
                              '${date.day}',
                              style: TextStyle(
                                fontSize: 24,
                                height: 1.1,
                                fontWeight: FontWeight.w900,
                                color: ink,
                              ),
                            ),
                            Text(
                              _months[date.month - 1],
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: ink.withValues(alpha: 0.75),
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.kind.label.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.9,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (item.subjectName != null) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: AppColors.fromHex(item.subjectColor),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                item.subjectName!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                CountdownBadge(daysAway: item.daysAway),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Today", "Tomorrow", "3 days": warmer as it gets closer.
class CountdownBadge extends StatelessWidget {
  final int? daysAway;

  const CountdownBadge({super.key, required this.daysAway});

  @override
  Widget build(BuildContext context) {
    final days = daysAway;
    if (days == null) return const SizedBox.shrink();

    final (label, background, ink) = switch (days) {
      < 0 => ('Past', AppColors.surfaceMuted, AppColors.textMuted),
      0 => ('Today', AppColors.primary, AppColors.textOnPrimary),
      1 => ('Tomorrow', const Color(0xFFFDEEE7), const Color(0xFFBF4922)),
      <= 3 => ('$days days', const Color(0xFFFEF4DC), const Color(0xFFA66E0A)),
      _ => ('$days days', AppColors.surfaceMuted, AppColors.textSecondary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: ink),
      ),
    );
  }
}
