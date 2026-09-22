import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/ui/motion.dart';

/// How long this lecture has been running, and when it was last saved.
///
/// The count is the thing a student glances at from across the desk, so it is
/// large and evenly spaced. Under it, a line fills towards the next automatic
/// save — the answer to "is this actually recording?".
class RecordingTimer extends StatefulWidget {
  final Duration totalDuration;
  final int chunkIndex;
  final int completedChunks;
  final bool isPaused;

  const RecordingTimer({
    super.key,
    required this.totalDuration,
    required this.chunkIndex,
    required this.completedChunks,
    this.isPaused = false,
  });

  @override
  State<RecordingTimer> createState() => _RecordingTimerState();
}

class _RecordingTimerState extends State<RecordingTimer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.totalDuration;
    final hours = total.inHours.toString().padLeft(2, '0');
    final minutes = (total.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (total.inSeconds % 60).toString().padLeft(2, '0');

    final chunkMinutes = AppConstants.defaultChunkDurationMinutes;
    final intoChunk = total.inSeconds % (chunkMinutes * 60);
    final toSave = chunkMinutes * 60 - intoChunk;
    final saved = widget.completedChunks;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The live state, above the number it belongs to.
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeTransition(
              opacity: widget.isPaused
                  ? const AlwaysStoppedAnimation(1.0)
                  : Tween<double>(begin: 0.35, end: 1).animate(_pulse),
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.isPaused
                      ? AppColors.warning
                      : AppColors.recordingRed,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              widget.isPaused ? 'PAUSED' : 'RECORDING',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.6,
                color: widget.isPaused
                    ? AppColors.warning
                    : AppColors.recordingRed,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AnimatedDefaultTextStyle(
          duration: Motion.base,
          style: TextStyle(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontSize: 56,
            height: 1,
            fontWeight: FontWeight.w300,
            letterSpacing: 2,
            color: widget.isPaused
                ? AppColors.textSecondaryDark
                : AppColors.textPrimaryDark,
          ),
          child: Text('$hours:$minutes:$seconds'),
        ),
        const SizedBox(height: AppSpacing.base),
        // Nothing is lost if the phone dies: the part being recorded is
        // written to disk every few minutes.
        SizedBox(
          width: 220,
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: LinearProgressIndicator(
                  value: widget.isPaused ? 0 : intoChunk / (chunkMinutes * 60),
                  minHeight: 3,
                  backgroundColor: AppColors.darkSurfaceLight,
                  valueColor: AlwaysStoppedAnimation(
                    widget.isPaused
                        ? AppColors.warning
                        : AppColors.primary.withValues(alpha: 0.8),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                widget.isPaused
                    ? '$saved part${saved == 1 ? '' : 's'} saved so far'
                    : saved == 0
                    ? 'Saves in ${_mins(toSave)}'
                    : '$saved part${saved == 1 ? '' : 's'} saved · '
                          'next in ${_mins(toSave)}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textTertiaryDark,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// "4 min", or "40s" in the last minute, so it never reads "0 min".
  static String _mins(int seconds) =>
      seconds >= 60 ? '${(seconds / 60).ceil()} min' : '${seconds}s';
}
