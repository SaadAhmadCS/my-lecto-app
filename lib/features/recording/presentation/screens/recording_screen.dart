import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../subjects/data/subject_dao.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../bloc/recording_bloc.dart';
import '../bloc/recording_event.dart';
import '../bloc/recording_state.dart';
import '../widgets/photo_strip.dart';
import '../widgets/recording_controls.dart';
import '../widgets/recording_timer.dart';
import '../widgets/storage_status_bar.dart';
import '../widgets/waveform_visualizer.dart';

/// Recording screen — the heart of Lecto.
///
/// Full-screen recording interface with:
/// - Live waveform visualization
/// - Timer with chunk progress
/// - Record/pause/stop controls
/// - Camera capture for board photos
/// - Storage & connectivity status
class RecordingScreen extends StatelessWidget {
  /// When set (e.g. opened from a subject), recording starts in this
  /// subject without showing the subject picker.
  final String? initialSubjectId;

  const RecordingScreen({super.key, this.initialSubjectId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => RecordingBloc(
        recorderService: context.read(),
        storageMonitor: context.read(),
        photoService: context.read(),
        permissionService: context.read(),
        recordingDao: context.read(),
      ),
      child: _RecordingScreenBody(initialSubjectId: initialSubjectId),
    );
  }
}

class _RecordingScreenBody extends StatelessWidget {
  final String? initialSubjectId;

