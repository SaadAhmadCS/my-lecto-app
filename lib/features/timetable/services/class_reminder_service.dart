import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/services/notification_service.dart';
import '../data/class_slot.dart';
import '../data/timetable_dao.dart';

/// Nudges you to start recording as each class begins.
///
/// Every class with reminders on gets a weekly repeating notification a couple
/// of minutes before it starts. They are scheduled with the OS, so they fire
/// whether or not the app is open, and survive a reboot. Tapping one opens the
/// app and starts recording in that class's subject.
///
/// While a class is being recorded, a one-off "class ended" nudge is also set
/// for its end time, since lectures overrun and stopping is left to you.
class ClassReminderService {
  final NotificationService _notifications;
  final TimetableDao _timetable;

  ClassReminderService({
    required NotificationService notifications,
    required TimetableDao timetable,
  }) : _notifications = notifications,
       _timetable = timetable;

  /// How early the nudge arrives. Early enough to still be sitting down,
  /// late enough that the lecturer is about to begin.
  static const Duration lead = Duration(minutes: 2);

  /// Payload of a class reminder: `class:<slot id>`.
  static const classPayloadPrefix = 'class:';

  /// Payload of the "class ended" nudge: opens the recorder.
  static const recorderPayload = 'recorder';

  static const _enabledKey = 'classRemindersOn';

  /// Class reminder IDs live in their own block, clear of recording updates.
  static const _idBlock = 0x7E000000;
  static const _endReminderId = 0x7DFFFFFF;

  static const _channel = AndroidNotificationDetails(
    'lecto_classes',
    'Class reminders',
    channelDescription: 'A nudge to start recording when a class begins',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
  );

  bool _timeZoneReady = false;

  FlutterLocalNotificationsPlugin get _plugin => _notifications.plugin;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    if (enabled) await _notifications.requestPermissionIfNeeded();
    await reschedule();
  }

  /// Whether the app may show notifications at all (Android 13+ asks).
  ///
  /// Without it every reminder is scheduled, fires on time and is silently
  /// dropped — verified on device — so the timetable asks and warns.
  Future<bool> canNotify() async {
    try {
      return await _android?.areNotificationsEnabled() ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Show the system's notification prompt. Returns whether it is now
  /// allowed; false after a permanent "Don't allow", when only the app's
  /// settings page can turn it back on.
  Future<bool> askToNotify() async {
    try {
      return await _android?.requestNotificationsPermission() ?? true;
    } catch (_) {
      return false;
    }
  }

  /// Whether Android lets reminders fire on the exact minute. Without it the
  /// OS may hold one back by up to an hour, so the timetable screen asks.
  Future<bool> canBeExact() async {
    try {
      return await _android?.canScheduleExactNotifications() ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Send the user to the system screen that allows exact alarms.
  Future<void> requestExact() async {
    await _android?.requestExactAlarmsPermission();
    await reschedule();
  }

  /// Rebuild every class reminder from the timetable.
  ///
  /// Called at launch and after any timetable change. Cheap: a week holds a
  /// few dozen classes at most.
  Future<void> reschedule() async {
    try {
      await _ensureTimeZone();

      for (final pending in await _plugin.pendingNotificationRequests()) {
        if (pending.payload?.startsWith(classPayloadPrefix) ?? false) {
          await _plugin.cancel(id: pending.id);
        }
      }
      if (!await isEnabled()) return;

      final mode = await canBeExact()
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;

      for (final slot in await _timetable.list()) {
        if (!slot.remind) continue;
        await _plugin.zonedSchedule(
          id: _idFor(slot),
          title: '${slot.displayName} starts in ${lead.inMinutes} min',
          body: [
            if (slot.room != null) slot.room!,
            'Tap to start recording',
          ].join(' · '),
          scheduledDate: _nextNudge(slot),
          notificationDetails: const NotificationDetails(
            android: _channel,
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: mode,
          // Repeats every week at the same day and time.
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          payload: '$classPayloadPrefix${slot.id}',
        );
      }
    } catch (e, stack) {
      debugPrint('ClassReminderService: could not schedule: $e\n$stack');
    }
  }

  /// Nudge at [slot]'s end, for a recording of it that is still running.
  Future<void> scheduleEndNudge(ClassSlot slot) async {
    try {
      await _ensureTimeZone();
      final end = slot.endOn(DateTime.now());
      if (!end.isAfter(DateTime.now())) return;

      await _plugin.zonedSchedule(
        id: _endReminderId,
        title: '${slot.displayName} has ended',
        body: 'Still recording · tap to stop and save',
        scheduledDate: tz.TZDateTime.from(end, tz.local),
        notificationDetails: const NotificationDetails(
          android: _channel,
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: await canBeExact()
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        payload: recorderPayload,
      );
    } catch (e) {
      debugPrint('ClassReminderService: could not set end nudge: $e');
    }
  }

  /// The recording stopped, so the "class ended" nudge has nothing to say.
  Future<void> cancelEndNudge() async {
    try {
      await _plugin.cancel(id: _endReminderId);
    } catch (_) {}
  }

  /// Next time [slot]'s nudge is due, in the device's time zone.
  ///
  /// Worked out in the device's own clock, then converted, so it lands on the
  /// right instant even if the zone lookup fell back to UTC.
  tz.TZDateTime _nextNudge(ClassSlot slot) {
    final now = DateTime.now();
    final nudgeMinute = slot.startMinute - lead.inMinutes;
    var date = DateTime(
      now.year,
      now.month,
      now.day,
      nudgeMinute ~/ 60,
      nudgeMinute % 60,
    );
    while (date.weekday != slot.weekday || !date.isAfter(now)) {
      date = DateTime(
        date.year,
        date.month,
        date.day + 1,
        date.hour,
        date.minute,
      );
    }
    return tz.TZDateTime.from(date, tz.local);
  }

  static int _idFor(ClassSlot slot) =>
      _idBlock | (slot.id.hashCode & 0x00FFFFFF);

  Future<void> _ensureTimeZone() async {
    if (_timeZoneReady) return;
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (e) {
      // Fall back to UTC: reminders still fire, at the right instant for
      // anyone whose zone has no daylight saving changes.
      debugPrint('ClassReminderService: local time zone unknown ($e)');
    }
    _timeZoneReady = true;
  }
}
