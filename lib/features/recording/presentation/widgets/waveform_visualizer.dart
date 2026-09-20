import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Real-time audio waveform visualizer.
///
/// Displays 50 vertical bars that animate based on audio amplitude.
/// Uses smooth interpolation for fluid visual feedback.
class WaveformVisualizer extends StatefulWidget {
  final double amplitude; // 0.0 to 1.0
  final bool isActive;

  const WaveformVisualizer({
    super.key,
    required this.amplitude,
    this.isActive = true,
  });

  @override
  State<WaveformVisualizer> createState() => _WaveformVisualizerState();
}

class _WaveformVisualizerState extends State<WaveformVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _barHeights = List.generate(50, (_) => 0.05);
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..addListener(_updateBars);
    _controller.repeat();
  }

  void _updateBars() {
    if (!mounted) return;
    setState(() {
      // Shift bars left and add new one on the right
      for (int i = 0; i < _barHeights.length - 1; i++) {
        _barHeights[i] = _barHeights[i + 1];
      }

      if (widget.isActive) {
        // Add organic variation to the amplitude
        final variation = (_random.nextDouble() - 0.5) * 0.3;
        final newHeight = (widget.amplitude + variation).clamp(0.05, 1.0);
        _barHeights[_barHeights.length - 1] = newHeight;
      } else {
        // Slowly decay to flat line when inactive
        _barHeights[_barHeights.length - 1] =
            _barHeights[_barHeights.length - 1] * 0.8;
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(_barHeights.length, (index) {
          final height = _barHeights[index];
          final isCenter = (index - _barHeights.length ~/ 2).abs() < 10;

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 80),
                  curve: Curves.easeOut,
                  height: max(4, height * 90),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: widget.isActive
                        ? LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              AppColors.primary.withValues(
                                alpha: isCenter ? 1.0 : 0.6,
                              ),
                              AppColors.accent.withValues(
                                alpha: height,
                              ),
                            ],
                          )
                        : null,
                    color: widget.isActive
                        ? null
                        : AppColors.waveformInactive,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
