import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/motion.dart';

/// "Nothing here yet", said kindly and in the app's own drawing style.
///
/// An empty screen is where a student decides whether the app is working, so
/// each one shows the illustration its feature uses elsewhere, says what will
/// appear, and where useful offers the action that fills it.
class EmptyState extends StatelessWidget {
  /// An SVG from assets/images — the same one its home card uses.
  final String illustration;
  final String title;
  final String body;

  /// The tint behind the drawing; defaults to the warm cream.
  final Color tint;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Boxed in a card, for a screen that is otherwise a list.
  final bool bordered;

  const EmptyState({
    super.key,
    required this.illustration,
    required this.title,
    required this.body,
    this.tint = AppColors.tintCream,
    this.actionLabel,
    this.onAction,
    this.bordered = true,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        // The drawing drifts, so the screen is not completely still.
        _Float(
          child: Container(
            width: 116,
            height: 116,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            child: SvgPicture.asset(illustration),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 17.5,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 16),
          Pressable(
            onTap: onAction,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                actionLabel!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textOnPrimary,
                ),
              ),
            ),
          ),
        ],
      ],
    );

    return Appear(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(28, 30, 28, 30),
        decoration: bordered
            ? BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border),
              )
            : null,
        child: content,
      ),
    );
  }
}

/// A slow rise and fall, a few pixels: enough to look alive, not enough to
/// distract while reading the line underneath.
class _Float extends StatefulWidget {
  final Widget child;

  const _Float({required this.child});

  @override
  State<_Float> createState() => _FloatState();
}

class _FloatState extends State<_Float> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, -5 * curved.value),
        child: child,
      ),
      child: widget.child,
    );
  }
}
