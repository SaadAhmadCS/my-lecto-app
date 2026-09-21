import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// Avatar, today's date, the recording streak and a bell.
class HomeHeader extends StatelessWidget {
  final String name;
  final int streakDays;

  /// Recordings still waiting for notes — the only thing the bell reports.
  final int needsAttention;
  final VoidCallback onAvatarTap;
  final VoidCallback onBellTap;

  const HomeHeader({
    super.key,
    required this.name,
    required this.streakDays,
    required this.needsAttention,
    required this.onAvatarTap,
    required this.onBellTap,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final theme = Theme.of(context);

    return Row(
      children: [
        // The Lecto mascot stands in for a profile photo; tapping it still
        // sets the name used in the greeting.
        Semantics(
          label: name.isEmpty ? 'Set your name' : 'Profile: $name',
          button: true,
          child: GestureDetector(
            onTap: onAvatarTap,
            child: SvgPicture.asset(
              'assets/images/avatar_mascot.svg',
              width: 46,
              height: 46,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _weekday(now).toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
              Text(
                '${now.day} ${_month(now)}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        // Only shown once there is a streak to be proud of.
        if (streakDays > 0) ...[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: AppColors.tintYellow,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.bolt_rounded,
                  size: 16,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 2),
                Text(
                  '$streakDays',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        _BellButton(count: needsAttention, onTap: onBellTap),
      ],
    );
  }

  static String _weekday(DateTime date) => const [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ][date.weekday - 1];

  static String _month(DateTime date) => const [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ][date.month - 1];
}

class _BellButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _BellButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: count == 0 ? 'Nothing needs attention' : '$count things need you',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.notifications_none_rounded,
                size: 22,
                color: AppColors.textPrimary,
              ),
            ),
            // A dot rather than a number: the count is already on the pill.
            if (count > 0)
              Positioned(
                right: 2,
                top: 2,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.background, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
