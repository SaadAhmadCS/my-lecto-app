import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../../../subjects/data/lab_subjects.dart';

/// The app's only store. Everything lives on the device.
///
/// There is no backend: subjects, recordings, chunk metadata, notes and
/// transcripts are all here, so the app works with no network and no account.
class RecordingDatabase {
  static Database? _database;
  static const String _dbName = 'lecto_recordings.db';

  /// 2: added `timetable_slots` for class reminders.
  /// 3: subjects gained `lab_of` and `teacher`; lab classes moved into their
  ///    own lab subjects.
  static const int _dbVersion = 3;

  /// Subject used when a recording is started without picking one.
  static const String unsortedSubjectId = 'unsorted';

  static Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: upgrade,
    );
  }

  @visibleForTesting
  static Future<void> upgrade(Database db, int from, int to) async {
    if (from < 2) await _createTimetable(db);
    // sqflite already runs this in a transaction: all of it, or none.
    if (from < 3) {
      await db.execute('ALTER TABLE subjects ADD COLUMN lab_of TEXT');
      await db.execute('ALTER TABLE subjects ADD COLUMN teacher TEXT');
      await LabSubjects.splitTimetableLabs(db);
    }
  }

  /// One weekly class: a subject on a weekday between two times.
  ///
  /// Times are minutes after midnight, local time. `weekday` follows
  /// [DateTime.weekday] (1 = Monday).
  static Future<void> _createTimetable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE timetable_slots (
        id TEXT PRIMARY KEY,
        subject_id TEXT NOT NULL,
        weekday INTEGER NOT NULL,
        start_minute INTEGER NOT NULL,
        end_minute INTEGER NOT NULL,
        room TEXT,
        is_lab INTEGER NOT NULL DEFAULT 0,
        remind INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_timetable_day ON timetable_slots(weekday, start_minute)',
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    // Subjects a lecture can be filed under. A lab is its own subject, with
    // `lab_of` pointing at its theory course.
    await db.execute('''
      CREATE TABLE subjects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        color TEXT NOT NULL DEFAULT '#6366F1',
        lab_of TEXT,
        teacher TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE recordings (
        id TEXT PRIMARY KEY,
        subject_id TEXT NOT NULL,
        title TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'recording',
        audio_format TEXT NOT NULL DEFAULT 'aac',
        chunk_duration_min INTEGER NOT NULL DEFAULT 15,
        total_duration_ms INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        notes_markdown TEXT,
        transcript_markdown TEXT,
        notes_updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE audio_chunks (
        id TEXT PRIMARY KEY,
        recording_id TEXT NOT NULL,
        sequence_number INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        size_bytes INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'recorded',
        created_at TEXT NOT NULL,
        FOREIGN KEY (recording_id) REFERENCES recordings(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE photos (
        id TEXT PRIMARY KEY,
        recording_id TEXT NOT NULL,
        chunk_index INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        timestamp_ms INTEGER NOT NULL,
        size_bytes INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (recording_id) REFERENCES recordings(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_chunks_recording ON audio_chunks(recording_id)',
    );
    await db.execute(
      'CREATE INDEX idx_photos_recording ON photos(recording_id)',
    );
    await db.execute(
      'CREATE INDEX idx_recordings_subject ON recordings(subject_id)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX idx_chunks_unique '
      'ON audio_chunks(recording_id, sequence_number)',
    );

    await _createTimetable(db);
    await _seedUnsorted(db);
  }

  /// Every install starts with somewhere to put a Quick Record.
  static Future<void> _seedUnsorted(DatabaseExecutor db) async {
    final now = DateTime.now().toIso8601String();
    await db.insert('subjects', {
      'id': unsortedSubjectId,
      'name': 'Unsorted',
      'color': '#64748B',
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Delete every row, keeping the schema and the Unsorted subject.
  static Future<void> clearAll() async {
    final db = await database;
    await db.transaction((txn) async {
      for (final table in [
        'photos',
        'audio_chunks',
        'recordings',
        'timetable_slots',
        'subjects',
      ]) {
        await txn.delete(table);
      }
      await _seedUnsorted(txn);
    });
  }

  static Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
