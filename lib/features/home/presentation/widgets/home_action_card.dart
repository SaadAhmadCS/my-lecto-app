import 'package:flutter/material.dart';

import '../../../../core/ui/motion.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// One tile in the dashboard's 2×2 grid.
///
/// A spot illustration sits in the bottom-right corner, so the card reads as a
/// picture first and a button second.
class HomeActionCard extends StatelessWidget {
  final String title;
  final String subtitle;

  /// SVG asset drawn in the corner.
  final String illustration;
  final Color background;

  /// Overrides [background] — the Record tile is a coral gradient.
  final Gradient? gradient;
  final Color foreground;
  final VoidCallback onTap;

  const HomeActionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.illustration,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.gradient,
  });

  static const double _radius = 21;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      scale: 0.96,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          height: 120,
          decoration: BoxDecoration(
            color: gradient == null ? background : null,
            gradient: gradient,
            borderRadius: BorderRadius.circular(_radius),
          ),
          child: InkWell(
            onTap: () {
              Feel.tap();
              onTap();
            },
            borderRadius: BorderRadius.circular(_radius),
            child: Stack(
              children: [
                Positioned(
                  right: 6,
                  bottom: 4,
                  child: SvgPicture.asset(illustration, width: 72, height: 72),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w900,
                              height: 1.2,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: foreground.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
