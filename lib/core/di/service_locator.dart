import 'package:get_it/get_it.dart';

import '../../features/recording/data/local/recording_dao.dart';
import '../../features/recording/data/local/recording_feed.dart';
import '../../features/recording/data/services/audio_recorder_service.dart';
import '../../features/recording/data/services/photo_capture_service.dart';
import '../../features/recording/data/services/recording_recovery_service.dart';
import '../../features/recording/data/services/storage_monitor_service.dart';
import '../../features/subjects/data/subject_dao.dart';
import '../../features/timetable/data/timetable_dao.dart';
import '../../features/timetable/services/class_reminder_service.dart';
import '../permissions/permission_service.dart';
import '../services/notification_service.dart';

final sl = GetIt.instance;

/// Wire up the app's services.
///
/// Everything here is on-device: there is no API client, upload queue,
/// connectivity monitor or auth, because the app talks to nothing.
Future<void> initServiceLocator() async {
  sl.registerLazySingleton<PermissionService>(() => PermissionService());

  final notifications = NotificationService();
  await notifications.initialize();
  sl.registerSingleton<NotificationService>(notifications);

  // === Recording ===
  sl.registerLazySingleton<StorageMonitorService>(
    () => StorageMonitorService(),
  );

  sl.registerLazySingleton<AudioRecorderService>(
    () => AudioRecorderService(storageMonitor: sl<StorageMonitorService>()),
  );

  sl.registerLazySingleton<PhotoCaptureService>(() => PhotoCaptureService());

  // === Data ===
  sl.registerLazySingleton<RecordingDao>(() => RecordingDao());
  sl.registerLazySingleton<SubjectDao>(() => SubjectDao());
  sl.registerLazySingleton<RecordingFeed>(() => RecordingFeed());

  sl.registerLazySingleton<RecordingRecoveryService>(
    () => RecordingRecoveryService(dao: sl<RecordingDao>()),
  );

  // === Timetable ===
  sl.registerLazySingleton<TimetableDao>(() => TimetableDao());
  sl.registerLazySingleton<ClassReminderService>(
    () => ClassReminderService(
      notifications: sl<NotificationService>(),
      timetable: sl<TimetableDao>(),
    ),
  );
}
