import 'package:flutter_test/flutter_test.dart';
import 'package:my_lecto/features/timetable/services/timetable_import.dart';

int _t(int hour, int minute) => hour * 60 + minute;

void main() {
  group('TimetableImport.sameCourse', () {
    bool same(String a, String b) => TimetableImport.sameCourse(a, b);

    test('matches abbreviations either way round', () {
      expect(
        same('Intro to Cyber Security', 'Introduction to Cyber Security'),
        isTrue,
      );
      expect(
        same('Introduction to Computer Architecture', 'Intro to Computer Arch'),
        isTrue,
      );
      expect(same('Adv Database Sys', 'Advanced Database Systems'), isTrue);
      expect(
        same('Machine Learn. Funda.', 'Machine Learning Fundamentals'),
        isTrue,
      );
    });

    test('ignores case, punctuation and filler words', () {
      expect(same('Theory of Automata', 'theory automata'), isTrue);
      expect(same('Linear Algebra', 'LINEAR ALGEBRA'), isTrue);
    });

    test('different courses stay different', () {
      expect(
        same('Intro to Cyber Security', 'Intro to Computer Architecture'),
        isFalse,
      );
      expect(same('Physics', 'Physics Lab Methods'), isFalse);
      expect(same('Database Systems', 'Distributed Systems'), isFalse);
    });

    test('course numbers must match exactly', () {
      expect(same('Calculus I', 'Calculus II'), isFalse);
      expect(same('Calculus II', 'Calculus II'), isTrue);
      expect(same('Physics 101', 'Physics 102'), isFalse);
    });
  });

  group('TimetableImport.parse', () {
    test('reads the format the prompt asks for', () {
      final parse = TimetableImport.parse('''
Monday | 08:30 | 10:00 | Linear Algebra | G-09 | class
Tuesday | 13:30 | 16:30 | Advanced Database Systems | Lab-4 | lab
''');

      expect(parse.classes, hasLength(2));
      final first = parse.classes.first;
      expect(first.weekday, DateTime.monday);
      expect(first.startMinute, _t(8, 30));
      expect(first.endMinute, _t(10, 0));
      expect(first.subject, 'Linear Algebra');
      expect(first.room, 'G-09');
      expect(first.isLab, isFalse);
      expect(parse.classes.last.isLab, isTrue);
      expect(parse.skipped, 0);
    });

    test('ignores chatter around the lines', () {
      final parse = TimetableImport.parse('''
Here is your timetable:

Friday | 15:00 | 16:30 | Theory of Automata | F-05 | class

Let me know if you need anything else!
''');
      expect(parse.classes, hasLength(1));
      expect(parse.skipped, 0);
    });

    test('reads a markdown table, header and rule included', () {
      final parse = TimetableImport.parse('''
| Day | Start | End | Course | Room | Type |
|-----|-------|-----|--------|------|------|
| Wednesday | 08:30 | 10:30 | Advanced Database Systems | F-11 | class |
| Wednesday | 11:00 | 13:00 | Intro to Computer Architecture | G-01 | class |
''');
      expect(parse.classes, hasLength(2));
      expect(parse.classes.first.room, 'F-11');
      expect(parse.skipped, 0);
    });

    test('reads bulleted, numbered and bolded lines', () {
      final parse = TimetableImport.parse('''
- Monday | 08:30 | 10:00 | Linear Algebra | G-09 | class
2. **Tuesday** | 11:00 | 13:00 | Machine Learning Fundamentals | B-19 | class
• `Friday | 08:30 | 11:30 | Intro to Cyber Security | Lab-2 | lab`
''');
      expect(parse.classes.map((c) => c.subject), [
        'Linear Algebra',
        'Machine Learning Fundamentals',
        'Intro to Cyber Security',
      ]);
    });

    test('takes "(Lab)" out of the name and marks it a lab', () {
      final parse = TimetableImport.parse(
        'Tue | 09:00 | 10:30 | Intro to Computer Architecture (Lab) | 504 | class',
      );
      expect(parse.classes.single.subject, 'Intro to Computer Architecture');
      expect(parse.classes.single.isLab, isTrue);
    });

    test('accepts short day names', () {
      final days = TimetableImport.parse('''
Mon | 08:30 | 09:00 | A | - | class
Tues | 08:30 | 09:00 | B | - | class
We | 08:30 | 09:00 | C | - | class
Thurs | 08:30 | 09:00 | D | - | class
fri | 08:30 | 09:00 | E | - | class
''').classes.map((c) => c.weekday);
      expect(days, [1, 2, 3, 4, 5]);
    });

    test('reads 12-hour times', () {
      final parse = TimetableImport.parse(
        'Monday | 1:30 PM | 3:00 pm | Linear Algebra | G-11 | class',
      );
      expect(parse.classes.single.startMinute, _t(13, 30));
      expect(parse.classes.single.endMinute, _t(15, 0));
    });

    test('reads bare 12-hour times as a school day', () {
      // "1:30 | 3:00" with no AM/PM is the afternoon, not the small hours.
      final afternoon = TimetableImport.parse(
        'Monday | 1:30 | 3:00 | Linear Algebra | G-11 | class',
      ).classes.single;
      expect(afternoon.startMinute, _t(13, 30));
      expect(afternoon.endMinute, _t(15, 0));

      // "11:00 | 1:00" runs over noon.
      final overNoon = TimetableImport.parse(
        'Monday | 11:00 | 1:00 | Intro to Cyber Security | G-08 | class',
      ).classes.single;
      expect(overNoon.endMinute, _t(13, 0));
    });

    test('reads a time range written in one field', () {
      final parse = TimetableImport.parse(
        'Monday | 08:30 - 10:00 | Linear Algebra | G-09 | class',
      );
      expect(parse.classes.single.startMinute, _t(8, 30));
      expect(parse.classes.single.endMinute, _t(10, 0));
      expect(parse.classes.single.subject, 'Linear Algebra');
    });

    test('a missing room is no room', () {
      final rooms = TimetableImport.parse('''
Monday | 08:30 | 10:00 | A | - | class
Monday | 10:00 | 11:00 | B | N/A | class
Monday | 11:00 | 12:00 | C
''').classes.map((c) => c.room);
      expect(rooms, [null, null, null]);
    });

    test('counts lines it could not read, but not headers', () {
      final parse = TimetableImport.parse('''
Day | Start | End | Course | Room | Type
Monday | 10:00 | 09:00 | Backwards | G-01 | class
Someday | 08:30 | 10:00 | Nowhen | G-02 | class
Monday | 08:30 | 10:00 | Linear Algebra | G-09 | class
''');
      expect(parse.classes, hasLength(1));
      expect(parse.skipped, 2);
    });

    test('drops exact repeats and sorts by day and time', () {
      final parse = TimetableImport.parse('''
Wednesday | 11:00 | 13:00 | Intro to Computer Architecture | G-01 | class
Monday | 08:30 | 10:00 | Linear Algebra | G-09 | class
Monday | 08:30 | 10:00 | linear algebra | G-09 | class
''');
      expect(parse.classes.map((c) => c.weekday), [1, 3]);
    });

    test('lists each course once, whatever its capitalisation', () {
      final parse = TimetableImport.parse('''
Monday | 08:30 | 10:00 | Linear Algebra | G-09 | class
Monday | 13:30 | 15:00 | linear algebra | G-11 | class
Tuesday | 11:00 | 13:00 | Machine Learning Fundamentals | B-19 | class
''');
      expect(parse.subjects, [
        'Linear Algebra',
        'Machine Learning Fundamentals',
      ]);
    });

    test('reads the BCS-6A timetable end to end', () {
      // What an AI should return for the real BCS-6A screenshot, with the
      // slips they make: a lead-in line, a "(Lab)" left in, an abbreviation.
      final parse = TimetableImport.parse('''
Sure! Here is your timetable:

Monday | 08:30 | 10:00 | Linear Algebra | G-09 | class
Monday | 11:00 | 13:00 | Intro to Cyber Security | G-08 | class
Monday | 13:30 | 15:00 | Linear Algebra | G-11 | class
Monday | 15:00 | 16:30 | Theory of Automata | F-02 | class
Tuesday | 09:00 | 10:30 | Intro to Computer Architecture (Lab) | 504 | lab
Tuesday | 11:00 | 13:00 | Machine Learning Fundamentals | B-19 | class
Tuesday | 13:30 | 16:30 | Advanced Database Systems | Lab-4 | lab
Wednesday | 08:30 | 10:30 | Advanced Database Systems | F-11 | class
Wednesday | 11:00 | 13:00 | Intro to Computer Architecture | G-01 | class
Wednesday | 13:30 | 16:30 | Machine Learning Fundamentals | Lab-9 | lab
Friday | 08:30 | 11:30 | Intro to Cyber Security | Lab-2 | lab
Friday | 11:30 | 13:00 | Intro to Computer Architecture | Lab-9 | lab
Friday | 15:00 | 16:30 | Theory of Automata | F-05 | class
''');

      expect(parse.classes, hasLength(13));
      expect(parse.skipped, 0);
      expect(parse.subjects, hasLength(6));
      expect(parse.classes.where((c) => c.isLab), hasLength(5));
      expect(
        parse.classes.where((c) => c.weekday == DateTime.thursday),
        isEmpty,
      );
      final lab = parse.classes.firstWhere(
        (c) => c.weekday == DateTime.tuesday,
      );
      expect(lab.subject, 'Intro to Computer Architecture');
      expect(lab.room, '504');
    });

    test('one course however it is abbreviated', () {
      final parse = TimetableImport.parse('''
Monday | 08:30 | 10:00 | Machine Learning Fundamentals | B-19 | class
Wednesday | 13:30 | 16:30 | Machine Learn. Funda. | Lab-9 | lab
''');
      expect(parse.subjects, ['Machine Learning Fundamentals']);
    });

    test('nothing usable is empty', () {
      final parse = TimetableImport.parse(
        "I'm sorry, I can't read that image clearly.",
      );
      expect(parse.isEmpty, isTrue);
      expect(parse.skipped, 0);
    });
  });
}
