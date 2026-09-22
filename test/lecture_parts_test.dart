import 'package:flutter_test/flutter_test.dart';
import 'package:my_lecto/core/services/ai_share_service.dart';

/// A long lecture goes over in parts: an AI app given two hours skims it and
/// invents the rest.
void main() {
  List<({String path, Duration length})> chunks(int count, {int minutes = 15}) => [
    for (var i = 0; i < count; i++)
      (path: 'chunk_$i.m4a', length: Duration(minutes: minutes)),
  ];

  group('when to split', () {
    test('a short lecture goes in one', () {
      expect(AiShareService.needsParts(const Duration(minutes: 50)), isFalse);
      expect(AiShareService.needsParts(null), isFalse);
    });

    test('a long one is split', () {
      expect(AiShareService.needsParts(const Duration(hours: 2)), isTrue);
    });
  });

  group('planning the parts', () {
    test('groups chunks into parts of about 45 minutes', () {
      // Today's database lab: 2h 20m in ten chunks.
      final parts = AiShareService.planParts([
        ...chunks(9),
        (path: 'chunk_9.m4a', length: const Duration(minutes: 5)),
      ]);

      expect(parts, hasLength(3));
      expect(parts.first.start, Duration.zero);
      expect(parts.first.end, const Duration(minutes: 45));
      expect(parts.first.chunkPaths, hasLength(3));
      expect(parts.last.end, const Duration(hours: 2, minutes: 20));
      // Every chunk is in exactly one part, in order.
      expect(
        [for (final p in parts) ...p.chunkPaths],
        [for (var i = 0; i < 10; i++) 'chunk_$i.m4a'],
      );
    });

    test('parts run end to end with no gap', () {
      final parts = AiShareService.planParts(chunks(8));
      for (var i = 1; i < parts.length; i++) {
        expect(parts[i].start, parts[i - 1].end);
      }
    });

    test('a short tail joins the part before it', () {
      // 45 + 5 minutes: two parts would leave a five-minute one.
      final parts = AiShareService.planParts([
        ...chunks(3),
        (path: 'tail.m4a', length: const Duration(minutes: 5)),
      ]);
      expect(parts, hasLength(1));
      expect(parts.single.chunkPaths, contains('tail.m4a'));
    });

    test('numbers the parts', () {
      final parts = AiShareService.planParts(chunks(9));
      expect([for (final p in parts) p.label], [
        'Part 1 of 3',
        'Part 2 of 3',
        'Part 3 of 3',
      ]);
      expect(parts[1].range, '45:00–1:30:00');
    });

    test('no audio, no parts', () {
      expect(AiShareService.planParts(const []), isEmpty);
    });
  });

  group('a part\'s prompt', () {
    final parts = AiShareService.planParts(chunks(9));
    final prompt = AiShareService.buildPrompt(
      title: 'MongoDB aggregation',
      duration: const Duration(hours: 2, minutes: 15),
      part: parts[1],
    );

    test('says which part it is and what it covers', () {
      expect(prompt, contains('Part 2 of 3'));
      expect(prompt, contains('45:00–1:30:00'));
      expect(prompt, contains('do not guess at what came before or after'));
    });

    test('asks for times in the whole lecture', () {
      expect(prompt, contains('this part starts at 45:00'));
    });

    test('a whole lecture still asks for the whole recording', () {
      final whole = AiShareService.buildPrompt(title: 'L');
      expect(whole, contains('WHOLE recording'));
      expect(whole, isNot(contains('Part 1 of')));
    });
  });
}
