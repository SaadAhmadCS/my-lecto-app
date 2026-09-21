import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'core/di/service_locator.dart';
import 'core/errors/app_error_handler.dart';
import 'core/permissions/permission_service.dart';
import 'core/routes/app_router.dart';
import 'core/services/foreground_recording_service.dart';
import 'core/services/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'features/recording/data/local/recording_dao.dart';
import 'features/recording/data/local/recording_feed.dart';
import 'features/recording/data/services/audio_recorder_service.dart';
import 'features/recording/data/services/photo_capture_service.dart';
import 'features/recording/data/services/recording_recovery_service.dart';
import 'features/recording/data/services/storage_monitor_service.dart';
import 'features/subjects/data/subject_dao.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppErrorHandler.install();

  ForegroundRecordingService.init();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await initServiceLocator();

  // No account and no onboarding: there is nothing to sign in to, so the app
  // opens on Home.
  final router = AppRouter.router();

  // Tapping a "recording saved" notification opens that recording.
  final notifications = sl<NotificationService>();
  void openRecording(String id) => router.push('/recording/$id');
  notifications.onRecordingTapped = openRecording;

  runApp(MyLectoApp(router: router));

  unawaited(_recoverInterruptedRecordings());

  final launchRecordingId = await notifications.launchRecordingId();
  if (launchRecordingId != null) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => openRecording(launchRecordingId),
    );
  }
}

/// Finish recordings cut off by an app kill or crash, and tell the user.
Future<void> _recoverInterruptedRecordings() async {
  try {
    final recovered = await sl<RecordingRecoveryService>().recoverInterrupted();
    if (recovered.isEmpty) return;

    final notifications = sl<NotificationService>();
    await notifications.requestPermissionIfNeeded();
    for (final recording in recovered) {
      final minutes = recording.duration.inMinutes;
      await notifications.showRecordingUpdate(
        recordingId: recording.recordingId,
        title: 'Recording saved: ${recording.title}',
        body: 'The app closed while recording. '
            '${minutes < 1 ? 'Less than a minute' : '$minutes min'} of audio '
            'was saved'
            '${recording.lostEnd ? '; the last part before it closed could not be saved.' : '.'}',
      );
    }
  } catch (e, stack) {
    AppErrorHandler.report(e, stack, context: 'recording recovery');
  }
}

/// Root application widget.
class MyLectoApp extends StatelessWidget {
  final GoRouter router;

  const MyLectoApp({super.key, required this.router});

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<PermissionService>.value(
          value: sl<PermissionService>(),
        ),
        RepositoryProvider<StorageMonitorService>.value(
          value: sl<StorageMonitorService>(),
        ),
        RepositoryProvider<AudioRecorderService>.value(
          value: sl<AudioRecorderService>(),
        ),
        RepositoryProvider<PhotoCaptureService>.value(
          value: sl<PhotoCaptureService>(),
        ),
        RepositoryProvider<RecordingDao>.value(
          value: sl<RecordingDao>(),
        ),
        RepositoryProvider<SubjectDao>.value(
          value: sl<SubjectDao>(),
        ),
        RepositoryProvider<RecordingFeed>.value(
          value: sl<RecordingFeed>(),
        ),
      ],
      child: MaterialApp.router(
        title: 'My Lecto',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.light,
        routerConfig: router,
      ),
    );
  }
}
