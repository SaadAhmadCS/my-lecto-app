import 'package:uuid/uuid.dart';

import '../../recording/data/local/recording_database.dart';
import 'lab_subjects.dart';

/// Subjects, stored on the device.
///
/// Rows come back in the shape the screens already used when subjects lived on
/// a server — `id`, `name`, `color` and a `_count.recordings` — so the UI did
/// not have to change when the backend went away.
class SubjectDao {
  static const _uuid = Uuid();

  /// Every subject, each with how many recordings it holds.
  ///
  /// Unsorted sorts last: it is a fallback, not a real subject. A lab sorts
  /// straight after its theory course.
  Future<List<Map<String, dynamic>>> listSubjects() async {
    final db = await RecordingDatabase.database;

    final rows = await db.rawQuery(
      '''
      SELECT s.id, s.name, s.color, s.created_at, s.lab_of, s.teacher,
             COUNT(r.id) AS recording_count,
             MAX(r.created_at) AS last_recorded_at,
             COALESCE(SUM(r.total_duration_ms), 0) AS total_ms,
             SUM(CASE WHEN r.id IS NOT NULL
                       AND (r.notes_markdown IS NULL OR r.notes_markdown = '')
                       AND r.status != 'recording'
                      THEN 1 ELSE 0 END) AS awaiting
      FROM subjects s
      LEFT JOIN subjects p ON p.id = s.lab_of
      LEFT JOIN recordings r ON r.subject_id = s.id
      GROUP BY s.id
      ORDER BY (s.id = ?) ASC,
               COALESCE(p.name, s.name) COLLATE NOCASE ASC,
               (s.lab_of IS NOT NULL) ASC
    ''',
      [RecordingDatabase.unsortedSubjectId],
    );

    return rows.map(_toApiShape).toList();
  }

  Future<Map<String, dynamic>?> getSubject(String id) async {
    final db = await RecordingDatabase.database;

    final rows = await db.rawQuery(
      '''
      SELECT s.id, s.name, s.color, s.created_at, s.lab_of, s.teacher,
             COUNT(r.id) AS recording_count,
             MAX(r.created_at) AS last_recorded_at,
             COALESCE(SUM(r.total_duration_ms), 0) AS total_ms,
             SUM(CASE WHEN r.id IS NOT NULL
                       AND (r.notes_markdown IS NULL OR r.notes_markdown = '')
                       AND r.status != 'recording'
                      THEN 1 ELSE 0 END) AS awaiting
      FROM subjects s
      LEFT JOIN recordings r ON r.subject_id = s.id
      WHERE s.id = ?
      GROUP BY s.id
    ''',
      [id],
    );

    return rows.isEmpty ? null : _toApiShape(rows.first);
  }

  /// Create a subject and return it.
  Future<Map<String, dynamic>> createSubject({
    required String name,
    required String color,
    String? teacher,
  }) async {
    final db = await RecordingDatabase.database;
    final now = DateTime.now().toIso8601String();
    final id = _uuid.v4();
    final cleanTeacher = _clean(teacher);

    await db.insert('subjects', {
      'id': id,
      'name': name,
      'color': color,
      'teacher': cleanTeacher,
      'created_at': now,
      'updated_at': now,
    });

    return {
      'id': id,
      'name': name,
      'color': color,
      'teacher': cleanTeacher,
      'labOf': null,
      'isLab': LabSubjects.soundsLikeLab(name),
      'createdAt': now,
      '_count': {'recordings': 0},
    };
  }

  /// The lab folder of theory course [id], creating it if needed.
  Future<String> labFor(String id) async {
    final db = await RecordingDatabase.database;
    return LabSubjects.labFor(db, id);
  }

  /// The other half of a course: its lab for a theory course, its theory
  /// course for a lab. Null when there is none.
  Future<Map<String, dynamic>?> pairOf(String id) async {
    final db = await RecordingDatabase.database;
    final rows = await db.rawQuery(
      '''
      SELECT id FROM subjects
      WHERE id = (SELECT lab_of FROM subjects WHERE id = ?) OR lab_of = ?
      LIMIT 1
    ''',
      [id, id],
    );
    return rows.isEmpty ? null : getSubject(rows.first['id'] as String);
  }

  /// Update a subject. An empty [teacher] clears it.
  ///
  /// Renaming a course renames its lab with it, unless the lab was renamed
  /// by hand.
  Future<void> updateSubject(
    String id, {
    String? name,
    String? color,
    String? teacher,
  }) async {
    if (name == null && color == null && teacher == null) return;

    final db = await RecordingDatabase.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      if (name != null) {
        final old = await txn.query(
          'subjects',
          columns: ['name'],
          where: 'id = ?',
          whereArgs: [id],
        );
        if (old.isNotEmpty) {
          await txn.update(
            'subjects',
            {'name': LabSubjects.labName(name), 'updated_at': now},
            where: 'lab_of = ? AND name = ?',
            whereArgs: [id, LabSubjects.labName(old.first['name'] as String)],
          );
        }
      }
      await txn.update(
        'subjects',
        {
          if (name != null) 'name': name,
          if (color != null) 'color': color,
          if (teacher != null) 'teacher': _clean(teacher),
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  static String? _clean(String? text) {
    final trimmed = text?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Delete a subject, moving its recordings to Unsorted.
  ///
  /// Deleting a folder should never destroy the lectures inside it.
  Future<void> deleteSubject(String id) async {
    if (id == RecordingDatabase.unsortedSubjectId) return;

    final db = await RecordingDatabase.database;
    await db.transaction((txn) async {
      await txn.update(
        'recordings',
        {'subject_id': RecordingDatabase.unsortedSubjectId},
        where: 'subject_id = ?',
        whereArgs: [id],
      );
      // A class with no subject has nothing to record into.
      await txn.delete(
        'timetable_slots',
        where: 'subject_id = ?',
        whereArgs: [id],
      );
      // Its lab stays, as a course of its own.
      await txn.update(
        'subjects',
        {'lab_of': null},
        where: 'lab_of = ?',
        whereArgs: [id],
      );
      await txn.delete('subjects', where: 'id = ?', whereArgs: [id]);
    });
  }

  static Map<String, dynamic> _toApiShape(Map<String, Object?> row) => {
    'id': row['id'],
    'name': row['name'],
    'color': row['color'],
    'teacher': row['teacher'],
    // The theory course this lab belongs to, if it is one.
    'labOf': row['lab_of'],
    'isLab':
        row['lab_of'] != null ||
        LabSubjects.soundsLikeLab(row['name'] as String? ?? ''),
    'createdAt': row['created_at'],
    'lastRecordedAt': row['last_recorded_at'],
    'totalDurationMs': (row['total_ms'] as int?) ?? 0,
    // Finished lectures still waiting for notes from the student's AI.
    'awaitingCount': (row['awaiting'] as int?) ?? 0,
    '_count': {'recordings': (row['recording_count'] as int?) ?? 0},
  };
}
