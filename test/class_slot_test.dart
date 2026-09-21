import 'package:flutter_test/flutter_test.dart';
import 'package:my_lecto/features/timetable/data/class_slot.dart';

/// Monday 8:30–10:00, like the first Linear Algebra class.
const _monday830 = ClassSlot(
  id: 's1',
  subjectId: 'la',
  subjectName: 'Linear Algebra',
  weekday: DateTime.monday,
  startMinute: 8 * 60 + 30,
  endMinute: 10 * 60,
);

// 21 Sep 2026 is a Monday.
DateTime _mon(int hour, int minute) => DateTime(2026, 9, 21, hour, minute);

void main() {
  group('ClassSlot.isOnAt', () {
    test('is on during the class', () {
      expect(_monday830.isOnAt(_mon(8, 30)), isTrue);
      expect(_monday830.isOnAt(_mon(9, 15)), isTrue);
      expect(_monday830.isOnAt(_mon(9, 59)), isTrue);
    });

    test('counts the 15 minutes before it starts', () {
      expect(_monday830.isOnAt(_mon(8, 15)), isTrue);
      expect(_monday830.isOnAt(_mon(8, 14)), isFalse);
    });

    test('is over once it ends', () {
      expect(_monday830.isOnAt(_mon(10, 0)), isFalse);
    });

    test('only on its own weekday', () {
      // Tuesday, same time.
      expect(_monday830.isOnAt(DateTime(2026, 9, 22, 9)), isFalse);
    });

    test('the early window can be switched off', () {
      expect(
        _monday830.isOnAt(_mon(8, 20), earlyBy: Duration.zero),
        isFalse,
      );
    });
  });

  test('a lab is named as one', () {
    const lab = ClassSlot(
      id: 's2',
      subjectId: 'arch',
      subjectName: 'Intro to Computer Architecture',
      weekday: DateTime.tuesday,
      startMinute: 9 * 60,
      endMinute: 10 * 60 + 30,
      isLab: true,
    );
    expect(lab.displayName, 'Intro to Computer Architecture (Lab)');
    expect(_monday830.displayName, 'Linear Algebra');
  });

  test('length and end time come from the minutes', () {
    expect(_monday830.length, const Duration(minutes: 90));
    expect(_monday830.endOn(_mon(0, 0)), _mon(10, 0));
  });
}
