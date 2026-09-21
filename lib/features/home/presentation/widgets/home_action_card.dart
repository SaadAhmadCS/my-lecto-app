import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

/// One of the tiles on the dashboard.
///
/// The icon sits large and low-contrast behind the label, so the card reads as
/// a picture first and a button second.
class HomeActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  /// Makes the card fill the height of two stacked cards beside it.
  final bool tall;

  const HomeActionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.tall = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: Container(
        height: tall ? 196 : 92,
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: Stack(
          children: [
            // Oversized and translucent: decoration, not an affordance.
            Positioned(
              right: tall ? -8 : -12,
              bottom: tall ? -10 : -14,
              child: Icon(
                icon,
                size: tall ? 88 : 56,
                color: foreground.withValues(alpha: 0.22),
              ),
            ),
            // The text keeps clear of the icon rather than sitting on it.
            Padding(
              padding: EdgeInsets.only(right: tall ? 0 : 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: foreground.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w500,
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
