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
import 'features/recording/presentation/bloc/recording_bloc.dart';
import 'features/recording/presentation/widgets/recording_mini_bar.dart';
import 'features/subjects/data/subject_dao.dart';
import 'features/timetable/data/timetable_dao.dart';
import 'features/timetable/services/class_reminder_service.dart';

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

  // Notification taps: a recording ID opens that recording; a class
  // reminder starts recording in that class; the end nudge opens the
  // recorder.
  final notifications = sl<NotificationService>();
  void handleTap(String payload) => _handleNotificationTap(router, payload);
  notifications.onTapped = handleTap;

  runApp(MyLectoApp(router: router));

  unawaited(_recoverInterruptedRecordings());
  // Reminders are rebuilt at every launch, so they track the timetable
  // and the time zone even if something cleared them.
  unawaited(sl<ClassReminderService>().reschedule());

  final launchPayload = await notifications.launchPayload();
  if (launchPayload != null) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => handleTap(launchPayload),
    );
  }
}

void _handleNotificationTap(GoRouter router, String payload) {
  if (payload == ClassReminderService.recorderPayload) {
    router.push(AppRoutes.record);
  } else if (payload.startsWith(ClassReminderService.classPayloadPrefix)) {
    unawaited(
      _startClass(
        router,
        payload.substring(ClassReminderService.classPayloadPrefix.length),
      ),
    );
  } else {
    router.push('/recording/$payload');
  }
}

/// Tapping a class reminder means "I am in class": record it, in its subject.
///
/// Already recording, or the class has since been deleted, and it just
/// opens the recorder.
Future<void> _startClass(GoRouter router, String slotId) async {
  final slot = await sl<TimetableDao>().get(slotId);
  final context = AppRouter.navigatorKey.currentContext;
  final busy =
      context != null &&
      context.mounted &&
      context.read<RecordingBloc>().isActive;

  if (slot == null || busy) {
    router.push(AppRoutes.record);
  } else {
    router.push('${AppRoutes.record}?subjectId=${slot.subjectId}&start=1');
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
        body:
            'The app closed while recording. '
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
        RepositoryProvider<RecordingDao>.value(value: sl<RecordingDao>()),
        RepositoryProvider<SubjectDao>.value(value: sl<SubjectDao>()),
        RepositoryProvider<RecordingFeed>.value(value: sl<RecordingFeed>()),
        RepositoryProvider<TimetableDao>.value(value: sl<TimetableDao>()),
        RepositoryProvider<ClassReminderService>.value(
          value: sl<ClassReminderService>(),
        ),
      ],
      // One recorder for the whole app, so a recording keeps going while you
      // move around instead of being tied to the recording screen.
      child: BlocProvider<RecordingBloc>(
        create: (context) => RecordingBloc(
          recorderService: context.read(),
          storageMonitor: context.read(),
          photoService: context.read(),
          permissionService: context.read(),
          recordingDao: context.read(),
        ),
        child: MaterialApp.router(
          title: 'My Lecto',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.light,
          routerConfig: router,
          builder: (context, child) => Stack(
            children: [
              if (child != null) Positioned.fill(child: child),
              RecordingMiniBar(router: router),
            ],
          ),
        ),
      ),
    );
  }
}
