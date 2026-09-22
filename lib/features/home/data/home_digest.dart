import 'package:flutter/foundation.dart';

import '../../../core/services/notes_parser.dart';
import '../../recording/data/local/recording_dao.dart';
import '../../recording/data/local/recording_database.dart';
import '../../recording/data/local/recording_feed.dart';
import '../../subjects/data/subject_dao.dart';

/// What kind of thing is coming up.
///
/// Worked out from the wording of a deadline, since the notes do not label
/// them. "Quiz on chapter 4" is a quiz; "Lab report 3" is an assignment.
enum UpcomingKind {
  quiz('Quiz'),
  assignment('Assignment'),
  other('Due');

  const UpcomingKind(this.label);
  final String label;

  /// Words that mean a quiz on their own.
  static const _quizWords = ['quiz', 'exam', 'test', 'midterm', 'viva'];

  /// Words that suggest a quiz but often sit next to an assignment word —
  /// "final project" is a project, "final exam" is an exam.
  static const _weakQuizWords = ['final', 'finals', 'paper'];

  static const _assignmentWords = [
    'assignment',
    'report',
    'problem set',
    'essay',
    'submission',
    'homework',
    'project',
    'presentation',
    'lab',
  ];

  /// Whole-word match, so "syllabus" is not a lab and "latest" is not a test.
  static bool _mentions(String text, List<String> words) => words.any(
    (word) =>
        RegExp('(?<![a-z])${RegExp.escape(word)}(?![a-z])').hasMatch(text),
  );

  static UpcomingKind from(String description) {
    final text = description.toLowerCase();
    if (_mentions(text, _quizWords)) return UpcomingKind.quiz;
    if (_mentions(text, _assignmentWords)) return UpcomingKind.assignment;
    if (_mentions(text, _weakQuizWords)) return UpcomingKind.quiz;
    return UpcomingKind.other;
  }
}

/// One piece of work from a lecture: a graded assignment or an ungraded task.
class HomeTask {
  final String text;
  final bool done;
  final String recordingId;
  final String recordingTitle;
  final String? subjectName;

  /// The subject's colour, as stored: "#5244e3".
  final String? subjectColor;

  /// The nearest deadline from the same lecture, when it had one. Tasks
  /// themselves carry no date — this is the best available signal.
  final DateTime? dueAt;

  /// Graded work the lecturer set, as opposed to reading or practice.
  final bool isAssignment;

  /// How to submit it, marks, format — whatever the lecture said.
  final String? details;

  /// Where the checklist line sits in the lecture's notes, so it can be ticked
  /// from outside the notes screen.
  final int? lineIndex;

  const HomeTask({
    required this.text,
    required this.done,
    required this.recordingId,
    required this.recordingTitle,
    this.subjectName,
    this.subjectColor,
    this.dueAt,
    this.lineIndex,
    this.isAssignment = false,
    this.details,
  });

  bool get isDueToday {
    final due = dueAt;
    if (due == null) return false;
    final now = DateTime.now();
    return due.year == now.year && due.month == now.month && due.day == now.day;
  }
}

/// A dated commitment pulled out of a lecture's notes.
class UpcomingItem {
  final String title;
  final DateTime? date;
  final String rawDate;
  final UpcomingKind kind;
  final String recordingId;
  final String recordingTitle;
  final String? subjectName;

  /// The subject's colour, as stored: "#5244e3".
  final String? subjectColor;

  /// What it covers, its format, how to submit — whatever the lecture said.
  final String? details;

  const UpcomingItem({
    required this.title,
    required this.rawDate,
    required this.kind,
    required this.recordingId,
    required this.recordingTitle,
    this.date,
    this.subjectName,
    this.subjectColor,
    this.details,
  });

  /// Whole days from today. Negative once it has passed.
  int? get daysAway {
    final due = date;
    if (due == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(due.year, due.month, due.day).difference(today).inDays;
  }
}

/// Everything the dashboard shows, gathered in one pass.
class HomeDigest {
  final List<HomeTask> tasks;
  final List<UpcomingItem> upcoming;
  final int subjectCount;
  final int recordingCount;
  final int awaitingCount;
  final int streakDays;

