import 'package:flutter_test/flutter_test.dart';
import 'package:my_lecto/core/services/ai_share_service.dart';
import 'package:my_lecto/core/services/notes_parser.dart';

/// Guards against invented assignments and exams: every announcement must
/// point to where it was said, so the student can listen and check.
void main() {
  group('times in the recording', () {
    test('reads the time off the end of a line', () {
      expect(
        NotesParser.splitTime('Quiz next week — "chapter 5 only" — [1:02:15]'),
        (
          'Quiz next week — "chapter 5 only"',
          const Duration(hours: 1, minutes: 2, seconds: 15),
        ),
      );
      expect(
        NotesParser.splitTime('Bring a calculator (42:10)'),
        ('Bring a calculator', const Duration(minutes: 42, seconds: 10)),
      );
      expect(
        NotesParser.splitTime('Resume the cluster [at 0:05:03]').$2,
        const Duration(minutes: 5, seconds: 3),
      );
    });

    test('a line with no time is left as it is', () {
      expect(NotesParser.splitTime('No time here'), ('No time here', null));
      // A ratio or score is not a time.
      expect(NotesParser.splitTime('Split 50/50 at 3:2 odds').$2, isNull);
    });

    test('assignments, quizzes and tasks carry their time', () {
      final notes = NotesParser.parse('''
## Assignments
- [ ] Lab report 3 — due 2026-10-01 — "submit on the LMS" — [1:58:40]
## Quizzes & Exams
- 2026-10-06 — Quiz 2 — "decision trees only" — [0:03:12]
## Tasks
- [ ] Try the entropy calculator — [0:40:00]
''');
      final a = notes.assignments.single;
      expect(a.text, 'Lab report 3');
      expect(a.due, DateTime(2026, 10, 1));
      expect(a.details, '"submit on the LMS"');
      expect(a.at, const Duration(hours: 1, minutes: 58, seconds: 40));

      final q = notes.quizzes.single;
      expect(q.title, 'Quiz 2');
      expect(q.at, const Duration(minutes: 3, seconds: 12));

      expect(notes.tasks.single.text, 'Try the entropy calculator');
      expect(notes.tasks.single.at, const Duration(minutes: 40));
    });

    test('an assignment with no time has none, to be flagged', () {
      // What Gemini invented for the database lab.
      final notes = NotesParser.parse('''
Assignments
 * [x] Lab Report — due 2026-09-29 — submit via campus portal, individual format.
Quizzes & Exams
 * 2026-10-15 — Midterm Exam — Covers all database aggregation concepts.
''');
      expect(notes.assignments.single.at, isNull);
      expect(notes.quizzes.single.at, isNull);
    });
  });

  group('pasted notes', () {
    test('start with every box unticked', () {
      const reply = '''
Tasks
 * [x] Connect to the cluster
 - [X] Write the query
Assignments
 * [x] Lab Report — due 2026-09-29
''';
      final notes = NotesParser.parse(NotesParser.untickAll(reply));
      expect(notes.tasks.every((t) => !t.done), isTrue);
      expect(notes.assignments.single.done, isFalse);
    });

    test('lines about the prompt file are dropped', () {
      final notes = NotesParser.parse('''
## Tasks
- [ ] Practice entropy by hand
- [ ] Review the lecto_prompt.txt reference file
## Important
- Review the prompt file before class
- The quiz is closed book
''');
      expect(notes.tasks.map((t) => t.text), ['Practice entropy by hand']);
      expect(notes.important, ['The quiz is closed book']);
    });

    test('"Topic:" is dropped from study guide headings', () {
      final notes = NotesParser.parse('''
Study Guide
Topic: Hunt's Algorithm and the Greedy Approach
Trees are built recursively.
''');
      expect(
        notes.studyGuide,
        contains("### Hunt's Algorithm and the Greedy Approach"),
      );
    });
  });

  group('prompt', () {
    final prompt = AiShareService.buildPrompt(
      title: 'L',
      duration: const Duration(hours: 2),
    );

    test('asks for the time of every announcement', () {
      expect(prompt, contains('[0:42:10]'));
      expect(prompt, contains('If you cannot point to the moment'));
    });

    test('forbids inventing assignments and exams', () {
      expect(prompt, contains('Most lectures announce no assignment'));
      expect(prompt, contains('never make up a date'));
      expect(prompt, isNot(contains('If you are unsure whether it is graded')));
    });

    test('forbids padding the study guide', () {
      expect(prompt, contains('Never pad'));
    });

    test('asks for the whole recording', () {
      expect(prompt, contains('WHOLE recording'));
    });
  });
}
