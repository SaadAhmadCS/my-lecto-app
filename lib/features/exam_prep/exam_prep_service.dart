import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/services/notes_parser.dart';
import '../recording/data/local/recording_database.dart';

/// One lecture that can go into an exam-prep pack.
class PrepLecture {
  final String id;
  final String title;
  final DateTime recordedAt;
  final String? notesMarkdown;
  final String? transcript;
  final ParsedNotes? notes;

  PrepLecture({
    required this.id,
    required this.title,
    required this.recordedAt,
    this.notesMarkdown,
    this.transcript,
  }) : notes = (notesMarkdown == null || notesMarkdown.trim().isEmpty)
           ? null
           : NotesParser.parse(notesMarkdown);

  bool get hasNotes => notes != null;

  /// The transcript, whether it was saved apart or left inside the notes.
  String? get fullTranscript {
    final saved = transcript?.trim() ?? '';
    if (saved.isNotEmpty) return saved;
    return notes?.transcript;
  }

  int get examHintCount => notes?.examHints.length ?? 0;
}

/// A quiz or exam to prepare for: one a lecture announced, or one the student
/// named ("Midterm").
class PrepExam {
  final String title;
  final DateTime? date;
  final String? details;

  const PrepExam({required this.title, this.date, this.details});

  String get key => '${title.toLowerCase().trim()}|${date?.toIso8601String()}';
}

/// Builds the pack a student sends their AI before a quiz or exam: every
/// chosen lecture's notes, the teacher's exam hints gathered up front, and a
/// prompt asking to prepare them the way this teacher examines.
class ExamPrepService {
  /// A pack past this many words may be cut off by some AI apps.
  static const largePackWords = 120000;

  /// Every lecture of [subjectId], oldest first.
  static Future<List<PrepLecture>> lectures(String subjectId) async {
    final db = await RecordingDatabase.database;
    final rows = await db.query(
      'recordings',
      columns: [
        'id',
        'title',
        'created_at',
        'notes_markdown',
        'transcript_markdown',
      ],
      where: "subject_id = ? AND status != 'recording'",
      whereArgs: [subjectId],
      orderBy: 'created_at ASC',
    );
    return [
      for (final row in rows)
        PrepLecture(
          id: row['id'] as String,
          title: row['title'] as String? ?? 'Lecture',
          recordedAt:
              DateTime.tryParse(row['created_at'] as String? ?? '') ??
              DateTime.now(),
          notesMarkdown: row['notes_markdown'] as String?,
          transcript: row['transcript_markdown'] as String?,
        ),
    ];
  }

