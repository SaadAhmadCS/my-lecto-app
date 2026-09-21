import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notifications: "recording saved" updates and class reminders.
///
/// Every notification carries a payload, and tapping one calls [onTapped]
/// with it. A recording ID opens that recording; class reminders use the
/// payloads defined in `ClassReminderService`.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// The shared plugin, for services that schedule their own notifications.
  FlutterLocalNotificationsPlugin get plugin => _plugin;

  /// Handles a tapped notification's payload; set once the router exists.
  void Function(String payload)? onTapped;

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
        final payload = response.payload;
        if (payload != null) onTapped?.call(payload);
      },
    );
  }

  /// Payload of the notification that launched the app, if any.
  Future<String?> launchPayload() async {
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
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
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
