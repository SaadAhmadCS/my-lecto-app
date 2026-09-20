import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// Main recording control buttons — record/pause, camera, stop.
///
/// The center button animates between record (mic icon) and pause states
/// with a pulsing red glow effect during active recording.
class RecordingControls extends StatefulWidget {
  final bool isRecording;
  final bool isPaused;
  final VoidCallback onRecordPause;
  final VoidCallback onStop;
  final VoidCallback onCapturePhoto;

  const RecordingControls({
    super.key,
    required this.isRecording,
    required this.isPaused,
    required this.onRecordPause,
    required this.onStop,
    required this.onCapturePhoto,
  });

  @override
  State<RecordingControls> createState() => _RecordingControlsState();
}

class _RecordingControlsState extends State<RecordingControls>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void didUpdateWidget(RecordingControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !widget.isPaused) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Camera button (left)
        _buildSecondaryButton(
          icon: Icons.camera_alt_rounded,
          label: 'Photo',
          onTap: widget.isRecording ? widget.onCapturePhoto : null,
        ),

        // Record / Pause button (center)
        _buildMainButton(),

        // Stop button (right)
        _buildSecondaryButton(
          icon: Icons.stop_rounded,
          label: 'Stop',
          onTap: widget.isRecording ? widget.onStop : null,
          color: AppColors.textSecondaryDark,
        ),
      ],
    );
  }

  Widget _buildMainButton() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        final scale = widget.isRecording && !widget.isPaused
            ? _pulseAnimation.value
            : 1.0;

        return Transform.scale(
          scale: scale,
          child: GestureDetector(
            onTap: widget.onRecordPause,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isPaused
                    ? AppColors.primary
                    : AppColors.recordingRed,
                boxShadow: widget.isRecording && !widget.isPaused
                    ? [
                        BoxShadow(
                          color: AppColors.recordingRed.withValues(alpha: 0.4),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ]
                    : [],
              ),
              child: Icon(
                widget.isPaused
                    ? Icons.mic_rounded
                    : (widget.isRecording
                        ? Icons.pause_rounded
                        : Icons.mic_rounded),
                color: Colors.white,
                size: 36,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSecondaryButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    Color? color,
  }) {
    final isDisabled = onTap == null;
    final buttonColor = isDisabled
        ? AppColors.textTertiaryDark
        : (color ?? AppColors.textPrimaryDark);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.darkSurface.withValues(alpha: 0.8),
              border: Border.all(
                color: buttonColor.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Icon(icon, color: buttonColor, size: 24),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: buttonColor,
            ),
          ),
        ],
      ),
    );
  }
}