  /// Every quiz and exam the lectures announced, once each: upcoming first,
  /// soonest first, then undated, then past ones.
  static List<PrepExam> announcedExams(
    List<PrepLecture> lectures, {
    DateTime? now,
  }) {
    final today = _day(now ?? DateTime.now());
    final byKey = <String, PrepExam>{};
    for (final lecture in lectures) {
      for (final quiz in lecture.notes?.quizzes ?? const <NoteQuiz>[]) {
        final exam = PrepExam(
          title: quiz.title,
          date: quiz.date,
          details: quiz.details,
        );
        // A later lecture's mention usually carries the newer details.
        byKey[exam.key] = exam;
      }
    }

    int rank(PrepExam e) {
      final date = e.date;
      if (date == null) return 1;
      return _day(date).isBefore(today) ? 2 : 0;
    }

    return byKey.values.toList()..sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      if (a.date == null || b.date == null) return a.title.compareTo(b.title);
      // Past exams: most recent first.
      return rank(a) == 2
          ? b.date!.compareTo(a.date!)
          : a.date!.compareTo(b.date!);
    });
  }

  /// The dated exam before [exam], if any — "since the last quiz" starts
  /// after it.
  static PrepExam? previousExam(List<PrepExam> exams, PrepExam exam) {
    final date = exam.date;
    if (date == null) return null;
    PrepExam? best;
    for (final e in exams) {
      final d = e.date;
      if (d == null || !d.isBefore(date)) continue;
      if (best == null || d.isAfter(best.date!)) best = e;
    }
    return best;
  }

  /// Rough size of the pack, in words.
  static int wordCount(
    Iterable<PrepLecture> lectures, {
    required bool includeTranscripts,
  }) {
    var words = 0;
    for (final l in lectures) {
      words += _words(l.notes == null ? '' : _notesWithoutTranscript(l));
      if (includeTranscripts) words += _words(l.fullTranscript ?? '');
    }
    return words;
  }

  /// The pack itself: hints and announcements first, then every lecture.
  static String buildPack({
    required String course,
    required PrepExam exam,
    required List<PrepLecture> lectures,
    required bool includeTranscripts,
    String? teacher,
  }) {
    final sorted = [...lectures]
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    final out = StringBuffer()
      ..writeln('# Exam prep pack — $course')
      ..writeln()
      ..writeln('Exam: ${_examLine(exam)}');
    if (teacher != null) out.writeln('Teacher: $teacher');
    out
      ..writeln(
        'Lectures: ${sorted.length}'
        '${sorted.isEmpty ? '' : ', ${_date(sorted.first.recordedAt)} to '
                  '${_date(sorted.last.recordedAt)}'}',
      )
      ..writeln();

    void gathered(String heading, List<String> Function(ParsedNotes) pick) {
      final lines = <String>[
        for (final l in sorted)
          for (final item
              in l.notes == null ? const <String>[] : pick(l.notes!))
            '- $item (${_date(l.recordedAt)}, ${l.title})',
      ];
      if (lines.isEmpty) return;
      out
        ..writeln('## $heading')
        ..writeln();
      lines.forEach(out.writeln);
      out.writeln();
    }

    gathered('Everything the teacher said about exams', (n) => n.examHints);
    gathered(
      'Every quiz and exam announced',
      (n) => [
        for (final q in n.quizzes)
          [if (q.date != null) _date(q.date!), q.title, ?q.details].join(' — '),
      ],
    );
    gathered('Instructions and announcements', (n) => n.important);

    for (var i = 0; i < sorted.length; i++) {
      final l = sorted[i];
      out
        ..writeln('---')
        ..writeln()
        ..writeln('# Lecture ${i + 1} — ${_date(l.recordedAt)} — ${l.title}')
        ..writeln();
      if (l.notes != null) {
        out
          ..writeln(_notesWithoutTranscript(l).trim())
          ..writeln();
      } else {
        out
          ..writeln('(No notes for this lecture yet.)')
          ..writeln();
      }
      final transcript = l.fullTranscript;
      if (includeTranscripts && transcript != null && transcript.isNotEmpty) {
        out
          ..writeln('## Transcript — the teacher\'s own words')
          ..writeln()
          ..writeln(transcript.trim())
          ..writeln();
      }
    }
    return out.toString();
  }

  /// What the student's AI is asked to do with the pack.
  static String buildPrompt({
    required String course,
    required PrepExam exam,
    required int lectureCount,
    required bool includeTranscripts,
    String? teacher,
    bool isLab = false,
  }) {
    final who = teacher ?? 'the teacher';
    return '''
I'm a student preparing for ${_examLine(exam)} in $course${isLab ? ' (a lab course)' : ''}${teacher == null ? '' : ', taught by $teacher'}.

The attached file is my notes from $lectureCount lecture${lectureCount == 1 ? '' : 's'} of this course${includeTranscripts ? ', with transcripts of what $who actually said' : ''}. It starts with everything $who said about exams, every quiz and exam announced, and every instruction given — gathered from all the lectures — and then has each lecture in order.

Prepare me for this exam the way THIS teacher examines. Their hints and warnings matter more than what a typical course would cover, so weigh them above your general knowledge. Work only from the file; if you add something from outside it, say so.

1. What will come — every topic $who said will be in the exam, or stressed, ranked by how strongly and how often. Give the lecture date for each.
2. How $who asks — the kinds of questions they favour and how they mark, with an example of each.
3. Traps — every mistake $who warned students make, and everything they said to be careful with, and how to avoid each.
4. Revision, topic by topic — for everything in scope: the definitions, formulas and methods exactly as taught, in the teacher's own notation and examples.
5. Practice paper — questions in this teacher's style on the most likely topics, shaped like the real ${exam.title} if its format was announced. Put the worked answers after all the questions.
6. Last-night checklist — one short page.

If the scope of the exam was announced (a chapter, the lectures since the last quiz), keep to it. Point out anything in scope that the notes cover thinly, so I can review it elsewhere.

Then offer to quiz me one question at a time, in this teacher's style, and to tell me what to go over again from my answers.
''';
  }

  /// Share the pack and prompt with the student's AI app.
  static Future<void> share({
    required String course,
    required PrepExam exam,
    required String pack,
    required String prompt,
  }) async {
    final dir = await getTemporaryDirectory();
    final name = 'Lecto_ExamPrep_${_slug(course)}_${_slug(exam.title)}';
    final promptFile = File('${dir.path}/${name}_prompt.txt');
    final packFile = File('${dir.path}/$name.txt');
    await promptFile.writeAsString(prompt);
    await packFile.writeAsString(pack);

    await SharePlus.instance.share(
      ShareParams(
        // The prompt goes first: an app trimming to its file limit keeps
        // the earliest.
        files: [
          XFile(promptFile.path, mimeType: 'text/plain'),
          XFile(packFile.path, mimeType: 'text/plain'),
        ],
        text: prompt,
        subject: 'Prepare me for ${exam.title} — $course',
      ),
    );
  }

  static String _notesWithoutTranscript(PrepLecture l) {
    final markdown = l.notesMarkdown ?? '';
    // Cut at the transcript heading; the transcript is added separately.
    final match = RegExp(
      r'^\s{0,3}(#{1,6}\s*|\*\*)?\s*transcript\b.*$',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(markdown);
    return match == null ? markdown : markdown.substring(0, match.start);
  }

  static String _examLine(PrepExam exam) => [
    exam.title,
    if (exam.date != null) 'on ${_date(exam.date!)}',
    if (exam.details != null) '(${exam.details})',
  ].join(' ');

  static int _words(String text) =>
      text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _slug(String text) =>
      text.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '');
}
