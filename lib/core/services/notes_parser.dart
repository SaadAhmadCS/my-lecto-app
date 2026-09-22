/// One item the students were asked to do: a task, or a graded assignment.
class NoteTask {
  /// What to do — for an assignment, its name.
  final String text;
  final bool done;

  /// Line index in the source markdown, so a tap can rewrite the right line.
  final int lineIndex;

  /// When it is due, if the lecture said. Assignments usually have one.
  final DateTime? due;

  /// Anything else the lecture said about it: how to submit, marks, format.
  final String? details;

  const NoteTask({
    required this.text,
    required this.done,
    required this.lineIndex,
    this.due,
    this.details,
  });
}

/// A quiz, test or exam the lecture mentioned.
class NoteQuiz {
  final String title;
  final DateTime? date;
  final String rawDate;

  /// What it covers, its format, what is allowed in — whatever was said.
  final String? details;

  const NoteQuiz({
    required this.title,
    required this.rawDate,
    this.date,
    this.details,
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

  /// Ungraded work: reading, practice, things to look into.
  final List<NoteTask> tasks;

  /// Graded work the lecture set.
  final List<NoteTask> assignments;
  final List<NoteQuiz> quizzes;

  /// Announcements, instructions, rule changes — things not to miss.
  final List<String> important;

  /// What the teacher let slip about exams: what will come, the questions
  /// they like, the mistakes students make, what to be careful with.
  final List<String> examHints;

  /// The full study notes, topic by topic, as markdown with a `###` heading
  /// per topic.
  final String? lectureNotes;
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
    this.assignments = const [],
    this.quizzes = const [],
    this.important = const [],
    this.examHints = const [],
    this.lectureNotes,
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
      assignments.isNotEmpty ||
      quizzes.isNotEmpty ||
      important.isNotEmpty ||
      examHints.isNotEmpty ||
      lectureNotes != null ||
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
  static final RegExp _task = RegExp(r'^\s*[-*+•]\s*\[( |x|X)\]\s*(.+)$');
  static final RegExp _bullet = RegExp(r'^\s*[-*+•]\s+(.+)$');
  static final RegExp _leadingDate = RegExp(
    r'^\s*[-*+•]?\s*(\d{4}-\d{2}-\d{2}|\d{1,2}[/-]\d{1,2}[/-]\d{2,4})\s*(?:[—–\-:]\s*)?(.*)$',
  );
  static final RegExp _isoDate = RegExp(r'\d{4}-\d{2}-\d{2}');

  /// " — " between the parts of an item line, as the prompt asks for.
  static final RegExp _separator = RegExp(r'\s+[—–]\s+|\s+-\s+');

  /// Longest a bare line can be and still be treated as a heading.
  static const _maxHeadingChars = 60;
  static const _maxHeadingWords = 6;

  static ParsedNotes parse(String markdown) {
    final lines = markdown.split('\n');

    final summaryLines = <String>[];
    final concepts = <String>[];
    final tasks = <NoteTask>[];
    final assignments = <NoteTask>[];
    final quizzes = <NoteQuiz>[];
    final important = <String>[];
    final examHints = <String>[];
    final lectureNoteLines = <String>[];
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
        // Topic headings inside the lecture notes belong to them. Only a
        // heading naming another section of the reply ends the notes.
        if (section == _Section.lectureNotes &&
            !_endsLectureNotes(_normalize(heading))) {
          lectureNoteLines.add('### ${heading.trim()}');
          continue;
        }
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
          final item = _item(line);
          if (item != null) concepts.add(item);
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
        case _Section.assignments:
          final assignment = _assignment(line, i);
          if (assignment != null) assignments.add(assignment);
        case _Section.quizzes:
          final quiz = _quiz(line);
          if (quiz != null) quizzes.add(quiz);
        case _Section.important:
          final item = _item(line);
          if (item != null) important.add(item);
        case _Section.examHints:
          final item = _item(line);
          if (item != null) examHints.add(item);
        case _Section.lectureNotes:
          lectureNoteLines.add(line);
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

    // Checklist items sometimes appear with no Tasks heading at all. Lines
    // already read as assignments are theirs, not tasks.
    if (tasks.isEmpty) {
      final taken = {for (final a in assignments) a.lineIndex};
      for (var i = 0; i < lines.length; i++) {
        if (taken.contains(i)) continue;
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
    final lectureNotes = _withTopicHeadings(lectureNoteLines).trim();

    return ParsedNotes(
      rawMarkdown: markdown,
      summary: summaryLines.isEmpty ? null : summaryLines.join('\n'),
      concepts: concepts,
      tasks: tasks,
      assignments: assignments,
      quizzes: quizzes,
      important: important,
      examHints: examHints,
      lectureNotes: lectureNotes.isEmpty ? null : lectureNotes,
      deadlines: deadlines,
      transcript: _isMissingTranscript(transcript) ? null : transcript,
      extraSections: extraSections,
    );
  }

  /// A bullet's text, or the whole line when an app dropped the marker.
  static String? _item(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    final bullet = _bullet.firstMatch(line);
    final text = (bullet?.group(1) ?? trimmed).trim();
    // "None" and friends: the AI saying a section is empty.
    return _isNothing(text) ? null : text;
  }

  /// "- [ ] Lab report 3 — due 2026-10-01 — submit on the portal, 10 marks".
  ///
  /// The box is optional: an app that drops it still gives an assignment,
  /// just an unticked one.
  static NoteTask? _assignment(String line, int index) {
    final boxed = _task.firstMatch(line);
    final text = boxed?.group(2)?.trim() ?? _item(line);
    if (text == null || _isNothing(text)) return null;

    final dateMatch = _isoDate.firstMatch(text);
    final parts = text
        .split(_separator)
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;

    // The name is the first part that is not just a date.
    final nameIndex = _isoDate.hasMatch(parts.first) && parts.length > 1
        ? 1
        : 0;
    // A part carrying the due date ("due 2026-10-01") is not a detail.
    final rest = [
      for (var i = 0; i < parts.length; i++)
        if (i != nameIndex && !_isoDate.hasMatch(parts[i])) parts[i],
    ];

    return NoteTask(
      text: parts[nameIndex],
      done: boxed?.group(1)?.toLowerCase() == 'x',
      lineIndex: index,
      due: dateMatch == null ? null : DateTime.tryParse(dateMatch.group(0)!),
      details: rest.isEmpty ? null : rest.join(' · '),
    );
  }

  /// "- 2026-09-28 — Quiz 2 on eigenvalues — covers ch 5, closed book".
  static NoteQuiz? _quiz(String line) {
    final text = _item(line);
    if (text == null) return null;

    final dateMatch = _isoDate.firstMatch(text);
    final parts = text
        .split(_separator)
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;

    final nameIndex = _isoDate.hasMatch(parts.first) && parts.length > 1
        ? 1
        : 0;
    final rest = [
      for (var i = 0; i < parts.length; i++)
        if (i != nameIndex &&
            !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(parts[i]))
          parts[i],
    ];

    return NoteQuiz(
      title: parts[nameIndex],
      rawDate: dateMatch?.group(0) ?? '',
      date: dateMatch == null ? null : DateTime.tryParse(dateMatch.group(0)!),
      details: rest.isEmpty ? null : rest.join(' · '),
    );
  }

  /// Restore topic headings a chat app stripped to bare lines.
  ///
  /// Copying from Gemini turns "### Entropy" into "Entropy". A short line
  /// that reads like a title — no sentence punctuation, no formula, not a
  /// bullet — followed by more text is taken as a topic heading again.
  static String _withTopicHeadings(List<String> lines) {
    final out = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();
      var hasMore = false;
      for (var j = i + 1; j < lines.length; j++) {
        if (lines[j].trim().isNotEmpty) {
          hasMore = true;
          break;
        }
      }
      final looksLikeTitle =
          trimmed.isNotEmpty &&
          trimmed.length <= 70 &&
          hasMore &&
          !trimmed.startsWith('#') &&
          !_bullet.hasMatch(line) &&
          !_task.hasMatch(line) &&
          RegExp(r'^[A-Z0-9]').hasMatch(trimmed) &&
          !RegExp(r'[.,;!?=$`]$').hasMatch(trimmed) &&
          !trimmed.contains('=') &&
          trimmed.split(RegExp(r'\s+')).length <= 10;
      if (looksLikeTitle) {
        // A blank line before the heading keeps markdown from gluing it to
        // the paragraph above.
        if (out.isNotEmpty && out.last.trim().isNotEmpty) out.add('');
        out.add('### ${trimmed.replaceAll(RegExp(r':$'), '')}');
      } else {
        out.add(line);
      }
    }
    return out.join('\n');
  }

  /// The headings of the reply's other sections, which end the lecture
  /// notes. Anything else is a topic inside them.
  static bool _endsLectureNotes(String name) => const {
    'summary',
    'important',
    'exam hints',
    'assignments',
    'quizzes exams',
    'quizzes and exams',
    'quizzes',
    'tasks',
    'key concepts',
    'concepts',
    'glossary',
    'other dates',
    'dates',
    'deadlines',
    'transcript',
    'full transcript',
  }.contains(name);

  static bool _isNothing(String text) {
    final t = text.toLowerCase().replaceAll(RegExp(r'[^a-z ]'), '').trim();
    return const {
      'none',
      'none mentioned',
      'nothing',
      'nothing mentioned',
      'na',
      'not mentioned',
      'no assignments',
      'no quizzes',
      'no hints',
      'no exam hints',
    }.contains(t);
  }

  /// Flip one checklist item and return the rewritten markdown.
  ///
  /// The markdown stays the source of truth, so a toggle survives into PDF
  /// export and search with no extra state to keep in step. A bullet with no
  /// box (an assignment an app stripped the box from) gains one.
  static String toggleTask(String markdown, NoteTask task) {
    final lines = markdown.split('\n');
    if (task.lineIndex < 0 || task.lineIndex >= lines.length) return markdown;

    final line = lines[task.lineIndex];
    if (_task.firstMatch(line) != null) {
      lines[task.lineIndex] = line.replaceFirst(
        RegExp(r'\[( |x|X)\]'),
        task.done ? '[ ]' : '[x]',
      );
    } else if (_bullet.firstMatch(line) != null && !task.done) {
      lines[task.lineIndex] = line.replaceFirstMapped(
        RegExp(r'^(\s*[-*+•]\s+)'),
        (m) => '${m.group(1)}[x] ',
      );
    } else {
      return markdown;
    }
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
  /// exact heading they were asked for. Order matters: "Important dates" is
  /// deadlines, not Important.
  static _Section _sectionFor(String name) {
    if (name.isEmpty) return _Section.none;
    bool has(String term) => name.contains(term);
    bool word(String w) => RegExp('(^| )$w( |\$)').hasMatch(name);

    if (has('transcript')) return _Section.transcript;
    if (has('deadline') ||
        has('due date') ||
        has('important date') ||
        has('other date') ||
        name == 'dates' ||
        word('due')) {
      return _Section.deadlines;
    }
    // Before quizzes: "Exam hints" is advice about exams, not a list of them.
    if (has('hint') ||
        has('exam tip') ||
        has('exam focus') ||
        has('exam prep') ||
        has('mistake') ||
        has('be careful') ||
        has('what to focus') ||
        has('likely question')) {
      return _Section.examHints;
    }
    if (has('assignment') ||
        has('homework') ||
        has('coursework') ||
        has('graded')) {
      return _Section.assignments;
    }
    if (has('quiz') ||
        word('exam') ||
        word('exams') ||
        word('test') ||
        word('tests') ||
        has('midterm') ||
        has('assessment')) {
      return _Section.quizzes;
    }
    // "Important points" are key concepts, not announcements.
    if ((word('important') && !has('important point')) ||
        has('announcement') ||
        has('instruction') ||
        has('don t miss') ||
        has('dont miss') ||
        has('reminder') ||
        has('heads up')) {
      return _Section.important;
    }
    if (has('task') || has('action item') || has('to do') || has('todo')) {
      return _Section.tasks;
    }
    if (has('lecture note') ||
        has('detailed note') ||
        has('study note') ||
        has('class note') ||
        name == 'notes' ||
        has('in depth') ||
        has('detailed explanation')) {
      return _Section.lectureNotes;
    }
    if (has('concept') ||
        has('glossary') ||
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

enum _Section {
  none,
  summary,
  concepts,
  tasks,
  assignments,
  quizzes,
  important,
  examHints,
  lectureNotes,
  deadlines,
  transcript,
  other,
}
