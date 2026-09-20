import 'package:flutter_test/flutter_test.dart';
import 'package:my_lecto/features/recording/presentation/widgets/transcript_search.dart';

void main() {
  const transcript = '''
# Thermodynamics

> Transcribed by Lecto AI

<!-- Chunk 1 | ~15 min -->

## Entropy
The **second law** says entropy never decreases.

- Entropy is disorder
- ENTROPY has units J/K

---
''';

  test('strips markdown into readable paragraphs', () {
    final index = TranscriptSearchIndex(transcript);

    expect(index.paragraphs, [
      'Thermodynamics',
      'Transcribed by Lecto AI',
      'Entropy\nThe second law says entropy never decreases.',
      '• Entropy is disorder\n• ENTROPY has units J/K',
    ]);
  });

  test('finds case-insensitive matches in reading order', () {
    final index = TranscriptSearchIndex(transcript);
    final matches = index.findMatches('entropy');

    expect(matches.length, 4);
    expect(matches.map((m) => m.paragraph), [2, 2, 3, 3]);

    // Offsets point at the text actually displayed
    for (final m in matches) {
      final text = index.paragraphs[m.paragraph];
      expect(text.substring(m.start, m.start + m.length).toLowerCase(), 'entropy');
    }
  });

  test('empty or whitespace query has no matches', () {
    final index = TranscriptSearchIndex(transcript);
    expect(index.findMatches(''), isEmpty);
    expect(index.findMatches('   '), isEmpty);
  });
}