  const HomeDigest({
    this.tasks = const [],
    this.upcoming = const [],
    this.subjectCount = 0,
    this.recordingCount = 0,
    this.awaitingCount = 0,
    this.streakDays = 0,
  });

  int get openTaskCount => tasks.where((task) => !task.done).length;

  /// Open tasks, soonest first, with undated ones last.
  List<HomeTask> get todayTasks {
    final open = tasks.where((task) => !task.done).toList()
      ..sort((a, b) {
        if (a.dueAt == null && b.dueAt == null) return 0;
        if (a.dueAt == null) return 1;
        if (b.dueAt == null) return -1;
        return a.dueAt!.compareTo(b.dueAt!);
      });
    // A couple of finished ones give the list a sense of progress.
    final done = tasks.where((task) => task.done).take(2);
    return [...open, ...done];
  }

  /// Still to come, soonest first.
  List<UpcomingItem> get futureItems {
    final future =
        upcoming.where((item) {
            final days = item.daysAway;
            return days == null || days >= 0;
          }).toList()
          ..sort((a, b) => (a.daysAway ?? 9999).compareTo(b.daysAway ?? 9999));
    return future;
  }

  int get quizzesThisWeek => upcoming.where((item) {
    final days = item.daysAway;
    return item.kind == UpcomingKind.quiz &&
        days != null &&
        days >= 0 &&
        days <= 7;
  }).length;
}

/// Builds the dashboard's data out of the notes already on the device.
///
/// Tasks and deadlines are not stored as rows — they live inside the markdown
/// each AI reply produced — so they are parsed back out on demand.
class HomeDigestBuilder {
  final RecordingDao _dao;
  final RecordingFeed _feed;
  final SubjectDao _subjects;

  const HomeDigestBuilder({
    required RecordingDao dao,
    required RecordingFeed feed,
    required SubjectDao subjects,
  }) : _dao = dao,
       _feed = feed,
       _subjects = subjects;

  /// The most recent digest, so a screen coming back into view can show it
  /// at once and refresh quietly rather than flash a loading state.
  static HomeDigest? last;

