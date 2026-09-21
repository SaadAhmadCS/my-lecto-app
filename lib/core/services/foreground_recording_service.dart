import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class ForegroundRecordingService {
  static bool _isRunning = false;

  /// Initialize the foreground task configuration. Call once at app startup.
  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'lecto_recording',
        channelName: 'Lecto Recording',
        channelDescription: 'Recording in progress',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  /// Start the foreground service. Call when recording starts.
  static Future<void> startService() async {
    if (_isRunning) return;
    _isRunning = true;
    await FlutterForegroundTask.startService(
      notificationTitle: 'Lecto — Recording',
      notificationText: 'Recording in progress...',
    );
  }

  /// Update notification text with duration.
  static Future<void> updateDuration(Duration duration) async {
    if (!_isRunning) return;
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    await FlutterForegroundTask.updateService(
      notificationTitle: 'Lecto — Recording',
      notificationText: 'Duration: $hours:$minutes:$seconds',
    );
  }

  /// Stop the foreground service. Call when recording stops.
  static Future<void> stopService() async {
    if (!_isRunning) return;
    _isRunning = false;
    await FlutterForegroundTask.stopService();
  }

  static bool get isRunning => _isRunning;
}
