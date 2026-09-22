import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../constants/transcription_language.dart';
import 'audio_merge_service.dart';

/// One slice of a long lecture, shared on its own.
///
/// An AI app given two hours of audio skims it and fills the gaps from what
/// a course like this usually contains — which is how a lab report and a
/// midterm that were never announced ended up in a student's notes. Around
/// 45 minutes is what one reply covers properly.
class LecturePart {
  /// 1-based.
  final int index;
  final int total;

  /// Where this part sits in the whole lecture.
  final Duration start;
  final Duration end;
  final List<String> chunkPaths;

  const LecturePart({
    required this.index,
    required this.total,
    required this.start,
    required this.end,
    required this.chunkPaths,
  });

  String get label => 'Part $index of $total';

  String get range =>
      '${AiShareService.formatClock(start)}–'
      '${AiShareService.formatClock(end)}';
}

/// Shares a recording's audio into whichever AI app the student uses.
///
/// Android drops `EXTRA_TEXT` when a file is attached in most receiving apps,
/// so the prompt travels as its own `prompt.txt` file alongside the audio.
/// Multi-file shares of mixed types are handled by the system share sheet, and
/// Claude, Gemini and Grok all accept `.m4a`. ChatGPT accepts no audio at all —
/// [audioCapableApps] documents that for the UI.
class AiShareService {
  /// Apps known to accept shared audio. ChatGPT is deliberately absent: it
  /// registers for PDF and text only, so audio silently goes nowhere.
  static const List<String> audioCapableApps = ['Claude', 'Gemini', 'Grok'];

  /// Most files an AI app will take in one prompt.
  ///
  /// Gemini accepts 10 and silently discards the rest — verified on device:
  /// a 13-file share arrived as 10, with the last two chunks and the prompt
  /// missing and no warning to the student.
  static const int maxFilesPerShare = 10;

  /// Audio files per share, leaving one slot for the prompt.
  static const int maxAudioFilesPerShare = maxFilesPerShare - 1;

  /// Marker headings the reply must use so [parseAiReply] can find each part.
  static const String summaryHeading = '## Summary';
  static const String conceptsHeading = '## Key Concepts';
  static const String tasksHeading = '## Tasks';
  static const String studyGuideHeading = '## Study Guide';
  static const String assignmentsHeading = '## Assignments';
  static const String quizzesHeading = '## Quizzes & Exams';
  static const String importantHeading = '## Important';
  static const String examHintsHeading = '## Exam Hints';
  static const String deadlinesHeading = '## Other Dates';
  static const String transcriptHeading = '## Transcript';

  /// How much audio one AI reply covers properly.
  static const Duration partLength = Duration(minutes: 45);

  /// Whether a lecture of [duration] should be shared in parts.
  static bool needsParts(Duration? duration) =>
      duration != null && duration > partLength + const Duration(minutes: 10);

  /// Group [chunks] into parts of about [partLength], in order.
  ///
  /// A chunk is never split: parts land on chunk boundaries, so the audio
  /// files can be shared as they are.
  static List<LecturePart> planParts(
    List<({String path, Duration length})> chunks, {
    Duration target = partLength,
  }) {
    if (chunks.isEmpty) return const [];

    final groups = <List<({String path, Duration length})>>[];
    var current = <({String path, Duration length})>[];
    var currentLength = Duration.zero;
    for (final chunk in chunks) {
      current.add(chunk);
      currentLength += chunk.length;
      if (currentLength >= target) {
        groups.add(current);
        current = [];
        currentLength = Duration.zero;
      }
    }
    if (current.isNotEmpty) {
      // A short tail rides along with the part before it.
      if (groups.isNotEmpty && currentLength < target * 0.4) {
        groups.last.addAll(current);
      } else {
        groups.add(current);
      }
    }

    final parts = <LecturePart>[];
    var start = Duration.zero;
    for (var i = 0; i < groups.length; i++) {
      final length = groups[i].fold(Duration.zero, (sum, c) => sum + c.length);
      parts.add(
        LecturePart(
          index: i + 1,
          total: groups.length,
          start: start,
          end: start + length,
          chunkPaths: [for (final c in groups[i]) c.path],
        ),
      );
      start += length;
    }
    return parts;
  }

