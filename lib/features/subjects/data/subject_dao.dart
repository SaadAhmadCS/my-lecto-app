import 'package:uuid/uuid.dart';

import '../../recording/data/local/recording_database.dart';

/// Subjects, stored on the device.
///
/// Rows come back in the shape the screens already used when subjects lived on
/// a server — `id`, `name`, `color` and a `_count.recordings` — so the UI did
/// not have to change when the backend went away.
class SubjectDao {
  static const _uuid = Uuid();

  /// Every subject, each with how many recordings it holds.
  ///
  /// Unsorted sorts last: it is a fallback, not a real subject.
  Future<List<Map<String, dynamic>>> listSubjects() async {
    final db = await RecordingDatabase.database;

    final rows = await db.rawQuery(
      '''
      SELECT s.id, s.name, s.color, s.created_at,
             COUNT(r.id) AS recording_count,
             MAX(r.created_at) AS last_recorded_at,
             COALESCE(SUM(r.total_duration_ms), 0) AS total_ms,
             SUM(CASE WHEN r.id IS NOT NULL
                       AND (r.notes_markdown IS NULL OR r.notes_markdown = '')
                       AND r.status != 'recording'
                      THEN 1 ELSE 0 END) AS awaiting
      FROM subjects s
      LEFT JOIN recordings r ON r.subject_id = s.id
      GROUP BY s.id
      ORDER BY (s.id = ?) ASC, s.name COLLATE NOCASE ASC
    ''',
      [RecordingDatabase.unsortedSubjectId],
    );

    return rows.map(_toApiShape).toList();
  }

  Future<Map<String, dynamic>?> getSubject(String id) async {
    final db = await RecordingDatabase.database;

    final rows = await db.rawQuery(
      '''
      SELECT s.id, s.name, s.color, s.created_at,
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
  }) async {
    final db = await RecordingDatabase.database;
    final now = DateTime.now().toIso8601String();
    final id = _uuid.v4();

    await db.insert('subjects', {
      'id': id,
      'name': name,
      'color': color,
      'created_at': now,
      'updated_at': now,
    });

    return {
      'id': id,
      'name': name,
      'color': color,
      'createdAt': now,
      '_count': {'recordings': 0},
    };
  }

  Future<void> updateSubject(String id, {String? name, String? color}) async {
    if (name == null && color == null) return;

    final db = await RecordingDatabase.database;
    await db.update(
      'subjects',
      {
        if (name != null) 'name': name,
        if (color != null) 'color': color,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
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
      await txn.delete('subjects', where: 'id = ?', whereArgs: [id]);
    });
  }

  static Map<String, dynamic> _toApiShape(Map<String, Object?> row) => {
    'id': row['id'],
    'name': row['name'],
    'color': row['color'],
    'createdAt': row['created_at'],
    'lastRecordedAt': row['last_recorded_at'],
    'totalDurationMs': (row['total_ms'] as int?) ?? 0,
    // Finished lectures still waiting for notes from the student's AI.
    'awaitingCount': (row['awaiting'] as int?) ?? 0,
    '_count': {'recordings': (row['recording_count'] as int?) ?? 0},
  };
}
