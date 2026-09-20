import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// One occurrence of the search query inside a paragraph.
class TranscriptMatch {
  final int paragraph;
  final int start;
  final int length;

  const TranscriptMatch(this.paragraph, this.start, this.length);
}

/// Plain-text paragraphs of a Markdown transcript, for in-transcript search.
///
/// Markdown syntax is stripped so match offsets line up with the text shown
/// in [SearchableTranscriptView].
class TranscriptSearchIndex {
  final List<String> paragraphs;

  TranscriptSearchIndex(String markdown) : paragraphs = _toParagraphs(markdown);

  /// Case-insensitive matches in reading order.
  List<TranscriptMatch> findMatches(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];

    final matches = <TranscriptMatch>[];
    for (var p = 0; p < paragraphs.length; p++) {
      final haystack = paragraphs[p].toLowerCase();
      var index = haystack.indexOf(needle);
      while (index != -1) {
        matches.add(TranscriptMatch(p, index, needle.length));
        index = haystack.indexOf(needle, index + needle.length);
      }
    }
    return matches;
  }

  static List<String> _toParagraphs(String markdown) {
    final withoutComments = markdown.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
    return withoutComments
        .split(RegExp(r'\n\s*\n'))
        .map((block) => block
            .split('\n')
            .map(_cleanLine)
            .where((line) => line.isNotEmpty)
            .join('\n'))
        .where((paragraph) => paragraph.isNotEmpty && paragraph != '---')
        .toList();
  }

  static String _cleanLine(String line) {
    return line
        .trim()
        .replaceFirst(RegExp(r'^#{1,6}\s+'), '')
        .replaceFirst(RegExp(r'^>\s?'), '')
        .replaceFirst(RegExp(r'^[-*]\s+'), '• ')
        .replaceAll(RegExp(r'\*\*|__|`'), '');
  }
}

/// Transcript rendered as plain paragraphs with search matches highlighted.
class SearchableTranscriptView extends StatelessWidget {
  final TranscriptSearchIndex index;
  final List<TranscriptMatch> matches;
  final int currentMatch;

  /// One key per paragraph, used to scroll the current match into view.
  final List<GlobalKey> paragraphKeys;

  const SearchableTranscriptView({
    super.key,
    required this.index,
    required this.matches,
    required this.currentMatch,
    required this.paragraphKeys,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: AppColors.textPrimaryDark,
          height: 1.6,
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var p = 0; p < index.paragraphs.length; p++)
            Padding(
              key: paragraphKeys[p],
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: SelectableText.rich(
                TextSpan(style: baseStyle, children: _spansFor(p)),
              ),
            ),
        ],
      ),
    );
  }

  List<TextSpan> _spansFor(int paragraph) {
    final text = index.paragraphs[paragraph];
    final spans = <TextSpan>[];
    var cursor = 0;

    for (var i = 0; i < matches.length; i++) {
      final match = matches[i];
      if (match.paragraph != paragraph) continue;

      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final isCurrent = i == currentMatch;
      spans.add(TextSpan(
        text: text.substring(match.start, match.start + match.length),
        style: TextStyle(
          backgroundColor: isCurrent
              ? AppColors.primary
              : AppColors.warning.withValues(alpha: 0.35),
          color: isCurrent ? Colors.white : null,
          fontWeight: FontWeight.w600,
        ),
      ));
      cursor = match.start + match.length;
    }

    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return spans;
  }
}
