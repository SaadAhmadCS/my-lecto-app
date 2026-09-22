import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../recording/data/local/recording_database.dart';

/// Labs are their own subjects, linked to their theory course by `lab_of`.
///
/// A lab often has a different teacher, its own marks and its own
/// assignments, so its lectures, tasks and quizzes must not mix with the
/// theory ones. These helpers keep a timetable class and the folder it
/// records into in step: a lab class always lands in the lab folder.
class LabSubjects {
  static const _uuid = Uuid();

  /// "Computer Architecture" → "Computer Architecture Lab".
  static String labName(String theoryName) => '$theoryName Lab';

  /// Whether [name] already says it is a lab ("Physics Lab", "Lab: Physics").
  static bool soundsLikeLab(String name) =>
      RegExp(r'\b(lab|laboratory|practical)\b', caseSensitive: false)
          .hasMatch(name);

  /// [name] without a trailing "Lab", "(Lab)" or "Laboratory", so an imported
  /// "Computer Architecture Lab" matches the "Computer Architecture" course.
  static String withoutLab(String name) {
    final stripped = name
        .replaceAll(
          RegExp(
            r'[\s\-–—:]*\(?\b(lab|laboratory|practical)\b\)?\s*$',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    return stripped.isEmpty ? name.trim() : stripped;
  }

  /// The subject a class of [subjectId] should be filed under.
  ///
  /// A lab class goes to the course's lab folder, created on first use; a
  /// lecture goes to the theory course, even when picked from its lab.
  static Future<String> subjectForClass(
    DatabaseExecutor db,
    String subjectId, {
    required bool isLab,
  }) => isLab ? labFor(db, subjectId) : theoryFor(db, subjectId);

  /// The lab folder of [subjectId], creating it if it has none.
  ///
  /// A subject that is already a lab is returned as is.
  static Future<String> labFor(DatabaseExecutor db, String subjectId) async {
    if (subjectId == RecordingDatabase.unsortedSubjectId) return subjectId;

    final rows = await db.query(
      'subjects',
      columns: ['id', 'name', 'color', 'lab_of'],
      where: 'id = ?',
      whereArgs: [subjectId],
    );
    if (rows.isEmpty) return subjectId;
    final subject = rows.first;
    // Already a lab: linked to a course, or made by hand as "Physics Lab".
    if (subject['lab_of'] != null || soundsLikeLab(subject['name'] as String)) {
      return subjectId;
    }

    final existing = await db.query(
      'subjects',
      columns: ['id'],
      where: 'lab_of = ?',
      whereArgs: [subjectId],
      limit: 1,
    );
    if (existing.isNotEmpty) return existing.first['id'] as String;

    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    await db.insert('subjects', {
      'id': id,
      'name': labName(subject['name'] as String),
      // Same colour, so the pair reads as one course everywhere.
      'color': subject['color'],
      'lab_of': subjectId,
      'created_at': now,
      'updated_at': now,
    });
    return id;
  }

  /// The theory course of [subjectId], or [subjectId] if it is not a lab.
  static Future<String> theoryFor(DatabaseExecutor db, String subjectId) async {
    final rows = await db.query(
      'subjects',
      columns: ['lab_of'],
      where: 'id = ?',
      whereArgs: [subjectId],
    );
    return (rows.isEmpty ? null : rows.first['lab_of'] as String?) ??
        subjectId;
  }

  /// Give every course with lab classes its own lab folder, and move those
  /// classes into it. Safe to run again: labs already split are left alone.
  static Future<void> splitTimetableLabs(DatabaseExecutor db) async {
    final labSlots = await db.rawQuery('''
      SELECT t.id, t.subject_id
      FROM timetable_slots t
      JOIN subjects s ON s.id = t.subject_id
      WHERE t.is_lab = 1 AND s.lab_of IS NULL
    ''');
    for (final slot in labSlots) {
      final labId = await labFor(db, slot['subject_id'] as String);
      await db.update(
        'timetable_slots',
        {'subject_id': labId},
        where: 'id = ?',
        whereArgs: [slot['id']],
      );
    }
  }
}
