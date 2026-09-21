/// One item the students were asked to do.
class NoteTask {
  final String text;
  final bool done;

  /// Line index in the source markdown, so a tap can rewrite the right line.
  final int lineIndex;

  const NoteTask({
    required this.text,
    required this.done,
    required this.lineIndex,
  });
}

/// A dated commitment pulled out of the notes.
class NoteDeadline {
  final DateTime? date;
  final String rawDate;
  final String description;

  const NoteDeadline({
    required this.rawDate,
    required this.description,
    this.date,
  });
}

/// A section the parser recognised the shape of but not the meaning.
///
/// Anything the AI wrote under a heading Lecto does not know lands here rather
/// than being dropped, so the student never loses part of their notes.
class NoteSection {
  final String title;
  final String body;

  const NoteSection({required this.title, required this.body});
}

/// A lecture's notes broken into the parts Lecto renders separately.
class ParsedNotes {
  final String? summary;
  final List<String> concepts;
  final List<NoteTask> tasks;
  final List<NoteDeadline> deadlines;
  final String? transcript;

  /// Content under headings Lecto does not recognise, in the order written.
  final List<NoteSection> extraSections;
  final String rawMarkdown;

  const ParsedNotes({
    required this.rawMarkdown,
    this.summary,
    this.concepts = const [],
    this.tasks = const [],
    this.deadlines = const [],
    this.transcript,
    this.extraSections = const [],
  });

  /// True when the reply had recognisable structure worth rendering as UI.
  ///
  /// An untitled section is just loose prose, so it does not count — a reply
  /// that is one paragraph still renders as plain markdown.
  bool get isStructured =>
      summary != null ||
      concepts.isNotEmpty ||
      tasks.isNotEmpty ||
      deadlines.isNotEmpty ||
      extraSections.any((section) => section.title.isNotEmpty);

  bool get hasTranscript => transcript != null && transcript!.trim().isNotEmpty;
}

/// Turns an AI reply into [ParsedNotes].
///
/// Built against what the apps actually produce, not what the prompt asks for.
/// Copying a reply out of the Gemini or Claude app strips markdown, so headings
/// arrive as bare lines — "Summary" rather than "## Summary" — and bullets as
/// " * " rather than "- ". Matching is therefore done on normalised text and
/// accepts headings with or without markers, with emoji, numbering or trailing
/// colons, and with reasonable synonyms.
class NotesParser {
  /// A heading written with markdown markers (`##` or `**bold**`).
  static final RegExp _markdownHeading = RegExp(
    r'^\s{0,3}(?:#{1,6}\s+(.+?)|\*\*(.+?)\*\*)\s*:?\s*$',
  );
  static final RegExp _task = RegExp(r'^\s*[-*+]\s*\[( |x|X)\]\s*(.+)$');
  static final RegExp _bullet = RegExp(r'^\s*[-*+]\s+(.+)$');
  static final RegExp _leadingDate = RegExp(
    r'^\s*[-*+]?\s*(\d{4}-\d{2}-\d{2}|\d{1,2}[/-]\d{1,2}[/-]\d{2,4})\s*(?:[—–\-:]\s*)?(.*)$',
  );

  /// Longest a bare line can be and still be treated as a heading.
  static const _maxHeadingChars = 60;
  static const _maxHeadingWords = 6;

