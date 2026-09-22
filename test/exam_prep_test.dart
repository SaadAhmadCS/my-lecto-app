import 'package:flutter_test/flutter_test.dart';
import 'package:my_lecto/core/services/ai_share_service.dart';
import 'package:my_lecto/core/services/notes_parser.dart';
import 'package:my_lecto/features/exam_prep/exam_prep_service.dart';

void main() {
  group('exam hints in notes', () {
    test('an Exam Hints section is read as hints, not quizzes', () {
      final notes = NotesParser.parse('''
## Quizzes & Exams
- 2026-09-29 — Quiz 2 — eigenvalues, 20 minutes
## Exam Hints
- "Diagonalisation will definitely come in the final."
- Students always forget to check that eigenvectors are non-zero.
''');
      expect(notes.quizzes, hasLength(1));
      expect(notes.examHints, [
        '"Diagonalisation will definitely come in the final."',
        'Students always forget to check that eigenvectors are non-zero.',
      ]);
    });

    test('recognises other names for the section', () {
      for (final heading in [
        'Exam Tips',
        'Common mistakes',
        'Hints for the exam',
        'Things to be careful about',
      ]) {
        final notes = NotesParser.parse('$heading\n- a hint');
        expect(notes.examHints, ['a hint'], reason: heading);
      }
    });

    test('"None" is not a hint', () {
      expect(NotesParser.parse('## Exam Hints\n- None').examHints, isEmpty);
    });

    test('the prompt asks for exam hints', () {
      final prompt = AiShareService.buildPrompt(title: 'Lecture');
      expect(prompt, contains(AiShareService.examHintsHeading));
      expect(prompt, contains('mistakes'));
    });
  });

  group('exam prep', () {
    PrepLecture lecture(
      String id,
      String date,
      String notes, {
      String? transcript,
    }) => PrepLecture(
      id: id,
      title: 'Lecture $id',
      recordedAt: DateTime.parse(date),
      notesMarkdown: notes,
      transcript: transcript,
    );

    final lectures = [
      lecture('1', '2026-09-01', '''
## Summary
Vectors.
## Quizzes & Exams
- 2026-09-10 — Quiz 1 — vectors
## Exam Hints
- Norms always come in quiz 1.
'''),
      lecture('2', '2026-09-15', '''
## Summary
Eigenvalues.
## Quizzes & Exams
- 2026-09-29 — Quiz 2 — eigenvalues
- Final exam — everything
## Exam Hints
- He likes "show that" questions.
## Transcript
Today we look at eigenvalues and eigenvectors in some depth, carefully.
''', transcript: null),
      lecture('3', '2026-09-20', ''),
    ];

    test('announced exams: upcoming first, then undated, then past', () {
      final exams = ExamPrepService.announcedExams(
        lectures,
        now: DateTime(2026, 9, 22),
      );
      expect(exams.map((e) => e.title), ['Quiz 2', 'Final exam', 'Quiz 1']);
    });

    test('the quiz before Quiz 2 is Quiz 1', () {
      final exams = ExamPrepService.announcedExams(
        lectures,
        now: DateTime(2026, 9, 22),
      );
      expect(ExamPrepService.previousExam(exams, exams.first)?.title, 'Quiz 1');
    });

    test('the pack puts every hint first, with where it came from', () {
      final pack = ExamPrepService.buildPack(
        course: 'Linear Algebra',
        exam: PrepExam(title: 'Quiz 2', date: DateTime(2026, 9, 29)),
        lectures: lectures.take(2).toList(),
        includeTranscripts: true,
        teacher: 'Dr. Khan',
      );
      final hints = pack.indexOf('Everything the teacher said about exams');
      final firstLecture = pack.indexOf('# Lecture 1');
      expect(hints, greaterThan(-1));
      expect(hints, lessThan(firstLecture));
      expect(pack, contains('- Norms always come in quiz 1. (2026-09-01'));
      expect(pack, contains('Teacher: Dr. Khan'));
      expect(pack, contains('Exam: Quiz 2 on 2026-09-29'));
      // The transcript inside the notes is moved under its own heading.
      expect(pack, contains("Transcript — the teacher's own words"));
    });

    test('transcripts are left out when asked', () {
      final pack = ExamPrepService.buildPack(
        course: 'Linear Algebra',
        exam: const PrepExam(title: 'Midterm'),
        lectures: lectures.take(2).toList(),
        includeTranscripts: false,
      );
      expect(pack, isNot(contains('in some depth')));
      expect(pack, contains('Eigenvalues.'));
    });

    test('a lecture without notes is not counted as having them', () {
      expect(lectures[2].hasNotes, isFalse);
      expect(lectures[1].examHintCount, 1);
    });

    test('the prompt names the exam, the teacher and the tasks', () {
      final prompt = ExamPrepService.buildPrompt(
        course: 'Linear Algebra',
        exam: PrepExam(title: 'Quiz 2', date: DateTime(2026, 9, 29)),
        lectureCount: 2,
        includeTranscripts: true,
        teacher: 'Dr. Khan',
      );
      expect(prompt, contains('Quiz 2 on 2026-09-29'));
      expect(prompt, contains('Dr. Khan'));
      expect(prompt, contains('Practice paper'));
      expect(prompt, contains('Traps'));
    });
  });
}
