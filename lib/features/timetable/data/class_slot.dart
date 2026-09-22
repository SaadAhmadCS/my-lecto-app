import 'package:flutter/material.dart';

import '../../subjects/data/lab_subjects.dart';

/// One weekly class: a subject on a weekday between two times.
class ClassSlot {
  final String id;
  final String subjectId;
  final String subjectName;
  final String? subjectColor;

  /// 1 = Monday … 7 = Sunday, as [DateTime.weekday].
  final int weekday;

  /// Minutes after midnight, local time.
  final int startMinute;
  final int endMinute;
  final String? room;
  final bool isLab;

  /// Whether this class gets a "start recording" nudge.
  final bool remind;

  const ClassSlot({
    required this.id,
    required this.subjectId,
    required this.subjectName,
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
    this.subjectColor,
    this.room,
    this.isLab = false,
    this.remind = true,
  });

  factory ClassSlot.fromRow(Map<String, Object?> row) => ClassSlot(
    id: row['id'] as String,
    subjectId: row['subject_id'] as String,
    subjectName: row['subject_name'] as String? ?? 'Untitled',
    subjectColor: row['subject_color'] as String?,
    weekday: row['weekday'] as int,
    startMinute: row['start_minute'] as int,
    endMinute: row['end_minute'] as int,
    room: row['room'] as String?,
    isLab: (row['is_lab'] as int? ?? 0) == 1,
    remind: (row['remind'] as int? ?? 1) == 1,
  );

  TimeOfDay get start =>
      TimeOfDay(hour: startMinute ~/ 60, minute: startMinute % 60);
  TimeOfDay get end => TimeOfDay(hour: endMinute ~/ 60, minute: endMinute % 60);

  Duration get length => Duration(minutes: endMinute - startMinute);

  /// "Linear Algebra", or "Linear Algebra (Lab)" for a lab whose folder name
  /// does not already say so ("Linear Algebra Lab" stays as it is).
  String get displayName => isLab && !LabSubjects.soundsLikeLab(subjectName)
      ? '$subjectName (Lab)'
      : subjectName;

  Color get color {
    try {
      return Color(int.parse((subjectColor ?? '').replaceFirst('#', '0xFF')));
    } catch (_) {
      return const Color(0xFFF16743);
    }
  }

  /// Whether [now] falls in this class, counting [earlyBy] before it starts
  /// so someone settling in a few minutes early still matches.
  bool isOnAt(DateTime now, {Duration earlyBy = const Duration(minutes: 15)}) {
    if (now.weekday != weekday) return false;
    final minute = now.hour * 60 + now.minute;
    return minute >= startMinute - earlyBy.inMinutes && minute < endMinute;
  }

  /// When this class next starts after [now].
  DateTime nextStart(DateTime now) {
    var date = DateTime(
      now.year,
      now.month,
      now.day,
      startMinute ~/ 60,
      startMinute % 60,
    );
    while (date.weekday != weekday || !date.isAfter(now)) {
      date = DateTime(
        date.year,
        date.month,
        date.day + 1,
        date.hour,
        date.minute,
      );
    }
    return date;
  }

  /// The end of this class on [day]'s date.
  DateTime endOn(DateTime day) =>
      DateTime(day.year, day.month, day.day, endMinute ~/ 60, endMinute % 60);

  static const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const weekdayLong = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
}

/// The icon for a kind of class, so a lab reads apart from a lecture at a
/// glance wherever classes are listed or picked.
extension ClassKindIcon on ClassSlot {
  IconData get kindIcon => isLab ? labIcon : lectureIcon;

  static const IconData labIcon = Icons.science_rounded;
  static const IconData lectureIcon = Icons.menu_book_rounded;
}
