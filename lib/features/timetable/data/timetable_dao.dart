import 'package:uuid/uuid.dart';

import '../../recording/data/local/recording_database.dart';
import '../../subjects/data/lab_subjects.dart';
import '../services/timetable_import.dart';
import 'class_slot.dart';

/// The weekly timetable, stored on the device.
class TimetableDao {
  static const _uuid = Uuid();

  static const _select = '''
    SELECT t.*, s.name AS subject_name, s.color AS subject_color
    FROM timetable_slots t
    JOIN subjects s ON s.id = t.subject_id
  ''';

  /// Every class, Monday first, in time order within a day.
  Future<List<ClassSlot>> list() async {
    final db = await RecordingDatabase.database;
    final rows = await db.rawQuery(
      '$_select ORDER BY t.weekday, t.start_minute',
    );
    return rows.map(ClassSlot.fromRow).toList();
  }

  Future<ClassSlot?> get(String id) async {
    final db = await RecordingDatabase.database;
    final rows = await db.rawQuery('$_select WHERE t.id = ?', [id]);
    return rows.isEmpty ? null : ClassSlot.fromRow(rows.first);
  }

  /// The class on right now (or about to start), if any.
  ///
  /// When classes overlap, the one that started most recently wins.
  Future<ClassSlot?> activeAt(DateTime now) async {
    final slots = (await list()).where((slot) => slot.isOnAt(now)).toList()
      ..sort((a, b) => b.startMinute.compareTo(a.startMinute));
    return slots.isEmpty ? null : slots.first;
  }

  /// Add the same class on each of [weekdays].
  ///
  /// A lab goes into the course's lab folder, whichever half was picked.
  Future<void> add({
    required String subjectId,
    required Iterable<int> weekdays,
    required int startMinute,
    required int endMinute,
    String? room,
    bool isLab = false,
    bool remind = true,
  }) async {
    final db = await RecordingDatabase.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final subject = await LabSubjects.subjectForClass(
        txn,
        subjectId,
        isLab: isLab,
      );
      for (final weekday in weekdays) {
        await txn.insert('timetable_slots', {
          'id': _uuid.v4(),
          'subject_id': subject,
          'weekday': weekday,
          'start_minute': startMinute,
          'end_minute': endMinute,
          'room': _clean(room),
          'is_lab': isLab ? 1 : 0,
          'remind': remind ? 1 : 0,
          'created_at': now,
        });
      }
    });
  }

  Future<void> update({
    required String id,
    required String subjectId,
    required int weekday,
    required int startMinute,
    required int endMinute,
    String? room,
    required bool isLab,
    required bool remind,
  }) async {
    final db = await RecordingDatabase.database;
    final subject = await LabSubjects.subjectForClass(
      db,
      subjectId,
      isLab: isLab,
    );
    await db.update(
      'timetable_slots',
      {
        'subject_id': subject,
        'weekday': weekday,
        'start_minute': startMinute,
        'end_minute': endMinute,
        'room': _clean(room),
        'is_lab': isLab ? 1 : 0,
        'remind': remind ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> setRemind(String id, bool remind) async {
    final db = await RecordingDatabase.database;
    await db.update(
      'timetable_slots',
      {'remind': remind ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async {
    final db = await RecordingDatabase.database;
    await db.delete('timetable_slots', where: 'id = ?', whereArgs: [id]);
  }

  /// Save a whole imported timetable at once.
  ///
  /// Each class goes into the subject it names — matched the way people
  /// abbreviate (see [TimetableImport.sameCourse]), so "Intro to Computer
  /// Arch" finds "Introduction to Computer Architecture" — and missing
  /// subjects are created, coloured from [palette] with colours already in
  /// use skipped first. With [replace], the current timetable is cleared
  /// first. All or nothing.
  ///
  /// Returns how many subjects were created.
  Future<int> importClasses(
    List<ImportedClass> classes, {
    required bool replace,
    required List<String> palette,
  }) async {
    final db = await RecordingDatabase.database;
    final now = DateTime.now().toIso8601String();

    return db.transaction((txn) async {
      final subjects = await txn.query(
        'subjects',
        columns: ['id', 'name', 'color'],
      );
      // (name, id) of every subject, growing as new ones are created.
      final known = [
        for (final s in subjects) (s['name'] as String, s['id'] as String),
      ];
      final used = subjects
          .map((s) => (s['color'] as String).toLowerCase())
          .toSet();
      final colors = [
        ...palette.where((c) => !used.contains(c.toLowerCase())),
        ...palette,
      ];

      if (replace) await txn.delete('timetable_slots');

      var created = 0;
      for (final c in classes) {
        // "Computer Architecture Lab" is the lab of "Computer Architecture".
        final isLab = c.isLab || LabSubjects.soundsLikeLab(c.subject);
        final name = isLab ? LabSubjects.withoutLab(c.subject) : c.subject;
        var subjectId = _match(known, name);
        if (subjectId == null) {
          subjectId = _uuid.v4();
          await txn.insert('subjects', {
            'id': subjectId,
            'name': name,
            'color': colors[created % colors.length],
            'created_at': now,
            'updated_at': now,
          });
          known.add((name, subjectId));
          created++;
        }
        final filedUnder = await LabSubjects.subjectForClass(
          txn,
          subjectId,
          isLab: isLab,
        );

        await txn.insert('timetable_slots', {
          'id': _uuid.v4(),
          'subject_id': filedUnder,
          'weekday': c.weekday,
          'start_minute': c.startMinute,
          'end_minute': c.endMinute,
          'room': _clean(c.room),
          'is_lab': isLab ? 1 : 0,
          'remind': 1,
          'created_at': now,
        });
      }
      return created;
    });
  }

  static String? _match(List<(String, String)> known, String name) {
    for (final (existing, id) in known) {
      if (TimetableImport.sameCourse(existing, name)) return id;
    }
    return null;
  }

  static String? _clean(String? room) {
    final trimmed = room?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}
