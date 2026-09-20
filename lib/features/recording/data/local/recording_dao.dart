import 'package:sqflite/sqflite.dart';

import 'recording_database.dart';

/// Data Access Object for recording persistence.
///
/// Handles all CRUD operations against the local SQLite database.
/// Ensures recordings survive app kills, crashes, and restarts.
class RecordingDao {
  /// Insert a new recording session.
  Future<void> insertRecording({
    required String id,
    required String subjectId,
    required String title,
    String status = 'recording',
    String audioFormat = 'aac',
    int chunkDurationMin = 15,
  }) async {
    final db = await RecordingDatabase.database;
    final now = DateTime.now().toIso8601String();

    await db.insert(
      'recordings',
      {
        'id': id,
        'subject_id': subjectId,
        'title': title,
        'status': status,
        'audio_format': audioFormat,
        'chunk_duration_min': chunkDurationMin,
        'total_duration_ms': 0,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Update recording status and duration.
  Future<void> updateRecording({
    required String id,
    String? status,
    int? totalDurationMs,
  }) async {
    final db = await RecordingDatabase.database;
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (status != null) updates['status'] = status;
    if (totalDurationMs != null) updates['total_duration_ms'] = totalDurationMs;

    await db.update('recordings', updates, where: 'id = ?', whereArgs: [id]);
  }

  /// Rename or re-file a recording on this device.
  ///
  /// A recording captured in "my own AI app" mode has no backend row, so the
  /// API cannot be the one to do this.
  Future<void> updateRecordingDetails({
    required String id,
    String? title,
    String? subjectId,
  }) async {
    if (title == null && subjectId == null) return;

    final db = await RecordingDatabase.database;
    await db.update(
      'recordings',
      {
        if (title != null) 'title': title,
        if (subjectId != null) 'subject_id': subjectId,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Store notes for a recording on this device.
  ///
  /// Used both for notes pasted back from the student's own AI app and for
  /// caching backend notes so they stay readable offline. [transcriptMarkdown]
  /// is optional — an AI app may return only notes for a long lecture.
  Future<void> saveNotes({
    required String id,
    required String notesMarkdown,
    String? transcriptMarkdown,
  }) async {
    final db = await RecordingDatabase.database;
    final now = DateTime.now().toIso8601String();

    final updates = <String, dynamic>{
      'notes_markdown': notesMarkdown,
      'notes_updated_at': now,
      'updated_at': now,
    };
    if (transcriptMarkdown != null && transcriptMarkdown.isNotEmpty) {
      updates['transcript_markdown'] = transcriptMarkdown;
    }

    await db.update('recordings', updates, where: 'id = ?', whereArgs: [id]);
  }

  /// Replace just the notes body, keeping the source and transcript.
  ///
  /// Toggling a checklist item rewrites the markdown, so this runs on every tap.
  Future<void> updateNotesMarkdown({
    required String id,
    required String notesMarkdown,
  }) async {
    final db = await RecordingDatabase.database;
    await db.update(
      'recordings',
      {
        'notes_markdown': notesMarkdown,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Locally stored notes for a recording, or null when there are none.
  Future<LocalNotes?> getNotes(String id) async {
    final db = await RecordingDatabase.database;
    final rows = await db.query(
      'recordings',
      columns: [
        'notes_markdown',
        'transcript_markdown',
        'notes_updated_at',
      ],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    final row = rows.first;
    final notes = row['notes_markdown'] as String?;
    if (notes == null || notes.isEmpty) return null;

    return LocalNotes(
      notesMarkdown: notes,
      transcriptMarkdown: row['transcript_markdown'] as String?,
      updatedAt: DateTime.tryParse(row['notes_updated_at'] as String? ?? ''),
    );
  }

  /// Get a recording by ID.
  Future<Map<String, dynamic>?> getRecording(String id) async {
    final db = await RecordingDatabase.database;
    final results = await db.query(
      'recordings',
      where: 'id = ?',
      whereArgs: [id],
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// List all recordings, optionally filtered by subject.
  Future<List<Map<String, dynamic>>> listRecordings({
    String? subjectId,
    String? status,
  }) async {
    final db = await RecordingDatabase.database;
    String? where;
    List<dynamic>? whereArgs;

    if (subjectId != null && status != null) {
      where = 'subject_id = ? AND status = ?';
      whereArgs = [subjectId, status];
    } else if (subjectId != null) {
      where = 'subject_id = ?';
      whereArgs = [subjectId];
    } else if (status != null) {
      where = 'status = ?';
      whereArgs = [status];
    }

    return db.query(
      'recordings',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
    );
  }

  /// Delete a recording and all its chunks/photos (via CASCADE).
  Future<void> deleteRecording(String id) async {
    final db = await RecordingDatabase.database;
    // Manual cascade since sqflite doesn't enforce FK constraints by default
    await db.delete('photos', where: 'recording_id = ?', whereArgs: [id]);
    await db.delete('audio_chunks', where: 'recording_id = ?', whereArgs: [id]);
    await db.delete('recordings', where: 'id = ?', whereArgs: [id]);
  }

  // === Audio Chunks ===

  /// Insert a completed chunk.
  Future<void> insertChunk({
    required String id,
    required String recordingId,
    required int sequenceNumber,
    required String filePath,
    required int durationMs,
    required int sizeBytes,
  }) async {
    final db = await RecordingDatabase.database;

    await db.insert(
      'audio_chunks',
      {
        'id': id,
        'recording_id': recordingId,
        'sequence_number': sequenceNumber,
        'file_path': filePath,
        'duration_ms': durationMs,
        'size_bytes': sizeBytes,
        'status': 'recorded',
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all chunks for a recording.
  Future<List<Map<String, dynamic>>> getChunks(String recordingId) async {
    final db = await RecordingDatabase.database;
    return db.query(
      'audio_chunks',
      where: 'recording_id = ?',
      whereArgs: [recordingId],
      orderBy: 'sequence_number ASC',
    );
  }

  // === Photos ===

  /// Insert a captured photo.
  Future<void> insertPhoto({
    required String id,
    required String recordingId,
    required int chunkIndex,
    required String filePath,
    required int timestampMs,
    required int sizeBytes,
  }) async {
    final db = await RecordingDatabase.database;

    await db.insert(
      'photos',
      {
        'id': id,
        'recording_id': recordingId,
        'chunk_index': chunkIndex,
        'file_path': filePath,
        'timestamp_ms': timestampMs,
        'size_bytes': sizeBytes,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all photos for a recording.
  Future<List<Map<String, dynamic>>> getPhotos(String recordingId) async {
    final db = await RecordingDatabase.database;
    return db.query(
      'photos',
      where: 'recording_id = ?',
      whereArgs: [recordingId],
      orderBy: 'timestamp_ms ASC',
    );
  }

  /// Get total storage used by all local audio files (in bytes).
  Future<int> getTotalLocalStorageBytes() async {
    final db = await RecordingDatabase.database;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(size_bytes), 0) as total FROM audio_chunks',
    );
    return (result.first['total'] as int?) ?? 0;
  }

  /// Count recordings by status.
  Future<Map<String, int>> getRecordingCountsByStatus() async {
    final db = await RecordingDatabase.database;
    final results = await db.rawQuery(
      'SELECT status, COUNT(*) as count FROM recordings GROUP BY status',
    );

    final counts = <String, int>{};
    for (final row in results) {
      counts[row['status'] as String] = (row['count'] as int?) ?? 0;
    }
    return counts;
  }
}

/// Notes held on this device for one recording.
class LocalNotes {
  final String notesMarkdown;
  final String? transcriptMarkdown;
  final DateTime? updatedAt;

  const LocalNotes({
    required this.notesMarkdown,
    this.transcriptMarkdown,
    this.updatedAt,
  });

  bool get hasTranscript =>
      transcriptMarkdown != null && transcriptMarkdown!.isNotEmpty;
}