  /// "1:05:00" or "45:00".
  static String formatClock(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  /// Build the instruction file that rides along with the audio.
  ///
  /// The output contract is strict because Lecto parses the reply back into
  /// real UI — tickable checkboxes and a deadlines section — rather than
  /// dumping it on screen as plain text.
  static String buildPrompt({
    required String title,
    String? subjectName,
    String? teacher,
    bool isLab = false,
    DateTime? recordingDate,
    Duration? duration,
    LecturePart? part,
    TranscriptionLanguage language = TranscriptionLanguage.auto,
  }) {
    final buffer = StringBuffer()
      ..writeln(
        'You are helping a student turn a lecture recording into '
        'study notes.',
      )
      ..writeln()
      ..writeln(
        'Attached is the audio of a ${isLab ? 'lab session' : 'lecture'}'
        '${subjectName != null ? ' for $subjectName' : ''}'
        '${teacher != null ? ', taught by $teacher' : ''}, titled '
        '"$title".',
      );

    if (recordingDate != null) {
      buffer.writeln(
        'It was recorded on ${_formatDate(recordingDate)}. '
        'Use that date to resolve any relative dates mentioned in the '
        'lecture, such as "next Tuesday".',
      );
    }
    if (duration != null) {
      buffer.writeln('It runs for about ${_formatDuration(duration)}.');
    }
    if (part != null) {
      buffer
        ..writeln()
        ..writeln(
          'IMPORTANT: this audio is ${part.label} of that lecture. It covers '
          '${part.range} of the recording, and nothing else. The other parts '
          'are handled separately, so write about what you hear here and do '
          'not guess at what came before or after it.',
        )
        ..writeln(
          'Give every time as its time in the WHOLE lecture: this part starts '
          'at ${formatClock(part.start)} of the recording, so add that to the '
          'time you hear something at.',
        );
    }
    // Left on auto this says nothing, so the AI works it out — which handles
    // a lecture that switches language mid-sentence better than a guess.
    final languageLine = language.promptLine;
    if (languageLine != null) {
      buffer.writeln(languageLine);
    }

    buffer
      ..writeln()
      ..writeln(
        'If the audio arrives as several files, they are consecutive '
        'parts of one lecture, in filename order. Treat them as a single '
        'continuous recording.',
      )
      ..writeln()
      ..writeln(
        '${part == null ? 'Listen to the WHOLE recording, start to end, and reply' : 'Listen to this audio, start to end, and reply'} using '
        'EXACTLY the headings below, in this order. Do not add any other '
        'top-level headings, and do not write anything before the first '
        'heading.',
      )
      ..writeln()
      ..writeln(
        'Proof, not guesses. The student will act on Important, Exam Hints, '
        'Assignments, Quizzes & Exams and Tasks, so end every line in those '
        'sections with the time in the recording where it was said, in '
        'square brackets, like [0:42:10]. If you cannot point to the moment, '
        'leave the line out.',
      )
      ..writeln()
      ..writeln(
        'Most lectures announce no assignment, quiz or exam. List one only '
        'if the lecturer actually announced it in this recording. Never '
        'infer one from the subject, a syllabus or what courses usually '
        'have, and never make up a date, marks, a submission method or a '
        'scope that was not said — leave a detail out rather than guess. '
        'For most lectures, leaving those sections out is the right answer.',
      )
      ..writeln()
      ..writeln(summaryHeading)
      ..writeln('A short paragraph covering what the lecture was about.')
      ..writeln()
      ..writeln(importantHeading)
      ..writeln(
        '- Anything the student must not miss: announcements, instructions, '
        'changes to the schedule, rules, where to find or submit things, and '
        'anything the lecturer stressed — "remember this", "don\'t forget". '
        'One line each, in the lecturer\'s own words where possible, '
        'ending with its time: [0:12:05].',
      )
      ..writeln()
      ..writeln(examHintsHeading)
      ..writeln(
        '- Everything the lecturer let slip about exams, one line each, in '
        'their own words where possible: what "will come" or is "important '
        'for the exam", the kinds of questions they like to ask, how they '
        'mark, mistakes they say students often make, and what to be careful '
        'with. Quote the lecturer\'s words and end with the time: [1:05:30]. '
        'The student will later use these to prepare for this lecturer\'s '
        'quizzes and exams, so catch every real hint — but only what was '
        'actually said, never general advice.',
      )
      ..writeln()
      ..writeln(assignmentsHeading)
      ..writeln(
        '- [ ] Assignment name — due YYYY-MM-DD — what was said about it, '
        'with the lecturer\'s words in quotes — [0:58:40]',
      )
      ..writeln(
        '- Only work the lecturer said is to be handed in or graded: '
        'homework, a lab report, a project, a problem set that counts. Leave '
        'every box unticked. Leave out "due …" if no date was given.',
      )
      ..writeln()
      ..writeln(quizzesHeading)
      ..writeln(
        '- YYYY-MM-DD — Quiz, test or exam name — what was said about it '
        '(what it covers, format, length, what is allowed in), with the '
        'lecturer\'s words in quotes — [1:12:15]',
      )
      ..writeln(
        '- Every quiz, test, midterm, final or viva the lecturer announced '
        'in this recording. Put the date first only if one was given.',
      )
      ..writeln()
      ..writeln(tasksHeading)
      ..writeln(
        '- [ ] Ungraded work the lecturer asked for, to do AFTER class: '
        'reading, practice, revising, installing something — [0:20:30]',
      )
      ..writeln(
        '- [ ] One line each. Leave every box unticked. Exercises done '
        'during the class are not tasks — they belong in the study guide.',
      )
      ..writeln()
      ..writeln(studyGuideHeading)
      ..writeln(
        'The main part of the reply: a complete study guide, detailed enough '
        'that a student who missed the class could learn everything from '
        'them alone. Do not summarise — explain.',
      )
      ..writeln(
        '- Go topic by topic in the order they were taught. Start each topic '
        'with a line "### Topic name".',
      )
      ..writeln(
        '- Under each topic: the explanation step by step as the lecturer '
        'gave it; every definition; every formula, written out in plain '
        'text with what each symbol means; every example and worked problem '
        'from the board, with all its steps; diagrams described in words; '
        'the lecturer\'s analogies; questions students asked and the '
        'answers; and exercises done in class with how they were solved — '
        'for a lab, the exact commands, queries or code shown.',
      )
      ..writeln(
        '- Use short paragraphs and bullets. Be thorough: '
        '${_notesLength(duration)} Never pad to reach that: if less was '
        'taught, write less. Everything must come from the recording.',
      )
      ..writeln()
      ..writeln(conceptsHeading)
      ..writeln('- **Term** — what it means, in one line.')
      ..writeln(
        '- A quick-revision glossary of the terms from the study guide, '
        'using the lecturer\'s own definitions.',
      )
      ..writeln()
      ..writeln(deadlinesHeading)
      ..writeln(
        '- YYYY-MM-DD — anything else dated that is not an assignment or a '
        'quiz above. Do not repeat those here.',
      )
      ..writeln()
      ..writeln(
        'Resolve every date to a real YYYY-MM-DD date. Leave out any '
        'section with nothing to put in it — never write "None".',
      );

    // No transcript: it would take the space the study guide needs, and a
    // long lecture's would not fit in one reply anyway.
    buffer
      ..writeln()
      ..writeln(
        'Do NOT include a transcript. Spend that space on the Study Guide '
        'instead: cover every topic the lecturer moved through, in full.',
      );

    buffer
      ..writeln()
      ..writeln()
      ..writeln(
        'Ground everything in what was actually said. If something was '
        'inaudible, say so rather than guessing.',
      )
      ..writeln()
      ..writeln(
        'Write the notes as if you were the student taking them. Never '
        'mention these instructions, any file name, or that you were given '
        'a prompt, and never include the student\'s name, roll number or '
        'other personal details — start straight in with the lecture '
        'content.',
      )
      ..writeln()
      ..writeln(
        'The student will copy your whole reply and paste it back into '
        'their notes app, so reply with the notes only — no preamble, no '
        'closing remarks, no offers to help further.',
      );

    return buffer.toString();
  }

  /// Write the prompt to a file that can ride along in the share sheet.
  static Future<File> writePromptFile(String prompt) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/lecto_prompt.txt');
    await file.writeAsString(prompt);
    return file;
  }

