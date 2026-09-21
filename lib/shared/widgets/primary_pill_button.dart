import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// The big coral call-to-action: gradient pill, soft glow, white label.
///
/// Matches the Record tile on Home, so every "do the main thing" button in
/// the app reads the same.
class PrimaryPillButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;

  const PrimaryPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 56,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    // The glow lives on an outer box: drawn by Ink it gets clipped to the
    // ink layer and shows as a pale rectangle.
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: enabled ? 1 : 0.5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          boxShadow: [
            if (enabled)
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.30),
                blurRadius: 24,
                spreadRadius: -6,
                offset: const Offset(0, 10),
              ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: Ink(
            height: height,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF57049), Color(0xFFEC5A32)],
              ),
              borderRadius: BorderRadius.circular(100),
            ),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(100),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: AppColors.textOnPrimary, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textOnPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
