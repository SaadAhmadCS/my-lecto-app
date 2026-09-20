import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_lecto/core/services/notes_parser.dart';
import 'package:my_lecto/features/recording/presentation/widgets/paste_notes_sheet.dart';

void main() {
  const structured = '''
Summary
A lecture about databases.
Key Concepts
 * SQL — a query language.
Tasks
 * [ ] Read chapter 4
Deadlines
 * 2026-10-01 — Quiz
''';

  /// Pumps a button that opens the sheet, and records what it returned.
  Future<List<bool>> openSheet(
    WidgetTester tester, {
    required String markdown,
    bool replacesExisting = false,
  }) async {
    final results = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                results.add(await PasteNotesSheet.show(
                  context,
                  notes: NotesParser.parse(markdown),
                  markdownStyle: MarkdownStyleSheet(),
                  replacesExisting: replacesExisting,
                ));
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return results;
  }

  testWidgets('shows what was found before saving', (tester) async {
    await openSheet(tester, markdown: structured);

    expect(find.text('Review notes'), findsOneWidget);
    // The count line is what makes a bad paste obvious at a glance.
    expect(
      find.textContaining('1 concept'),
      findsOneWidget,
      reason: 'should report what the parser found',
    );
    expect(find.textContaining('1 task'), findsOneWidget);
    expect(find.textContaining('1 deadline'), findsOneWidget);
    // Rendered with the same widget the Notes tab uses.
    expect(find.text('Read chapter 4'), findsOneWidget);
  });

  testWidgets('counts read naturally for one and for many', (tester) async {
    await openSheet(tester, markdown: '''
Tasks
 * [ ] One
 * [ ] Two
Deadlines
 * 2026-10-01 — Quiz
''');

    expect(find.textContaining('2 tasks'), findsOneWidget);
    expect(find.textContaining('1 deadline ·'), findsNothing);
    expect(find.textContaining('1 deadline'), findsOneWidget);
  });

  testWidgets('Save notes confirms', (tester) async {
    final results = await openSheet(tester, markdown: structured);

    await tester.tap(find.text('Save notes'));
    await tester.pumpAndSettle();

    expect(results, [true]);
  });

  testWidgets('Discard does not confirm', (tester) async {
    final results = await openSheet(tester, markdown: structured);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(results, [false]);
  });

  testWidgets('dismissing without choosing does not confirm', (tester) async {
    // Tapping the scrim must not be read as approval.
    final results = await openSheet(tester, markdown: structured);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(results, [false]);
  });

  testWidgets('warns when the paste is not notes', (tester) async {
    await openSheet(tester, markdown: 'https://example.com/some-link-i-copied');

    expect(
      find.textContaining('does not look like lecture notes'),
      findsOneWidget,
    );
  });

  testWidgets('warns when it would replace existing notes', (tester) async {
    await openSheet(
      tester,
      markdown: structured,
      replacesExisting: true,
    );

    expect(find.textContaining('replaces the notes already here'), findsOneWidget);
  });

  testWidgets('no replace warning for a first paste', (tester) async {
    await openSheet(tester, markdown: structured);

    expect(find.textContaining('replaces the notes already here'), findsNothing);
  });

  testWidgets('tasks are not tickable before saving', (tester) async {
    // Ticking a box in the preview would be lost when the markdown is stored.
    await openSheet(tester, markdown: structured);

    final tile = tester.widget<InkWell>(
      find.ancestor(
        of: find.text('Read chapter 4'),
        matching: find.byType(InkWell),
      ),
    );
    expect(tile.onTap, isNull);
  });
}
