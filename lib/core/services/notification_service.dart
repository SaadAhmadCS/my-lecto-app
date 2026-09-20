import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notifications for processing results (IMP-06).
///
/// The payload of every notification is a recording ID; tapping one calls
/// [onRecordingTapped].
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  /// Opens a recording; set once the router exists.
  void Function(String recordingId)? onRecordingTapped;

  bool _permissionRequested = false;

  static const _channel = AndroidNotificationDetails(
    'lecto_processing',
    'Lecture notes',
    channelDescription: 'When transcripts and study notes are ready',
    importance: Importance.high,
    priority: Priority.high,
  );

  Future<void> initialize() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final recordingId = response.payload;
        if (recordingId != null) onRecordingTapped?.call(recordingId);
      },
    );
  }

  /// Recording ID of the notification that launched the app, if any.
  Future<String?> launchRecordingId() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return details!.notificationResponse?.payload;
  }

  /// Ask once per app run (Android 13+ / iOS), when a notification is about
  /// to become useful rather than at startup.
  Future<void> requestPermissionIfNeeded() async {
    if (_permissionRequested) return;
    _permissionRequested = true;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, sound: true);
    } catch (e) {
      debugPrint('NotificationService: permission request failed: $e');
    }
  }

  Future<void> cancelAll() => _plugin.cancelAll();

  Future<void> showRecordingUpdate({
    required String recordingId,
    required String title,
    required String body,
  }) {
    return _plugin.show(
      // Stable per recording so a later update replaces the earlier one
      id: recordingId.hashCode & 0x7fffffff,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: _channel,
        iOS: DarwinNotificationDetails(),
      ),
      payload: recordingId,
    );
  }
}