  static ParsedNotes parse(String markdown) {
    final lines = markdown.split('\n');

    final summaryLines = <String>[];
    final concepts = <String>[];
    final tasks = <NoteTask>[];
    final deadlines = <NoteDeadline>[];
    final transcriptLines = <String>[];
    final extraSections = <NoteSection>[];

    var section = _Section.none;
    var extraTitle = '';
    final extraBody = <String>[];

    void flushExtra() {
      final body = extraBody.join('\n').trim();
      if (body.isNotEmpty || extraTitle.isNotEmpty) {
        extraSections.add(NoteSection(title: extraTitle, body: body));
      }
      extraTitle = '';
      extraBody.clear();
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final heading = _headingOf(line);

      if (heading != null) {
        if (section == _Section.other) flushExtra();
        final next = _sectionFor(_normalize(heading));
        if (next == _Section.none) {
          // Unknown heading: keep it verbatim rather than losing what follows.
          section = _Section.other;
          extraTitle = heading.trim();
        } else {
          section = next;
        }
        continue;
      }

      switch (section) {
        case _Section.summary:
          if (line.trim().isNotEmpty) summaryLines.add(line.trim());
        case _Section.concepts:
          final bullet = _bullet.firstMatch(line);
          if (bullet != null) {
            concepts.add(bullet.group(1)!.trim());
          } else if (line.trim().isNotEmpty) {
            // Some apps drop the bullet marker entirely.
            concepts.add(line.trim());
          }
        case _Section.tasks:
          final task = _task.firstMatch(line);
          if (task != null) {
            tasks.add(
              NoteTask(
                text: task.group(2)!.trim(),
                done: task.group(1)!.toLowerCase() == 'x',
                lineIndex: i,
              ),
            );
          }
        case _Section.deadlines:
          if (line.trim().isEmpty) continue;
          final dated = _leadingDate.firstMatch(line);
          if (dated != null && dated.group(2)!.trim().isNotEmpty) {
            deadlines.add(
              NoteDeadline(
                rawDate: dated.group(1)!,
                description: dated.group(2)!.trim(),
                date: DateTime.tryParse(dated.group(1)!),
              ),
            );
          } else {
            final bullet = _bullet.firstMatch(line);
            deadlines.add(
              NoteDeadline(
                rawDate: '',
                description: (bullet?.group(1) ?? line).trim(),
              ),
            );
          }
        case _Section.transcript:
          transcriptLines.add(line);
        case _Section.other:
          extraBody.add(line);
        case _Section.none:
          // Text before any heading — keep it as an untitled section.
          if (line.trim().isNotEmpty) extraBody.add(line);
      }
    }

    if (section == _Section.other || extraBody.isNotEmpty) flushExtra();

    // Checklist items sometimes appear with no Tasks heading at all.
    if (tasks.isEmpty) {
      for (var i = 0; i < lines.length; i++) {
        final task = _task.firstMatch(lines[i]);
        if (task != null) {
          tasks.add(
            NoteTask(
              text: task.group(2)!.trim(),
              done: task.group(1)!.toLowerCase() == 'x',
              lineIndex: i,
            ),
          );
        }
      }
    }

    final transcript = transcriptLines.join('\n').trim();

    return ParsedNotes(
      rawMarkdown: markdown,
      summary: summaryLines.isEmpty ? null : summaryLines.join('\n'),
      concepts: concepts,
      tasks: tasks,
      deadlines: deadlines,
      transcript: _isMissingTranscript(transcript) ? null : transcript,
      extraSections: extraSections,
    );
  }

  /// Flip one checklist item and return the rewritten markdown.
  ///
  /// The markdown stays the source of truth, so a toggle survives into PDF
  /// export and search with no extra state to keep in step.
  static String toggleTask(String markdown, NoteTask task) {
    final lines = markdown.split('\n');
    if (task.lineIndex < 0 || task.lineIndex >= lines.length) return markdown;

    final line = lines[task.lineIndex];
    if (_task.firstMatch(line) == null) return markdown;

    lines[task.lineIndex] = line.replaceFirst(
      RegExp(r'\[( |x|X)\]'),
      task.done ? '[ ]' : '[x]',
    );
    return lines.join('\n');
  }

  /// The heading text of [line], or null when it is not a heading.
  ///
  /// Accepts markdown headings anywhere, and bare lines only when they are
  /// short and name a section we know — otherwise ordinary prose would be
  /// mistaken for a heading.
  static String? _headingOf(String line) {
    final markdown = _markdownHeading.firstMatch(line);
    if (markdown != null) {
      return (markdown.group(1) ?? markdown.group(2))?.trim();
    }

    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.length > _maxHeadingChars) return null;
    if (_bullet.hasMatch(trimmed)) return null;
    if (trimmed.endsWith('.')) return null;

    final normalized = _normalize(trimmed);
    if (normalized.isEmpty) return null;
    if (normalized.split(' ').length > _maxHeadingWords) return null;
    if (_sectionFor(normalized) == _Section.none) return null;

    return trimmed;
  }

  /// Strip markdown, numbering, emoji and punctuation for matching.
  static String _normalize(String raw) {
    var value = raw.toLowerCase();
    value = value.replaceAll(RegExp(r'[#*_`~]'), ' ');
    value = value.replaceFirst(RegExp(r'^\s*\d+\s*[.)]\s*'), ' ');
    value = value.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool _isMissingTranscript(String transcript) {
    if (transcript.isEmpty) return true;
    final normalized = transcript.toLowerCase();
    return normalized.length < 80 && normalized.contains('too long');
  }

  /// Match on keywords rather than exact titles, since AI apps rarely use the
  /// exact heading they were asked for.
  static _Section _sectionFor(String name) {
    if (name.isEmpty) return _Section.none;
    bool has(String term) => name.contains(term);

    if (has('transcript')) return _Section.transcript;
    if (has('deadline') ||
        has('due') ||
        has('important date') ||
        name == 'dates') {
      return _Section.deadlines;
    }
    if (has('task') ||
        has('action item') ||
        has('homework') ||
        has('assignment') ||
        has('to do') ||
        has('todo')) {
      return _Section.tasks;
    }
    if (has('concept') ||
        has('definition') ||
        has('key point') ||
        has('important point') ||
        has('main point') ||
        has('key idea') ||
        has('takeaway') ||
        has('topic')) {
      return _Section.concepts;
    }
    if (has('summary') || has('overview') || has('tldr') || has('tl dr')) {
      return _Section.summary;
    }
    return _Section.none;
  }
}

enum _Section { none, summary, concepts, tasks, deadlines, transcript, other }
