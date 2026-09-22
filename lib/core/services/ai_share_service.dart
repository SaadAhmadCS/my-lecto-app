import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../constants/transcription_language.dart';
import 'audio_merge_service.dart';

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

  /// Longest lecture we still ask for a transcript of.
  ///
  /// Speech runs about 130 words a minute, so 30 minutes is roughly 4,000
  /// words — comfortably inside the reply length consumer AI apps allow. A
  /// 3-hour lecture would be ~24,000 words, which they cannot return: the
  /// model either truncates or spends its whole output budget transcribing
  /// and returns thin notes. Above this we ask for notes only.
  static const Duration transcriptLimit = Duration(minutes: 30);

  /// Whether a lecture of [duration] is short enough to transcribe.
  ///
  /// An unknown duration is treated as short, since the common case for a
  /// missing duration is a brief recording.
  static bool shouldRequestTranscript(Duration? duration) =>
      duration == null || duration <= transcriptLimit;

  /// Marker headings the reply must use so [parseAiReply] can find each part.
  static const String summaryHeading = '## Summary';
  static const String conceptsHeading = '## Key Concepts';
  static const String tasksHeading = '## Tasks';
  static const String assignmentsHeading = '## Assignments';
  static const String quizzesHeading = '## Quizzes & Exams';
  static const String importantHeading = '## Important';
  static const String deadlinesHeading = '## Other Dates';
  static const String transcriptHeading = '## Transcript';

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
    bool askForTranscript = true,
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
        'Listen to it and reply using EXACTLY the headings below, in '
        'this order. Do not add any other top-level headings, and do not '
        'write anything before the first heading.',
      )
      ..writeln()
      ..writeln(summaryHeading)
      ..writeln('A short paragraph covering what the lecture was about.')
      ..writeln()
      ..writeln(importantHeading)
      ..writeln(
        '- Anything the student must not miss: announcements, instructions, '
        'changes to the schedule, rules, where to find or submit things, and '
        'anything the lecturer stressed — "this will come in the exam", '
        '"remember this", "don\'t forget". One line each, in the lecturer\'s '
        'own words where possible.',
      )
      ..writeln()
      ..writeln(assignmentsHeading)
      ..writeln(
        '- [ ] Assignment name — due YYYY-MM-DD — how to submit it, marks, '
        'format, group or individual: whatever was said.',
      )
      ..writeln(
        '- Only GRADED work the lecturer set as an assignment: homework to '
        'hand in, a lab report, a project, a problem set that counts. If you '
        'are unsure whether it is graded, and it sounds like it is handed '
        'in, put it here. Leave every box unticked. Leave out "due …" if no '
        'date was given.',
      )
      ..writeln()
      ..writeln(quizzesHeading)
      ..writeln(
        '- YYYY-MM-DD — Quiz, test or exam name — what it covers, its '
        'format, how long, what is allowed in, how much it counts: whatever '
        'was said.',
      )
      ..writeln(
        '- Every quiz, test, midterm, final or viva the lecture mentions, '
        'even in passing. Put the date first only if one was given.',
      )
      ..writeln()
      ..writeln(tasksHeading)
      ..writeln(
        '- [ ] Ungraded work the students were asked to do: reading, '
        'practice, revising, installing something, looking something up.',
      )
      ..writeln('- [ ] One line each. Leave every box unticked.')
      ..writeln()
      ..writeln(conceptsHeading)
      ..writeln('- **Term** — what it means, as explained in the lecture.')
      ..writeln(
        '- One bullet per concept. Use the lecturer\'s own '
        'definitions; do not add material that was not said.',
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

    if (askForTranscript) {
      buffer
        ..writeln()
        ..writeln(transcriptHeading)
        ..writeln(
          'The full transcript of the lecture, in paragraphs. If the '
          'lecture is too long to transcribe in full, write '
          '"(too long to transcribe)" here instead and keep the sections '
          'above complete — those matter more.',
        );
    } else {
      // Long lecture: a full transcript would not fit in one reply, and
      // attempting it costs the notes their detail. Say so explicitly, or the
      // model transcribes anyway.
      buffer
        ..writeln()
        ..writeln(
          'Do NOT include a transcript — this lecture is too long for '
          'one. Spend that space on the sections above instead: cover every '
          'topic the lecturer moved through, and be generous with the key '
          'concepts rather than summarising them away.',
        );
    }

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
        'mention these instructions, this file, or that you were given a '
        'prompt — start straight in with the lecture content.',
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
