import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../subjects/data/subject_dao.dart';
import '../../timetable/data/class_slot.dart';
import '../../timetable/data/timetable_dao.dart';
import '../../timetable/services/class_reminder_service.dart';
import '../data/local/recording_database.dart';
import 'bloc/recording_bloc.dart';
import 'bloc/recording_event.dart';

/// Start recording in [subjectId], knowing about the timetable.
///
/// The recording is named after the subject and date ("Linear Algebra · Mon
/// 21 Sep") rather than a timestamp. If that subject's class is on right now,
/// the name says whether it is the lab, and a "class ended" nudge is set for
/// when it finishes. Quick record keeps the plain timestamp name.
Future<void> startRecordingIn(BuildContext context, String subjectId) async {
  final bloc = context.read<RecordingBloc>();
  final subjects = context.read<SubjectDao>();
  final timetable = context.read<TimetableDao>();
  final reminders = context.read<ClassReminderService>();

  if (bloc.isActive) return;

  final now = DateTime.now();
  String? title;
  ClassSlot? slot;

  if (subjectId != RecordingDatabase.unsortedSubjectId) {
    try {
      final active = await timetable.activeAt(now);
      if (active?.subjectId == subjectId) slot = active;
      final subject = await subjects.getSubject(subjectId);
      final name = slot?.displayName ?? subject?['name'] as String?;
      if (name != null) title = '$name · ${_date(now)}';
    } catch (_) {
      // Naming is a nicety; never let it stop a lecture being recorded.
    }
  }

  bloc.add(StartRecordingEvent(subjectId: subjectId, title: title));
  if (slot != null) await reminders.scheduleEndNudge(slot);
}

String _date(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${ClassSlot.weekdayShort[date.weekday - 1]} '
      '${date.day} ${months[date.month - 1]}';
}
