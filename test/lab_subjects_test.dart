import 'package:flutter_test/flutter_test.dart';
import 'package:my_lecto/features/recording/data/local/recording_database.dart';
import 'package:my_lecto/features/subjects/data/lab_subjects.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  group('names', () {
    test('a lab folder is the course name plus Lab', () {
      expect(
        LabSubjects.labName('Computer Architecture'),
        'Computer Architecture Lab',
      );
    });

    test('recognises names that are already labs', () {
      expect(LabSubjects.soundsLikeLab('Physics Lab'), isTrue);
      expect(LabSubjects.soundsLikeLab('Computer Architecture (Lab)'), isTrue);
      expect(LabSubjects.soundsLikeLab('Chemistry Practical'), isTrue);
      expect(LabSubjects.soundsLikeLab('Linear Algebra'), isFalse);
      // A word containing "lab" is not a lab.
      expect(LabSubjects.soundsLikeLab('Syllabus Design'), isFalse);
    });

    test('strips the lab suffix to find the course', () {
      expect(
        LabSubjects.withoutLab('Computer Architecture Lab'),
        'Computer Architecture',
      );
      expect(
        LabSubjects.withoutLab('Computer Architecture (Lab)'),
        'Computer Architecture',
      );
      expect(
        LabSubjects.withoutLab('Database Systems - Lab'),
        'Database Systems',
      );
      expect(LabSubjects.withoutLab('Lab'), 'Lab');
    });
  });

  group('upgrading a version 2 database', () {
    late Database db;

    /// The version 2 schema with a timetable like a real student's: one
    /// course with lectures and two labs, one with a lab only, one without.
    Future<void> seedV2(Database db) async {
      await db.execute('''
        CREATE TABLE subjects (
          id TEXT PRIMARY KEY, name TEXT NOT NULL,
          color TEXT NOT NULL DEFAULT '#6366F1',
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL)
      ''');
      await db.execute('''
        CREATE TABLE recordings (
          id TEXT PRIMARY KEY, subject_id TEXT NOT NULL, title TEXT NOT NULL)
      ''');
      await db.execute('''
        CREATE TABLE timetable_slots (
          id TEXT PRIMARY KEY, subject_id TEXT NOT NULL,
          weekday INTEGER NOT NULL, start_minute INTEGER NOT NULL,
          end_minute INTEGER NOT NULL, room TEXT,
          is_lab INTEGER NOT NULL DEFAULT 0,
          remind INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL)
      ''');
      const now = '2026-09-22T00:00:00';
      for (final (id, name, color) in [
        ('arch', 'Computer Architecture', '#F16743'),
        ('ml', 'Machine Learning', '#22C55E'),
        ('la', 'Linear Algebra', '#6366F1'),
        ('bio', 'Biology Lab', '#0EA5E9'),
      ]) {
        await db.insert('subjects', {
          'id': id,
          'name': name,
          'color': color,
          'created_at': now,
          'updated_at': now,
        });
      }
      var n = 0;
      for (final (subject, isLab) in [
        ('arch', false),
        ('arch', true),
        ('arch', true),
        ('ml', true),
        ('la', false),
        ('bio', true),
      ]) {
        await db.insert('timetable_slots', {
          'id': 'slot${n++}',
          'subject_id': subject,
          'weekday': 1 + n % 5,
          'start_minute': 480,
          'end_minute': 570,
          'is_lab': isLab ? 1 : 0,
          'created_at': now,
        });
      }
      await db.insert('recordings', {
        'id': 'r1',
        'subject_id': 'arch',
        'title': 'Pipelining',
      });
    }

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await seedV2(db);
      await RecordingDatabase.upgrade(db, 2, 3);
    });

    tearDown(() => db.close());

    Future<Map<String, Object?>> subject(String id) async =>
        (await db.query('subjects', where: 'id = ?', whereArgs: [id])).single;

    Future<String> slotSubject(String id) async =>
        (await db.query(
              'timetable_slots',
              where: 'id = ?',
              whereArgs: [id],
            )).single['subject_id']
            as String;

    test('each course with labs gets one lab folder', () async {
      final labs = await db.query('subjects', where: 'lab_of IS NOT NULL');
      expect(
        {for (final l in labs) l['lab_of']: l['name']},
        {'arch': 'Computer Architecture Lab', 'ml': 'Machine Learning Lab'},
      );
    });

    test('the lab keeps the course colour', () async {
      final lab = (await db.query(
        'subjects',
        where: 'lab_of = ?',
        whereArgs: ['arch'],
      )).single;
      expect(lab['color'], '#F16743');
    });

    test('lab classes move into the lab; lectures stay', () async {
      final archLab = (await db.query(
        'subjects',
        where: 'lab_of = ?',
        whereArgs: ['arch'],
      )).single['id'];
      expect(await slotSubject('slot0'), 'arch');
      expect(await slotSubject('slot1'), archLab);
      expect(await slotSubject('slot2'), archLab);
      expect(await slotSubject('slot4'), 'la');
    });

    test('a subject already named as a lab is left alone', () async {
      expect(await slotSubject('slot5'), 'bio');
      expect(
        await db.query('subjects', where: "name LIKE 'Biology Lab %'"),
        isEmpty,
      );
    });

    test('recordings are not moved', () async {
      final r = (await db.query('recordings')).single;
      expect(r['subject_id'], 'arch');
    });

    test('teacher starts empty', () async {
      expect((await subject('arch'))['teacher'], isNull);
    });

    test('running the split again changes nothing', () async {
      final before = await db.query('subjects');
      await LabSubjects.splitTimetableLabs(db);
      expect(await db.query('subjects'), before);
    });
  });

  group('filing a class', () {
    late Database db;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('''
        CREATE TABLE subjects (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, color TEXT NOT NULL,
          lab_of TEXT, teacher TEXT,
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL)
      ''');
      await db.insert('subjects', {
        'id': 'db',
        'name': 'Database Systems',
        'color': '#000000',
        'created_at': '',
        'updated_at': '',
      });
    });

    tearDown(() => db.close());

    test('a lab of a course goes to its lab, created once', () async {
      final first = await LabSubjects.subjectForClass(db, 'db', isLab: true);
      final second = await LabSubjects.subjectForClass(db, 'db', isLab: true);
      expect(first, isNot('db'));
      expect(second, first);
      expect(await db.query('subjects'), hasLength(2));
    });

    test('a lecture picked from the lab goes to the course', () async {
      final lab = await LabSubjects.labFor(db, 'db');
      expect(await LabSubjects.subjectForClass(db, lab, isLab: false), 'db');
    });

    test('Unsorted never gets a lab', () async {
      expect(
        await LabSubjects.labFor(db, RecordingDatabase.unsortedSubjectId),
        RecordingDatabase.unsortedSubjectId,
      );
    });
  });
}