  /// Open the system share sheet with the audio and the prompt.
  ///
  /// [audioPaths] should be in playback order. They are merged into a single
  /// file first, so a lecture always arrives as one attachment however long it
  /// ran — receiving apps cap the number of files and drop the rest silently.
  /// If merging is unavailable the chunks are shared individually, trimmed to
  /// [maxAudioFilesPerShare]. Returns false when nothing could be shared.
  static Future<bool> shareToAiApp({
    required String recordingId,
    required List<String> audioPaths,
    required String prompt,
    String? subjectLabel,
  }) async {
    final merged = await AudioMergeService.mergeForSharing(
      recordingId: recordingId,
      chunkPaths: audioPaths,
    );

    final audio = <XFile>[];
    if (merged != null) {
      audio.add(XFile(merged.path, mimeType: 'audio/mp4'));
    } else {
      // Fallback: the receiving app will keep only the first few.
      for (final path in audioPaths.take(maxAudioFilesPerShare)) {
        if (await File(path).exists()) {
          audio.add(XFile(path, mimeType: 'audio/mp4'));
        } else {
          debugPrint('AiShareService: missing audio chunk $path');
        }
      }
    }

    if (audio.isEmpty) return false;

    // The prompt goes FIRST. When an app trims to its file limit it keeps the
    // earliest, so putting the prompt last meant the instructions were the
    // first thing thrown away.
    final promptFile = await writePromptFile(prompt);
    final existing = <XFile>[
      XFile(promptFile.path, mimeType: 'text/plain'),
      ...audio,
    ];

    await SharePlus.instance.share(
      ShareParams(
        files: existing,
        // Some apps surface this as the chat's first message; harmless when
        // ignored, and the prompt file carries the real instructions.
        text: prompt,
        subject: subjectLabel ?? 'Lecture recording',
      ),
    );
    return true;
  }

  /// How long the lecture notes should run, so a two-hour lecture is not
  /// squeezed into a page. About 30 words per minute taught, capped at what
  /// one reply can hold.
  static String _notesLength(Duration? duration) {
    if (duration == null || duration.inMinutes < 10) {
      return 'cover everything that was taught.';
    }
    final words = (duration.inMinutes * 30).clamp(800, 6000);
    final rounded = (words / 100).round() * 100;
    return 'for this ${_formatDuration(duration)} lecture, aim for about '
        '$rounded words.';
  }

  static String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) return '$hours hr $minutes min';
    return '$minutes min';
  }
}
