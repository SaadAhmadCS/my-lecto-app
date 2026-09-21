import 'package:flutter_test/flutter_test.dart';
import 'package:my_lecto/features/home/data/home_digest.dart';

UpcomingItem _item(String title, {int? daysFromNow, UpcomingKind? kind}) {
  final now = DateTime.now();
  return UpcomingItem(
    title: title,
    rawDate: 'whenever',
    kind: kind ?? UpcomingKind.from(title),
    recordingId: 'r1',
    recordingTitle: 'Lecture',
    date: daysFromNow == null
        ? null
        : DateTime(now.year, now.month, now.day).add(Duration(days: daysFromNow)),
  );
}

HomeTask _task(String text, {bool done = false, int? dueInDays}) {
  final now = DateTime.now();
  return HomeTask(
    text: text,
    done: done,
    recordingId: 'r1',
    recordingTitle: 'Lecture',
    dueAt: dueInDays == null
        ? null
        : DateTime(now.year, now.month, now.day).add(Duration(days: dueInDays)),
  );
}

void main() {
  group('UpcomingKind.from', () {
    test('reads a quiz', () {
      expect(UpcomingKind.from('Quiz on chapter 4'), UpcomingKind.quiz);
      expect(UpcomingKind.from('Midterm exam'), UpcomingKind.quiz);
      expect(UpcomingKind.from('Viva next week'), UpcomingKind.quiz);
    });

    test('reads an assignment', () {
      expect(UpcomingKind.from('Lab report 3'), UpcomingKind.assignment);
      expect(UpcomingKind.from('Problem set 2'), UpcomingKind.assignment);
      expect(UpcomingKind.from('Essay submission'), UpcomingKind.assignment);
    });

    test('falls back when nothing matches', () {
      expect(UpcomingKind.from('Bring your lab coat'), UpcomingKind.assignment);
      expect(UpcomingKind.from('Guest speaker visiting'), UpcomingKind.other);
    });

    test('matches whole words only', () {
      // "syllabus" contains "lab", "latest" contains "test".
      expect(UpcomingKind.from('Syllabus posted online'), UpcomingKind.other);
      expect(UpcomingKind.from('Read the latest chapter'), UpcomingKind.other);
      expect(UpcomingKind.from('Finalize your group'), UpcomingKind.other);
    });

    test('a final project is a project, a final exam is an exam', () {
      expect(UpcomingKind.from('Final project due'), UpcomingKind.assignment);
      expect(UpcomingKind.from('Final exam'), UpcomingKind.quiz);
      expect(UpcomingKind.from('Finals start Monday'), UpcomingKind.quiz);
      expect(UpcomingKind.from('Term paper'), UpcomingKind.quiz);
    });
  });

  group('HomeDigest', () {
    test('counts only open tasks', () {
      final digest = HomeDigest(tasks: [
        _task('a'),
        _task('b', done: true),
        _task('c'),
      ]);
      expect(digest.openTaskCount, 2);
    });

    test('orders open tasks soonest first, undated last, done at the end', () {
      final digest = HomeDigest(tasks: [
        _task('undated'),
        _task('later', dueInDays: 5),
        _task('finished', done: true),
        _task('sooner', dueInDays: 1),
      ]);
      expect(
        digest.todayTasks.map((task) => task.text),
        ['sooner', 'later', 'undated', 'finished'],
      );
    });

    test('drops items that have already passed', () {
      final digest = HomeDigest(upcoming: [
        _item('Quiz 1', daysFromNow: -3),
        _item('Quiz 2', daysFromNow: 2),
      ]);
      expect(digest.futureItems.map((item) => item.title), ['Quiz 2']);
    });

    test('keeps undated items but sorts them last', () {
      final digest = HomeDigest(upcoming: [
        _item('No date given'),
        _item('Quiz soon', daysFromNow: 1),
      ]);
      expect(
        digest.futureItems.map((item) => item.title),
        ['Quiz soon', 'No date given'],
      );
    });

    test('quizzesThisWeek counts quizzes within seven days only', () {
      final digest = HomeDigest(upcoming: [
        _item('Quiz tomorrow', daysFromNow: 1),
        _item('Quiz in a fortnight', daysFromNow: 14),
        _item('Lab report', daysFromNow: 2),
        _item('Quiz that passed', daysFromNow: -1),
        _item('Quiz with no date'),
      ]);
      expect(digest.quizzesThisWeek, 1);
    });
  });

  group('UpcomingItem.daysAway', () {
    test('is null without a date', () {
      expect(_item('x').daysAway, isNull);
    });

    test('counts whole days, negative once passed', () {
      expect(_item('x', daysFromNow: 0).daysAway, 0);
      expect(_item('x', daysFromNow: 3).daysAway, 3);
      expect(_item('x', daysFromNow: -2).daysAway, -2);
    });
  });
}