  const _RecordingScreenBody({this.initialSubjectId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BlocBuilder<RecordingBloc, RecordingBlocState>(
          builder: (context, state) {
            return IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () {
                if (state is RecordingInProgress || state is RecordingPaused) {
                  _showExitConfirmation(context);
                } else {
                  Navigator.of(context).pop();
                }
              },
            );
          },
        ),
        title: const Text(
          'Record Lecture',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: BlocConsumer<RecordingBloc, RecordingBlocState>(
        listener: (context, state) {
          if (state is RecordingCompleted) {
            _showCompletionDialog(context, state);
          }
          if (state is RecordingError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: AppColors.error,
                action: state.canRetry
                    ? SnackBarAction(
                        label: 'Settings',
                        textColor: Colors.white,
                        onPressed: () {
                          openAppSettings();
                        },
                      )
                    : null,
              ),
            );
          }
        },
        builder: (context, state) {
          return switch (state) {
            RecordingIdle() => _buildIdleView(context),
            RecordingRequestingPermissions() => _buildPermissionsView(),
            RecordingInProgress() => _buildRecordingView(context, state),
            RecordingPaused() => _buildPausedView(context, state),
            RecordingCompleted() => _buildCompletedView(context, state),
            RecordingError() => _buildErrorView(context, state),
          };
        },
      ),
    );
  }

  /// Idle state — ready to start recording.
  Widget _buildIdleView(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 2),

          // Waveform (inactive)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: WaveformVisualizer(amplitude: 0.0, isActive: false),
          ),

          const SizedBox(height: AppSpacing.xxl),

          // Timer placeholder
          const RecordingTimer(
            totalDuration: Duration.zero,
            chunkIndex: 0,
            completedChunks: 0,
          ),

          const Spacer(),

          // Hint text
          Text(
            'Tap the mic button to start recording',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondaryDark.withValues(alpha: 0.7),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // Controls
          RecordingControls(
            isRecording: false,
            isPaused: false,
            onRecordPause: () => _beginRecording(context),
            onStop: () {},
            onCapturePhoto: () {},
          ),

          const Spacer(flex: 1),
        ],
      ),
    );
  }

  /// Permissions request view.
  Widget _buildPermissionsView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: AppSpacing.lg),
          Text(
            'Requesting permissions...',
            style: TextStyle(color: AppColors.textSecondaryDark),
          ),
        ],
      ),
    );
  }

  /// Active recording view — the main experience.
  Widget _buildRecordingView(BuildContext context, RecordingInProgress state) {
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.lg),

          // Status bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: StorageStatusBar(
              availableMB: state.availableStorageMB,
              isStorageLow: state.isStorageLow,
              isOnline: state.isOnline,
              completedChunks: state.completedChunks,
            ),
          ),

          const Spacer(flex: 2),

          // Waveform
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: WaveformVisualizer(
              amplitude: state.amplitude,
              isActive: true,
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),

          // Timer
          RecordingTimer(
            totalDuration: state.totalDuration,
            chunkIndex: state.chunkIndex,
            completedChunks: state.completedChunks,
          ),

          const Spacer(),

          // Photo strip
          PhotoStrip(photos: state.photos),

          if (state.photos.isNotEmpty) const SizedBox(height: AppSpacing.lg),

          // Controls
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: RecordingControls(
              isRecording: true,
              isPaused: false,
              onRecordPause: () {
                context
                    .read<RecordingBloc>()
                    .add(const PauseRecordingEvent());
              },
              onStop: () => _showStopConfirmation(context),
              onCapturePhoto: () => _capturePhoto(context),
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),

          // Approaching the 8-hour session limit (REC-016)
          if (state.isNearMaxDuration)
            Container(
              margin: const EdgeInsets.fromLTRB(
                AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm,
              ),
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.warningBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer_off_outlined,
                      color: AppColors.warning, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Recording stops automatically at 8 hours '
                      '(${(AppConstants.maxRecordingDuration - state.totalDuration).inMinutes.clamp(0, 15)} min left)',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.warning.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Low storage warning
          if (state.isStorageLow)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.warningBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppColors.warning, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Low storage — chunks shortened to save space',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.warning.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  /// Paused recording view.
  Widget _buildPausedView(BuildContext context, RecordingPaused state) {
    return SafeArea(
      child: Column(
        children: [
          const Spacer(flex: 2),

          // Waveform (inactive/paused)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: WaveformVisualizer(amplitude: 0.0, isActive: false),
          ),

          const SizedBox(height: AppSpacing.xxl),

          // Timer (paused)
          RecordingTimer(
            totalDuration: state.totalDuration,
            chunkIndex: 0,
            completedChunks: state.completedChunks,
            isPaused: true,
          ),

          const Spacer(),

          // Photo strip
          PhotoStrip(photos: state.photos),

          if (state.photos.isNotEmpty) const SizedBox(height: AppSpacing.lg),

          // Controls
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: RecordingControls(
              isRecording: true,
              isPaused: true,
              onRecordPause: () {
                context
                    .read<RecordingBloc>()
                    .add(const ResumeRecordingEvent());
              },
              onStop: () => _showStopConfirmation(context),
              onCapturePhoto: () => _capturePhoto(context),
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  /// Completed recording view.
  Widget _buildCompletedView(BuildContext context, RecordingCompleted state) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: AppColors.success,
              size: 72,
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Recording Saved!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimaryDark,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '${state.totalChunks} chunks • '
              '${state.totalDuration.inMinutes} min • '
              '${state.totalPhotos} photos',
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondaryDark,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              [
                if (state.stoppedAtMaxDuration)
                  'Stopped automatically at the 8-hour limit.',
                'Share it to your AI app to get notes',
              ].join('\n'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.accent,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                // push, not go: go replaces the stack, which left the detail
                // screen with nothing to pop back to.
                context.push(
                  '/recording/${state.recordingId}?title=Recording',
                );
              },
              // Nothing is being generated in the background, so the next step
              // is the share.
              icon: const Icon(Icons.ios_share_rounded),
              label: const Text('Share to your AI'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.md,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Back to Home'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondaryDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Error state view.
  Widget _buildErrorView(BuildContext context, RecordingError state) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.error,
              size: 64,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              state.message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.textPrimaryDark,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (state.canRetry)
              FilledButton(
                onPressed: () => _beginRecording(context),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                child: const Text('Try Again'),
              )
            else
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back to Home'),
              ),
          ],
        ),
      ),
    );
  }

  /// Start in the preselected subject, or ask which subject to use.
  void _beginRecording(BuildContext context) {
    final subjectId = initialSubjectId;
    if (subjectId != null) {
      _startRecordingWithSubject(context, subjectId);
    } else {
      _showSubjectPicker(context);
    }
  }

  /// Show subject picker bottom sheet before recording starts.
  void _showSubjectPicker(BuildContext outerContext) {
    final subjectDao = outerContext.read<SubjectDao>();

    showModalBottomSheet(
      context: outerContext,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: subjectDao.listSubjects(),
          builder: (ctx, snapshot) {
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.darkBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  Text(
                    'Record for which subject?',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.base),

                  // Quick Record option
                  ListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.bolt_rounded,
                          color: AppColors.primary, size: 20),
                    ),
                    title: const Text('Quick Record'),
                    subtitle: Text(
                      'Save to "Unsorted" — organize later',
                      style: TextStyle(
                        color: AppColors.textTertiaryDark,
                        fontSize: 12,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _startRecordingWithSubject(outerContext, 'unsorted');
                    },
                  ),

                  const Divider(color: AppColors.darkBorder),

                  // Subject list
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary),
                      ),
                    )
                  else if (snapshot.hasError)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Center(
                        child: Text(
                          'Could not load subjects.\nTap "Quick Record" above.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondaryDark),
                        ),
                      ),
                    )
                  else ...[
                    ..._buildSubjectList(ctx, outerContext, snapshot.data!),
                  ],

                  const SizedBox(height: AppSpacing.base),
                ],
              ),
            );
          },
        );
      },
    );
  }

  List<Widget> _buildSubjectList(
    BuildContext sheetContext,
    BuildContext outerContext,
    List<Map<String, dynamic>> subjects,
  ) {

    if (subjects.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
          child: Center(
            child: Text(
              'No subjects yet — use Quick Record or create one in Subjects tab.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 13),
            ),
          ),
        ),
      ];
    }

    return subjects.map((s) {
      final name = s['name'] as String? ?? 'Untitled';
      final id = s['id'] as String;
      final colorStr = s['color'] as String? ?? '#6366F1';

      Color cardColor;
      try {
        cardColor = Color(int.parse(colorStr.replaceFirst('#', '0xFF')));
      } catch (_) {
        cardColor = AppColors.primary;
      }

      return ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: cardColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.folder_rounded, color: cardColor, size: 20),
        ),
        title: Text(name),
        onTap: () {
          Navigator.of(sheetContext).pop();
          _startRecordingWithSubject(outerContext, id);
        },
      );
    }).toList();
  }

  void _startRecordingWithSubject(BuildContext context, String subjectId) {
    context.read<RecordingBloc>().add(
          StartRecordingEvent(subjectId: subjectId),
        );
  }

  /// Capture a photo using the camera.
  Future<void> _capturePhoto(BuildContext context) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70, // Compress to save storage
      maxWidth: 1920,
    );

    if (image != null && context.mounted) {
      context.read<RecordingBloc>().add(
            CapturePhotoEvent(photoFilePath: image.path),
          );
    }
  }

  /// Show stop confirmation dialog.
  void _showStopConfirmation(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiaryDark,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text(
                'Stop Recording?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryDark,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Your recording will be saved and can be transcribed later.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondaryDark,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.textTertiaryDark),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Continue'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        context.read<RecordingBloc>().add(
                              const StopRecordingEvent(),
                            );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.recordingRed,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Stop & Save'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        );
      },
    );
  }

  /// Show exit confirmation when recording is active.
  void _showExitConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.darkSurface,
          title: const Text('Recording in progress'),
          content: const Text(
            'Do you want to stop the recording and exit?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                context
                    .read<RecordingBloc>()
                    .add(const StopRecordingEvent());
              },
              style: TextButton.styleFrom(
                foregroundColor: AppColors.error,
              ),
              child: const Text('Stop & Exit'),
            ),
          ],
        );
      },
    );
  }

  /// Show completion summary dialog.
  void _showCompletionDialog(BuildContext context, RecordingCompleted state) {
    // Auto-handled by the completed view state
  }
}
