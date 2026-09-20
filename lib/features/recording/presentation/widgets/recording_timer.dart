import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// Large monospace timer display for the recording screen.
///
/// Shows HH:MM:SS format with a chunk progress indicator.
class RecordingTimer extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final hours = totalDuration.inHours.toString().padLeft(2, '0');
    final minutes =
        (totalDuration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds =
        (totalDuration.inSeconds % 60).toString().padLeft(2, '0');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Timer
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 300),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 52,
            fontWeight: FontWeight.w300,
            letterSpacing: 4,
            color: isPaused
                ? AppColors.textSecondaryDark
                : AppColors.textPrimaryDark,
          ),
          child: Text('$hours:$minutes:$seconds'),
        ),

        const SizedBox(height: AppSpacing.sm),

        // Chunk indicator
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isPaused
                    ? AppColors.warning
                    : AppColors.recordingRed,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              isPaused
                  ? 'PAUSED'
                  : 'Chunk ${chunkIndex + 1} • $completedChunks saved',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.2,
                color: isPaused
                    ? AppColors.warning
                    : AppColors.textSecondaryDark,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
