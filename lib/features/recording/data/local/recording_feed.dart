import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'recording_database.dart';

/// Reads recordings for the list screens.
///
/// Rows come back with their subject already attached and their chunk count
/// counted, in the shape the cards expect.
class RecordingFeed {
  /// Status for a recording whose notes have not been pasted back yet.
  static const String awaitingNotes = 'awaiting_paste';

  /// Status for a recording that has notes.
  static const String ready = 'completed';

  /// Recordings, newest first.
  ///
  /// [subjectId] limits to one subject; [limit] caps the rows returned.
  Future<List<Map<String, dynamic>>> list({
    String? subjectId,
    int? limit,
  }) async {
    try {
      final db = await RecordingDatabase.database;

      final rows = await db.rawQuery(
        '''
        SELECT r.id, r.title, r.created_at, r.total_duration_ms,
               r.notes_markdown,
               s.id AS subject_id, s.name AS subject_name,
               s.color AS subject_color,
               (SELECT COUNT(*) FROM audio_chunks c
                 WHERE c.recording_id = r.id) AS chunk_count
        FROM recordings r
        LEFT JOIN subjects s ON s.id = r.subject_id
        ${subjectId != null ? 'WHERE r.subject_id = ?' : ''}
        ORDER BY r.created_at DESC
        ${limit != null ? 'LIMIT ?' : ''}
      ''',
        [if (subjectId != null) subjectId, if (limit != null) limit],
      );

      return rows.map(_toCardShape).toList();
    } catch (e) {
      debugPrint('RecordingFeed: could not read recordings: $e');
      return const [];
    }
  }

  /// How many finished recordings are still waiting for notes.
  ///
  /// One still being recorded is not waiting yet — it cannot be shared.
  Future<int> awaitingCount() async {
    try {
      final db = await RecordingDatabase.database;
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM recordings '
        "WHERE (notes_markdown IS NULL OR notes_markdown = '') "
        "AND status != 'recording'",
      );
      return Sqflite.firstIntValue(rows) ?? 0;
    } catch (e) {
      debugPrint('RecordingFeed: could not count recordings: $e');
      return 0;
    }
  }

  /// Total number of recordings.
  Future<int> total() async {
    try {
      final db = await RecordingDatabase.database;
      final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM recordings');
      return Sqflite.firstIntValue(rows) ?? 0;
    } catch (e) {
      debugPrint('RecordingFeed: could not count recordings: $e');
      return 0;
    }
  }

  static Map<String, dynamic> _toCardShape(Map<String, Object?> row) {
    final notes = row['notes_markdown'] as String?;
    final subjectId = row['subject_id'] as String?;

    return {
      'id': row['id'],
      'title': row['title'] ?? 'Untitled',
      'processingStatus': (notes != null && notes.isNotEmpty)
          ? ready
          : awaitingNotes,
      'createdAt': row['created_at'],
      'totalDurationMs': (row['total_duration_ms'] as int?) ?? 0,
      'notesMarkdown': notes,
      '_count': {'chunks': (row['chunk_count'] as int?) ?? 0},
      'subject': subjectId == null
          ? null
          : {
              'id': subjectId,
              'name': row['subject_name'],
              'color': row['subject_color'],
            },
    };
  }
}