  Future<HomeDigest> build() async {
    try {
      final subjects = await _subjects.listSubjects();
      final recordings = await _feed.list();
      final awaiting = await _feed.awaitingCount();

      final tasks = <HomeTask>[];
      final upcoming = <UpcomingItem>[];

      for (final recording in recordings) {
        final id = recording['id'] as String;
        // The feed already read the notes; no second query per lecture.
        final markdown = recording['notesMarkdown'] as String?;
        if (markdown == null || markdown.isEmpty) continue;

        final parsed = NotesParser.parse(markdown);
        final title = recording['title'] as String? ?? 'Recording';
        final subjectMap = recording['subject'] as Map<String, dynamic>?;
        final subject = subjectMap?['name'] as String?;
        final subjectColor = subjectMap?['color'] as String?;

        // Older notes (before assignments had their own section and dates)
        // lean on the lecture's nearest deadline for their tasks' urgency.
        // Newer notes date the assignments themselves, so tasks stay undated.
        final legacy = parsed.assignments.isEmpty && parsed.quizzes.isEmpty;
        final nearest = legacy ? _nearestDate(parsed.deadlines) : null;

        for (final assignment in parsed.assignments) {
          tasks.add(
            HomeTask(
              text: assignment.text,
              done: assignment.done,
              recordingId: id,
              recordingTitle: title,
              subjectName: subject,
              subjectColor: subjectColor,
              dueAt: assignment.done ? null : assignment.due,
              lineIndex: assignment.lineIndex,
              isAssignment: true,
              details: assignment.details,
            ),
          );
          final due = assignment.due;
          if (due != null) {
            upcoming.add(
              UpcomingItem(
                title: assignment.text,
                date: due,
                rawDate: '',
                kind: UpcomingKind.assignment,
                recordingId: id,
                recordingTitle: title,
                subjectName: subject,
                subjectColor: subjectColor,
                details: assignment.details,
              ),
            );
          }
        }

        for (final task in parsed.tasks) {
          tasks.add(
            HomeTask(
              text: task.text,
              done: task.done,
              recordingId: id,
              recordingTitle: title,
              subjectName: subject,
              subjectColor: subjectColor,
              dueAt: task.done ? null : nearest,
              lineIndex: task.lineIndex,
            ),
          );
        }

        for (final quiz in parsed.quizzes) {
          upcoming.add(
            UpcomingItem(
              title: quiz.title,
              date: quiz.date,
              rawDate: quiz.rawDate,
              kind: UpcomingKind.quiz,
              recordingId: id,
              recordingTitle: title,
              subjectName: subject,
              subjectColor: subjectColor,
              details: quiz.details,
            ),
          );
        }

        for (final deadline in parsed.deadlines) {
          upcoming.add(
            UpcomingItem(
              title: deadline.description,
              date: deadline.date,
              rawDate: deadline.rawDate,
              kind: UpcomingKind.from(deadline.description),
              recordingId: id,
              recordingTitle: title,
              subjectName: subject,
              subjectColor: subjectColor,
            ),
          );
        }
      }

      return last = HomeDigest(
        tasks: tasks,
        upcoming: upcoming,
        // Unsorted is a holding folder, not a course.
        subjectCount: subjects
            // A lab is part of its course, not another course.
            .where(
              (s) =>
                  s['id'] != RecordingDatabase.unsortedSubjectId &&
                  s['isLab'] != true,
            )
            .length,
        recordingCount: recordings.length,
        awaitingCount: awaiting,
        streakDays: _streak(recordings),
      );
    } catch (e) {
      debugPrint('HomeDigest: could not build: $e');
      return const HomeDigest();
    }
  }

  /// Tick or untick [task] in its lecture's notes. Returns whether it changed.
  ///
  /// The notes may have been re-pasted since the task was read, so the line is
  /// only rewritten if it is still the same task.
  Future<bool> toggleTask(HomeTask task) async {
    final lineIndex = task.lineIndex;
    if (lineIndex == null) return false;

    final notes = await _dao.getNotes(task.recordingId);
    if (notes == null) return false;

    final lines = notes.notesMarkdown.split('\n');
    if (lineIndex >= lines.length || !lines[lineIndex].contains(task.text)) {
      return false;
    }

    final updated = NotesParser.toggleTask(
      notes.notesMarkdown,
      NoteTask(text: task.text, done: task.done, lineIndex: lineIndex),
    );
    if (updated == notes.notesMarkdown) return false;

    await _dao.updateNotesMarkdown(
      id: task.recordingId,
      notesMarkdown: updated,
    );
    return true;
  }

  static DateTime? _nearestDate(List<NoteDeadline> deadlines) {
    final dates =
        deadlines
            .map((deadline) => deadline.date)
            .whereType<DateTime>()
            .toList()
          ..sort();
    return dates.isEmpty ? null : dates.first;
  }

  /// Consecutive days up to today on which something was recorded.
  ///
  /// Today having no recording yet does not break a streak — it only ends
  /// once a whole day passes with nothing.
  static int _streak(List<Map<String, dynamic>> recordings) {
    final days = <DateTime>{};
    for (final recording in recordings) {
      final created = DateTime.tryParse(
        recording['createdAt'] as String? ?? '',
      );
      if (created != null) {
        days.add(DateTime(created.year, created.month, created.day));
      }
    }
    if (days.isEmpty) return 0;

    final now = DateTime.now();
    var cursor = DateTime(now.year, now.month, now.day);
    if (!days.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (!days.contains(cursor)) return 0;
    }

    var streak = 0;
    while (days.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }
}
