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

  /// Where in the recording it was said, so the student can listen and check.
  final Duration? at;

  const NoteTask({
    required this.text,
    required this.done,
    required this.lineIndex,
    this.due,
    this.details,
    this.at,
  });
}

/// A quiz, test or exam the lecture mentioned.
class NoteQuiz {
  final String title;
  final DateTime? date;
  final String rawDate;

  /// What it covers, its format, what is allowed in — whatever was said.
  final String? details;

  /// Where in the recording it was announced.
  final Duration? at;

  const NoteQuiz({
    required this.title,
    required this.rawDate,
    this.date,
    this.details,
    this.at,
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

  /// The study guide: everything taught, topic by topic, as markdown with a
  /// `###` heading per topic.
  final String? studyGuide;
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
    this.studyGuide,
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
      studyGuide != null ||
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
    final studyGuideLines = <String>[];
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
        if (section == _Section.studyGuide &&
            !_endsStudyGuide(_normalize(heading))) {
          studyGuideLines.add('### ${_topicTitle(heading)}');
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
          if (task != null && !_isInstructionLeak(task.group(2)!)) {
            final (text, at) = splitTime(task.group(2)!.trim());
            tasks.add(
              NoteTask(
                text: text,
                done: task.group(1)!.toLowerCase() == 'x',
                lineIndex: i,
                at: at,
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
        case _Section.studyGuide:
          studyGuideLines.add(line);
        case _Section.deadlines:
          if (line.trim().isEmpty) continue;
          final dated = _leadingDate.firstMatch(line);
          if (dated != null && dated.group(2)!.trim().isNotEmpty) {
            deadlines.add(
              NoteDeadline(
                rawDate: dated.group(1)!,
                description: splitTime(dated.group(2)!.trim()).$1,
                date: DateTime.tryParse(dated.group(1)!),
              ),
            );
          } else {
            final bullet = _bullet.firstMatch(line);
            deadlines.add(
              NoteDeadline(
                rawDate: '',
                description: splitTime((bullet?.group(1) ?? line).trim()).$1,
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
        if (task != null && !_isInstructionLeak(task.group(2)!)) {
          final (text, at) = splitTime(task.group(2)!.trim());
          tasks.add(
            NoteTask(
              text: text,
              done: task.group(1)!.toLowerCase() == 'x',
              lineIndex: i,
              at: at,
            ),
          );
        }
      }
    }

    final transcript = transcriptLines.join('\n').trim();
    final studyGuide = _withTopicHeadings(studyGuideLines).trim();

    return ParsedNotes(
      rawMarkdown: markdown,
      summary: summaryLines.isEmpty ? null : summaryLines.join('\n'),
      concepts: concepts,
      tasks: tasks,
      assignments: assignments,
      quizzes: quizzes,
      important: important,
      examHints: examHints,
      studyGuide: studyGuide.isEmpty ? null : studyGuide,
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
    if (_isNothing(text) || _isInstructionLeak(text)) return null;
    return text;
  }

  /// "- [ ] Lab report 3 — due 2026-10-01 — submit on the portal, 10 marks".
  ///
  /// The box is optional: an app that drops it still gives an assignment,
  /// just an unticked one.
  static NoteTask? _assignment(String line, int index) {
    final boxed = _task.firstMatch(line);
    final raw = boxed?.group(2)?.trim() ?? _item(line);
    if (raw == null || _isNothing(raw) || _isInstructionLeak(raw)) return null;
    final (text, at) = splitTime(raw);

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
      at: at,
    );
  }

  /// "- 2026-09-28 — Quiz 2 on eigenvalues — covers ch 5, closed book".
  static NoteQuiz? _quiz(String line) {
    final raw = _item(line);
    if (raw == null) return null;
    final (text, at) = splitTime(raw);

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
      at: at,
    );
  }

  /// "[1:02:15]", "(42:10)" or "[at 0:42:10]": where in the recording a
  /// line was said. The prompt asks for one on every announcement, so the
  /// student can listen to the moment instead of trusting the AI.
  static final RegExp _time = RegExp(
    r'\s*[\[(]\s*(?:at\s+)?((?:\d{1,2}:)?\d{1,2}:\d{2})\s*[\])]',
  );

  /// [text] without its trailing time, and the time.
  static (String, Duration?) splitTime(String text) {
    final match = _time.allMatches(text).lastOrNull;
    if (match == null) return (text, null);
    final parts = match.group(1)!.split(':').map(int.parse).toList();
    final at = parts.length == 3
        ? Duration(hours: parts[0], minutes: parts[1], seconds: parts[2])
        : Duration(minutes: parts[0], seconds: parts[1]);
    final rest = (text.substring(0, match.start) + text.substring(match.end))
        .trim()
        // The separator that stood before the time.
        .replaceAll(RegExp(r'\s*[—–-]\s*$'), '');
    return (rest, at);
  }

  /// Every checkbox unticked. Pasted notes start that way: the AI cannot
  /// know what the student has done, however it marks the boxes.
  static String untickAll(String markdown) => markdown.replaceAllMapped(
    RegExp(r'^(\s*[-*+•]\s*)\[[xX]\]', multiLine: true),
    (m) => '${m.group(1)}[ ]',
  );

  /// A line about the prompt itself — "review the lecto_prompt.txt file" —
  /// which an AI sometimes lists as if it were part of the lecture.
  static bool _isInstructionLeak(String text) {
    final t = text.toLowerCase();
    return t.contains('lecto_prompt') ||
        t.contains('prompt.txt') ||
        t.contains('prompt file') ||
        t.contains('instructions file') ||
        t.contains('instruction file');
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
        out.add('### ${_topicTitle(trimmed)}');
      } else {
        out.add(line);
      }
    }
    return out.join('\n');
  }

  /// "Topic 2: Entropy:" → "Entropy".
  static String _topicTitle(String heading) => heading
      .trim()
      .replaceFirst(
        RegExp(r'^topic\s*\d*\s*[:.\-–—]\s*', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r':$'), '');

  /// The headings of the reply's other sections, which end the lecture
  /// notes. Anything else is a topic inside them.
  static bool _endsStudyGuide(String name) => const {
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
    if (has('study guide') ||
        has('lecture note') ||
        has('detailed note') ||
        has('study note') ||
        has('class note') ||
        name == 'notes' ||
        has('in depth') ||
        has('detailed explanation')) {
      return _Section.studyGuide;
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
  studyGuide,
  deadlines,
  transcript,
  other,
}
