import 'package:flutter_test/flutter_test.dart';
import 'package:my_lecto/core/constants/transcription_language.dart';
import 'package:my_lecto/core/services/ai_share_service.dart';
import 'package:my_lecto/core/services/notes_parser.dart';

void main() {
  group('buildPrompt', () {
    test('names the lecture, subject and date', () {
      final prompt = AiShareService.buildPrompt(
        title: 'Thermodynamics 101',
        subjectName: 'Physics',
        recordingDate: DateTime(2026, 9, 19),
        duration: const Duration(hours: 1, minutes: 25),
      );

      expect(prompt, contains('Thermodynamics 101'));
      expect(prompt, contains('Physics'));
      expect(prompt, contains('2026-09-19'));
      expect(prompt, contains('1 hr 25 min'));
    });

    test('gives the recording date so relative dates can be resolved', () {
      final prompt = AiShareService.buildPrompt(
        title: 'Lecture',
        recordingDate: DateTime(2026, 9, 19),
      );

      expect(prompt, contains('next Tuesday'));
    });

    test('works with no subject, date or duration', () {
      final prompt = AiShareService.buildPrompt(title: 'Untitled');

      expect(prompt, contains('Untitled'));
      expect(prompt, isNot(contains('null')));
    });

    test('requests exactly the headings the parser looks for', () {
      final prompt = AiShareService.buildPrompt(title: 'Lecture');

      for (final heading in [
        AiShareService.summaryHeading,
        AiShareService.conceptsHeading,
        AiShareService.tasksHeading,
        AiShareService.deadlinesHeading,
        AiShareService.assignmentsHeading,
        AiShareService.quizzesHeading,
        AiShareService.importantHeading,
      ]) {
        expect(prompt, contains(heading), reason: 'missing $heading');
      }
    });

    test('a reply following the prompt parses into every section', () {
      // Guards the contract between the prompt and NotesParser: the headings
      // the prompt asks for must be the ones the parser recognises.
      final prompt = AiShareService.buildPrompt(title: 'Lecture');
      final headings = RegExp(
        r'^## .+$',
        multiLine: true,
      ).allMatches(prompt).map((m) => m.group(0)!).toList();

      final reply = StringBuffer();
      for (final heading in headings) {
        reply.writeln(heading);
        if (heading == AiShareService.tasksHeading) {
          reply.writeln('- [ ] Do the reading');
        } else if (heading == AiShareService.assignmentsHeading) {
          reply.writeln('- [ ] Lab report 3 — due 2026-10-01 — submit on LMS');
        } else if (heading == AiShareService.quizzesHeading) {
          reply.writeln('- 2026-09-28 — Quiz 2 — chapter 5, 20 minutes');
        } else if (heading == AiShareService.importantHeading) {
          reply.writeln('- Section B will be on the final.');
        } else if (heading == AiShareService.deadlinesHeading) {
          reply.writeln('- 2026-10-01 — Essay due');
        } else if (heading == AiShareService.conceptsHeading) {
          reply.writeln('- **Entropy** — disorder in a system.');
        } else {
          reply.writeln('Some text.');
        }
        reply.writeln();
      }

      final parsed = NotesParser.parse(reply.toString());
      expect(parsed.isStructured, isTrue);
      expect(parsed.summary, isNotNull);
      expect(parsed.concepts, hasLength(1));
      expect(parsed.tasks, hasLength(1));
      expect(parsed.assignments.single.text, 'Lab report 3');
      expect(parsed.assignments.single.due, DateTime(2026, 10, 1));
      expect(parsed.quizzes.single.title, 'Quiz 2');
      expect(parsed.important, hasLength(1));
      expect(parsed.deadlines, hasLength(1));
      expect(parsed.examHints, hasLength(1));
      expect(parsed.studyGuide, isNotNull);
      // No transcript is asked for any more.
      expect(parsed.hasTranscript, isFalse);
    });
  });

  group('language', () {
    test('auto-detect says nothing, leaving it to the AI', () {
      // A lecture that switches language mid-sentence is handled better by
      // the model than by a setting.
      final prompt = AiShareService.buildPrompt(title: 'L');

      expect(prompt.toLowerCase(), isNot(contains('the lecture is in')));
    });

    test('a chosen language is stated in the prompt', () {
      final english = AiShareService.buildPrompt(
        title: 'L',
        language: TranscriptionLanguage.english,
      );
      expect(english, contains('in English'));

      final urdu = AiShareService.buildPrompt(
        title: 'L',
        language: TranscriptionLanguage.urdu,
      );
      expect(urdu, contains('Roman Urdu'));
      // Technical terms reading better in English is the whole point of
      // asking for Roman Urdu rather than Urdu script.
      expect(urdu, contains('technical terms in English'));
    });

    test('every language either states itself or deliberately does not', () {
      for (final language in TranscriptionLanguage.values) {
        final line = language.promptLine;
        if (language == TranscriptionLanguage.auto) {
          expect(line, isNull, reason: 'auto should stay silent');
        } else {
          expect(line, isNotNull, reason: '${language.label} needs a prompt');
        }
      }
    });
  });

  test('never asks for a transcript, whatever the length', () {
    // A transcript takes the room the study guide needs.
    for (final duration in [
      null,
      const Duration(minutes: 12),
      const Duration(hours: 3),
    ]) {
      final prompt = AiShareService.buildPrompt(title: 'L', duration: duration);
      expect(prompt, contains('Do NOT include a transcript'));
      expect(prompt, isNot(contains(AiShareService.transcriptHeading)));
      expect(prompt, contains(AiShareService.studyGuideHeading));
    }
  });

  test('ChatGPT is not offered as an audio target', () {
    // Verified on device: it registers for PDF and text, never audio.
    expect(AiShareService.audioCapableApps, isNot(contains('ChatGPT')));
    expect(AiShareService.audioCapableApps, contains('Claude'));
  });
}
