import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/ui/motion.dart';
import '../bloc/recording_bloc.dart';
import '../bloc/recording_state.dart';

/// A floating "Recording 12:34" pill shown on every screen but the recorder.
///
/// Recording keeps going when you leave its screen, so this is how you know
/// it is still running and how you get back to it. It sits in the app-wide
/// overlay, above where the nav dock sits.
class RecordingMiniBar extends StatelessWidget {
  final GoRouter router;

  const RecordingMiniBar({super.key, required this.router});

  /// How many recording screens are open. The pill hides while any is, since
  /// the recorder is already on screen. Counted by the screen itself because
  /// the router's reported location does not follow pushed routes.
  static final ValueNotifier<int> recorderScreensOpen = ValueNotifier(0);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: recorderScreensOpen,
      builder: (context, open, _) {
        if (open > 0) return const SizedBox.shrink();

        return BlocBuilder<RecordingBloc, RecordingBlocState>(
          // Rebuild once a second and on start/pause/stop, not on every
          // amplitude sample.
          buildWhen: (previous, current) =>
              previous.runtimeType != current.runtimeType ||
              _seconds(previous) != _seconds(current),
          builder: (context, state) {
            final (duration, paused) = switch (state) {
              RecordingInProgress(:final totalDuration) => (
                totalDuration,
                false,
              ),
              RecordingPaused(:final totalDuration) => (totalDuration, true),
              _ => (null, false),
            };
            if (duration == null) return const SizedBox.shrink();

            final bottomInset = MediaQuery.of(context).padding.bottom;

            return Positioned(
              left: 0,
              right: 0,
              // Clear of the nav dock (20 margin + 60 tall + a gap), and of
              // the audio player on screens without the dock.
              bottom: bottomInset + 96,
              child: Center(
                // Rises into view when a recording starts.
                child: Appear(
                  offset: 14,
                  child: _Pill(
                    duration: duration,
                    paused: paused,
                    onTap: () => router.push(AppRoutes.record),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static int? _seconds(RecordingBlocState state) => switch (state) {
    RecordingInProgress(:final totalDuration) => totalDuration.inSeconds,
    RecordingPaused(:final totalDuration) => totalDuration.inSeconds,
    _ => null,
  };
}

class _Pill extends StatelessWidget {
  final Duration duration;
  final bool paused;
  final VoidCallback onTap;

  const _Pill({
    required this.duration,
    required this.paused,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: paused
          ? 'Recording paused. Open the recorder.'
          : 'Recording in progress. Open the recorder.',
      // Shadow on an outer box: drawn by Ink it is clipped to a pale square.
      child: Pressable(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(100),
            boxShadow: [
              BoxShadow(
                color: AppColors.textPrimary.withValues(alpha: 0.22),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            color: paused ? AppColors.navBar : AppColors.primary,
            borderRadius: BorderRadius.circular(100),
            child: InkWell(
              onTap: () {
                Feel.tap();
                onTap();
              },
              borderRadius: BorderRadius.circular(100),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    paused
                        ? const Icon(
                            Icons.pause_rounded,
                            size: 16,
                            color: AppColors.textOnPrimary,
                          )
                        : const _PulsingDot(),
                    const SizedBox(width: 8),
                    Text(
                      '${paused ? 'Paused' : 'Recording'}  ${_format(duration)}',
                      style: const TextStyle(
                        color: AppColors.textOnPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.textOnPrimary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _format(Duration d) {
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return d.inHours > 0
        ? '${d.inHours}:$minutes:$seconds'
        : '$minutes:$seconds';
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(_controller),
      child: Container(
        width: 9,
        height: 9,
        decoration: const BoxDecoration(
          color: AppColors.textOnPrimary,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
