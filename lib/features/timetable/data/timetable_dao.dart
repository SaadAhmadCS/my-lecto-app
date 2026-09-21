import 'package:uuid/uuid.dart';

import '../../recording/data/local/recording_database.dart';
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
      for (final weekday in weekdays) {
        await txn.insert('timetable_slots', {
          'id': _uuid.v4(),
          'subject_id': subjectId,
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
    await db.update(
      'timetable_slots',
      {
        'subject_id': subjectId,
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

  static String? _clean(String? room) {
    final trimmed = room?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}
