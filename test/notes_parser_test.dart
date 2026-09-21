import 'package:flutter_test/flutter_test.dart';
import 'package:my_lecto/core/services/notes_parser.dart';

void main() {
  const wellFormed = '''
## Summary
Newton's laws of motion, covering inertia and F=ma.

## Key Concepts
- **Inertia** — an object resists changes to its motion.
- **Force** — mass times acceleration.

## Tasks
- [ ] Read chapter 4 before the next class
- [ ] Attempt problems 1 to 10

## Deadlines
- 2026-09-26 — Problem set 3 due
- 2026-10-03 — Midterm exam

## Transcript
Right, so today we are going to talk about Newton's laws.
''';

  group('parse', () {
    test('pulls every section out of a well-formed reply', () {
      final notes = NotesParser.parse(wellFormed);

      expect(notes.isStructured, isTrue);
      expect(notes.summary, contains('Newton'));
      expect(notes.concepts, hasLength(2));
      expect(notes.concepts.first, contains('Inertia'));
      expect(notes.tasks, hasLength(2));
      expect(notes.tasks.every((t) => !t.done), isTrue);
      expect(notes.deadlines, hasLength(2));
      expect(notes.deadlines.first.date, DateTime(2026, 9, 26));
      expect(notes.deadlines.first.description, 'Problem set 3 due');
      expect(notes.hasTranscript, isTrue);
    });

    test('accepts heading synonyms and different heading levels', () {
      final notes = NotesParser.parse('''
# Overview
A lecture about databases.

### Action Items
- [x] Install Postgres

**Due Dates**
- 2026-11-01 — Project proposal
''');

      expect(notes.summary, contains('databases'));
      expect(notes.tasks.single.done, isTrue);
      expect(notes.deadlines.single.description, 'Project proposal');
    });

    test('finds checklist items even with no Tasks heading', () {
      final notes = NotesParser.parse('''
## Summary
Short lecture.

- [ ] Revise slide deck
''');

      expect(notes.tasks.single.text, 'Revise slide deck');
    });

    test('treats an unstructured reply as plain markdown', () {
      final notes = NotesParser.parse(
        'Here are some thoughts about the lecture with no headings at all.',
      );

      expect(notes.isStructured, isFalse);
      expect(notes.rawMarkdown, contains('no headings'));
    });

    test('ignores a transcript the AI declined to produce', () {
      final notes = NotesParser.parse('''
## Summary
A long lecture.

## Transcript
(too long to transcribe)
''');

      expect(notes.hasTranscript, isFalse);
    });

    test('keeps a deadline that has no parseable date', () {
      final notes = NotesParser.parse('''
## Deadlines
- End of term — portfolio submission
''');

      expect(notes.deadlines.single.date, isNull);
      expect(notes.deadlines.single.description, contains('portfolio'));
    });
  });

  group('a real Gemini reply', () {
    // Verbatim from the Gemini Android app on 2026-09-19. Copying a reply out
    // of the app strips markdown: headings arrive as bare lines and bullets as
    // " * ". An earlier parser only matched "##" headings, so every section
    // except Tasks came back empty.
    const geminiReply = '''
Summary
Based on the guidelines provided, this is a summary of the computer science advanced database lecture. The session focused on basic SQL commands and preparation for MongoDB.
Key Concepts
 * SQL commands — basic database instructions that will appear in the upcoming paper.
 * MongoDB — a database system that students are required to install before the next class.
Tasks
 * [ ] Study basic SQL commands for the upcoming quiz and paper.
 * [ ] Install MongoDB before the next class.
 * [ ] Open your PC during the current class to test all basic SQL commands.
Deadlines
 * 2026-09-26 — Quiz on basic SQL commands during the next week's class.
Transcript
Hey hello, this is your computer science advanced database lecture.
''';

    test('every section is recovered despite the missing markdown', () {
      final notes = NotesParser.parse(geminiReply);

      expect(notes.summary, contains('advanced database lecture'));
      expect(notes.concepts, hasLength(2));
      expect(notes.concepts.first, contains('SQL commands'));
      expect(notes.tasks, hasLength(3));
      expect(notes.deadlines, hasLength(1));
      expect(notes.deadlines.single.date, DateTime(2026, 9, 26));
      expect(notes.hasTranscript, isTrue);
    });

    test('its tasks still toggle', () {
      final notes = NotesParser.parse(geminiReply);
      final updated = NotesParser.toggleTask(geminiReply, notes.tasks[1]);
      final reparsed = NotesParser.parse(updated);

      expect(reparsed.tasks[1].done, isTrue);
      expect(reparsed.tasks[0].done, isFalse);
      expect(reparsed.concepts, hasLength(2));
    });
  });

  group('never loses content', () {
    test('keeps sections under headings it does not recognise', () {
      final notes = NotesParser.parse('''
## Summary
A lecture.

## Further Reading
- Revise the second half of the syllabus.
''');

      expect(notes.summary, contains('lecture'));
      expect(notes.extraSections, hasLength(1));
      expect(notes.extraSections.single.title, 'Further Reading');
      expect(notes.extraSections.single.body, contains('second half'));
    });

    test('keeps text written before any heading', () {
      final notes = NotesParser.parse('''
Here are your notes for today.

## Summary
A lecture.
''');

      expect(notes.extraSections.single.body, contains('notes for today'));
      expect(notes.summary, contains('lecture'));
    });

    test('a heading-like sentence is not mistaken for a heading', () {
      final notes = NotesParser.parse(
        'The summary of this lecture is that databases are useful.',
      );

      expect(notes.summary, isNull);
      expect(notes.extraSections.single.body, contains('databases are useful'));
    });
  });

  group('heading synonyms seen in the wild', () {
    test('matches on keywords, not exact titles', () {
      final notes = NotesParser.parse('''
Key Concepts & Definitions
 * Entropy — disorder.
Action Items
 * [ ] Read chapter 2
Important Dates
 * 2026-12-01 — Final exam
''');

      expect(notes.concepts, hasLength(1));
      expect(notes.tasks, hasLength(1));
      expect(notes.deadlines, hasLength(1));
    });

    test('tolerates numbering, emoji and trailing colons', () {
      final notes = NotesParser.parse('''
## 1. Summary:
It was a lecture.
### 📌 Key Takeaways
- Something important
''');

      expect(notes.summary, contains('lecture'));
      expect(notes.concepts, hasLength(1));
    });
  });

  group('assignments, quizzes and important', () {
    // As a reply to the new prompt looks once an app has stripped markdown.
    const reply = '''
Summary
Pipelining and hazards.
Important
 * Section B of the syllabus will definitely be on the final.
 * Lab moves to Room 504 from next week.
Assignments
 * [ ] Lab report 2 — due 2026-09-26 — submit on the LMS as a PDF — 10 marks
 * Pipeline simulator project — groups of 3
Quizzes & Exams
 * 2026-09-24 — Quiz 1 — pipelining basics — 20 minutes, closed book
 * Midterm — everything up to caches
Tasks
 * [ ] Read chapter 4.5
Key Concepts
 * Forwarding — passing a result straight to the next stage.
Other Dates
 * 2026-10-10 — Guest lecture
''';

    test('reads each section into its own list', () {
      final notes = NotesParser.parse(reply);

      expect(notes.important, hasLength(2));
      expect(notes.important.first, contains('Section B'));

      expect(notes.assignments, hasLength(2));
      final report = notes.assignments.first;
      expect(report.text, 'Lab report 2');
      expect(report.due, DateTime(2026, 9, 26));
      expect(report.details, 'submit on the LMS as a PDF · 10 marks');
      expect(report.done, isFalse);
      // No box and no date: still an assignment.
      expect(notes.assignments.last.text, 'Pipeline simulator project');
      expect(notes.assignments.last.due, isNull);

      expect(notes.quizzes, hasLength(2));
      expect(notes.quizzes.first.title, 'Quiz 1');
      expect(notes.quizzes.first.date, DateTime(2026, 9, 24));
      expect(notes.quizzes.first.details, contains('closed book'));
      expect(notes.quizzes.last.title, 'Midterm');
      expect(notes.quizzes.last.date, isNull);

      expect(notes.tasks.single.text, 'Read chapter 4.5');
      expect(notes.concepts, hasLength(1));
      expect(notes.deadlines.single.description, 'Guest lecture');
    });

    test('assignment checkboxes are not also read as tasks', () {
      final notes = NotesParser.parse('''
## Assignments
- [ ] Essay — due 2026-10-01
''');
      expect(notes.assignments, hasLength(1));
      expect(notes.tasks, isEmpty);
    });

    test('an assignment with no box can still be ticked', () {
      final notes = NotesParser.parse(reply);
      final project = notes.assignments.last;
      final updated = NotesParser.toggleTask(reply, project);
      final reparsed = NotesParser.parse(updated);

      expect(reparsed.assignments.last.done, isTrue);
      expect(reparsed.assignments.last.text, 'Pipeline simulator project');
      expect(reparsed.assignments.first.done, isFalse);
    });

    test('"None" is an empty section, not an item', () {
      final notes = NotesParser.parse('''
## Assignments
- None
## Quizzes & Exams
None mentioned.
## Important
- Nothing
''');
      expect(notes.assignments, isEmpty);
      expect(notes.quizzes, isEmpty);
      expect(notes.important, isEmpty);
    });

    test('heading synonyms land in the right place', () {
      final notes = NotesParser.parse('''
Homework
 * [ ] Problem set 4 — due 2026-10-02
Upcoming Tests
 * 2026-10-05 — Unit test 2
Announcements
 * No class on Friday.
Important Points
 * Entropy — disorder.
''');
      expect(notes.assignments, hasLength(1));
      expect(notes.quizzes, hasLength(1));
      expect(notes.important.single, 'No class on Friday.');
      expect(notes.concepts, hasLength(1));
    });
  });

  group('toggleTask', () {
    test('ticks an unticked item and leaves the rest alone', () {
      final notes = NotesParser.parse(wellFormed);
      final updated = NotesParser.toggleTask(wellFormed, notes.tasks.first);
      final reparsed = NotesParser.parse(updated);

      expect(reparsed.tasks.first.done, isTrue);
      expect(reparsed.tasks.last.done, isFalse);
      expect(reparsed.summary, contains('Newton'));
      expect(reparsed.deadlines, hasLength(2));
    });

    test('unticks a ticked item', () {
      const markdown = '## Tasks\n- [x] Already done';
      final notes = NotesParser.parse(markdown);
      final updated = NotesParser.toggleTask(markdown, notes.tasks.single);

      expect(NotesParser.parse(updated).tasks.single.done, isFalse);
    });

    test('survives a stale line index', () {
      final notes = NotesParser.parse(wellFormed);
      final updated = NotesParser.toggleTask('## Tasks\n', notes.tasks.first);

      expect(updated, '## Tasks\n');
    });
  });
}
