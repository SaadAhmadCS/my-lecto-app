import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// One set of timings and curves for the whole app.
///
/// Screens that animate at their own speeds feel like separate apps stitched
/// together, so everything here is picked once: quick for a tap, calm for
/// content arriving.
class Motion {
  const Motion._();

  /// A press, a tick, a colour change.
  static const Duration fast = Duration(milliseconds: 160);

  /// The everyday one: a card arriving, a sheet settling.
  static const Duration base = Duration(milliseconds: 280);

  /// A whole screen's worth of content.
  static const Duration slow = Duration(milliseconds: 460);

  /// Decelerating: fast to start, gentle to land.
  static const Curve enter = Curves.easeOutCubic;

  /// A little overshoot, for something that should feel springy.
  static const Curve pop = Curves.easeOutBack;

  /// How long each item waits behind the one before it in a list.
  static const Duration stagger = Duration(milliseconds: 55);
}

/// The app's haptics, named after what they mean rather than how strong they
/// are, so the same action always feels the same wherever it is.
class Feel {
  const Feel._();

  /// Moving between things: a tab, a chip, a filter.
  static void select() => HapticFeedback.selectionClick();

  /// Opening something, or a plain button press.
  static void tap() => HapticFeedback.lightImpact();

  /// Ticking a task off, saving notes, finishing something.
  static void done() => HapticFeedback.mediumImpact();

  /// Starting or stopping a recording — the moments worth feeling.
  static void heavy() => HapticFeedback.heavyImpact();

  /// Something refused: an empty paste, a save that failed.
  static void refuse() => HapticFeedback.vibrate();
}

/// A tap target that presses in, the way a physical button would.
///
/// Wraps anything: a card, a tile, a chip. The scale is small on purpose —
/// enough to feel, not enough to notice.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// How far it sinks. Bigger cards can take a little more.
  final double scale;

  /// Haptic on tap. Off for rows that already trigger their own.
  final bool haptic;
  final BorderRadius? borderRadius;
  final String? semanticLabel;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.haptic = true,
    this.borderRadius,
    this.semanticLabel,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;

    // Nothing to handle: react to the press and let the child own the tap,
    // so a card with its own ripple still sinks when touched.
    if (!enabled) {
      return Listener(
        onPointerDown: (_) => setState(() => _down = true),
        onPointerUp: (_) => setState(() => _down = false),
        onPointerCancel: (_) => setState(() => _down = false),
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: Motion.fast,
          curve: Motion.enter,
          child: widget.child,
        ),
      );
    }

    return Semantics(
      label: widget.semanticLabel,
      button: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap == null
            ? null
            : () {
                if (widget.haptic) Feel.tap();
                widget.onTap!();
              },
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                Feel.select();
                widget.onLongPress!();
              },
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: Motion.fast,
          curve: Motion.enter,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Content that rises into place instead of appearing all at once.
///
/// [index] staggers a list: each row starts a little after the one above it,
/// which reads as the screen filling in rather than flashing.
class Appear extends StatefulWidget {
  final Widget child;
  final int index;

  /// How far it travels up, in logical pixels.
  final double offset;
  final Duration duration;

  const Appear({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = 18,
    this.duration = Motion.slow,
  });

  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    final wait = Motion.stagger * widget.index;
    if (wait == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(wait, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: Motion.enter);
    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, widget.offset * (1 - curved.value)),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

/// A number that counts up to its value, and re-counts when it changes.
///
/// Used for the figures a student watches grow: hours recorded, lectures,
/// tasks left.
class CountUp extends StatelessWidget {
  final num value;
  final TextStyle? style;

  /// Wraps the number in its final form — "4h 20m", "6 courses".
  final String Function(num value)? format;
  final Duration duration;

  const CountUp({
    super.key,
    required this.value,
    this.style,
    this.format,
    this.duration = Motion.slow,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Motion.enter,
      builder: (context, animated, _) => Text(
        format?.call(animated) ?? animated.round().toString(),
        style: style,
      ),
    );
  }
}

/// The soft grey block that stands in for content while it loads.
///
/// Better than a spinner: the screen keeps its shape, so nothing jumps when
/// the real thing arrives.
class Skeleton extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const Skeleton({super.key, this.width, this.height = 16, this.radius = 10});

  /// A card-shaped block.
  const Skeleton.card({super.key, this.height = 120, this.radius = 22})
    : width = double.infinity;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.55,
        end: 1,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}
