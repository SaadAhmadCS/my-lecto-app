import 'package:flutter_test/flutter_test.dart';
import 'package:my_lecto/core/services/ai_share_service.dart';
import 'package:my_lecto/core/services/notes_parser.dart';

void main() {
  group('study guide', () {
    test('keeps markdown topic headings inside the notes', () {
      final notes = NotesParser.parse('''
## Summary
Decision trees.
## Tasks
- [ ] Read chapter 4
## Lecture Notes
### Decision trees
A tree works like if-then-else.
- Root node: where the first split happens.
### Entropy
Entropy measures impurity.
H = -Σ p log2 p, where p is the share of each class.
## Key Concepts
- **Entropy** — impurity of a node.
''');
      expect(notes.studyGuide, contains('### Decision trees'));
      expect(notes.studyGuide, contains('### Entropy'));
      expect(notes.studyGuide, contains('H = -Σ p log2 p'));
      // The topics did not leak out as sections of their own.
      expect(notes.extraSections, isEmpty);
      expect(notes.concepts, hasLength(1));
      expect(notes.tasks, hasLength(1));
    });

    test('restores topic headings Gemini stripped to bare lines', () {
      // How today's Gemini reply arrived: no # marks, " * " bullets.
      final notes = NotesParser.parse('''
Summary
Decision trees and splitting criteria.
Lecture Notes
Decision Trees
A decision tree works like an if-then-else structure in programming.
 * The root node is where the first split happens.
Entropy
Entropy measures the impurity of a node.
H = -Σ p log2 p
Hunt's Algorithm
It builds the tree recursively.
Key Concepts
 * Entropy — impurity of a node.
''');
      final body = notes.studyGuide!;
      expect(body, contains('### Decision Trees'));
      expect(body, contains('### Entropy'));
      expect(body, contains("### Hunt's Algorithm"));
      // A formula is never mistaken for a heading.
      expect(body, isNot(contains('### H =')));
      expect(body, contains(' * The root node'));
      expect(notes.concepts, hasLength(1));
    });

    test('a sentence is not turned into a heading', () {
      final notes = NotesParser.parse('''
## Lecture Notes
### Pipelines
The output of one stage is the input of the next.
Each stage filters or reshapes documents.
''');
      expect(notes.studyGuide, isNot(contains('### The output')));
      expect(notes.studyGuide, isNot(contains('### Each stage')));
    });

    test('reads the section by its new name', () {
      final notes = NotesParser.parse(
        'Study Guide\nTrees\nA tree splits data.',
      );
      expect(notes.studyGuide, contains('### Trees'));
    });

    test('a study guide alone counts as structured notes', () {
      final notes = NotesParser.parse('## Lecture Notes\n### A\nText here.');
      expect(notes.isStructured, isTrue);
    });
  });

  group('prompt', () {
    test('asks for a detailed study guide sized to the lecture', () {
      final prompt = AiShareService.buildPrompt(
        title: 'Decision trees',
        duration: const Duration(hours: 2),
      );
      expect(prompt, contains(AiShareService.studyGuideHeading));
      expect(prompt, contains('about 3600 words'));
      expect(prompt, contains('Do not summarise'));
    });

    test('tasks are only for after class', () {
      final prompt = AiShareService.buildPrompt(title: 'Lab');
      expect(prompt, contains('AFTER class'));
      expect(prompt, contains('Exercises done during the class are not tasks'));
    });

    test('keeps personal details and file names out', () {
      final prompt = AiShareService.buildPrompt(title: 'Lab');
      expect(prompt, contains('roll number'));
      expect(prompt, contains('any file name'));
    });

    test('the study guide comes before key concepts', () {
      final prompt = AiShareService.buildPrompt(title: 'Lecture');
      expect(
        prompt.indexOf(AiShareService.studyGuideHeading),
        lessThan(prompt.indexOf(AiShareService.conceptsHeading)),
      );
    });
  });
}
