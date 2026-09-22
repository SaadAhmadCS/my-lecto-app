import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// The live sound of the room, scrolling right to left.
///
/// Painted rather than built: fifty animated widgets rebuilt ten times a
/// second made the whole screen stutter, and this is the one thing a student
/// watches to know the phone is still listening.
class WaveformVisualizer extends StatefulWidget {
  /// 0 to 1, from the recorder.
  final double amplitude;
  final bool isActive;
  final double height;

  const WaveformVisualizer({
    super.key,
    required this.amplitude,
    this.isActive = true,
    this.height = 120,
  });

  @override
  State<WaveformVisualizer> createState() => _WaveformVisualizerState();
}

class _WaveformVisualizerState extends State<WaveformVisualizer>
    with SingleTickerProviderStateMixin {
  static const _bars = 56;

  /// Newest last. Every tick shifts one to the left.
  final List<double> _levels = List.filled(_bars, 0.04);
  final _random = Random();
  late final AnimationController _ticker = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  /// Follows the amplitude with a little lag, so the bars breathe instead of
  /// flickering between readings.
  double _smoothed = 0.04;
  int _lastShiftMs = 0;

  @override
  void initState() {
    super.initState();
    _ticker.addListener(_tick);
  }

  void _tick() {
    final ms = (_ticker.lastElapsedDuration ?? Duration.zero).inMilliseconds;
    // A new bar every ~90ms, whatever the frame rate.
    if ((ms - _lastShiftMs).abs() < 90) return;
    _lastShiftMs = ms;

    final target = widget.isActive ? widget.amplitude.clamp(0.04, 1.0) : 0.0;
    _smoothed = _smoothed + (target - _smoothed) * 0.45;

    // A touch of variation: a perfectly even bar chart reads as fake.
    final jitter = widget.isActive ? (_random.nextDouble() - 0.5) * 0.14 : 0.0;
    final level = (_smoothed + jitter).clamp(0.04, 1.0);

    for (var i = 0; i < _levels.length - 1; i++) {
      _levels[i] = _levels[i + 1];
    }
    _levels[_levels.length - 1] = level;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _WavePainter(
            levels: _levels,
            repaint: _ticker,
            active: widget.isActive,
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final List<double> levels;
  final bool active;

  _WavePainter({
    required this.levels,
    required this.active,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.height / 2;
    final slot = size.width / levels.length;
    final width = slot * 0.55;
    final paint = Paint()..strokeCap = StrokeCap.round;

    for (var i = 0; i < levels.length; i++) {
      final level = levels[i];
      final half = max(2.0, level * (size.height / 2 - 4));
      final x = slot * i + slot / 2;

      // The newest bars are the brightest, so the sound reads as arriving.
      final age = i / levels.length;
      paint.shader = active
          ? LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.primaryLight.withValues(alpha: 0.35 + age * 0.65),
                AppColors.primary.withValues(alpha: 0.35 + age * 0.65),
              ],
            ).createShader(Rect.fromLTWH(x, middle - half, width, half * 2))
          : null;
      if (!active) paint.color = AppColors.waveformInactive;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - width / 2, middle - half, width, half * 2),
          Radius.circular(width),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.active != active;
}
