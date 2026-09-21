import 'package:shared_preferences/shared_preferences.dart';

/// What language your lectures are in.
///
/// This goes into the prompt shared with your AI app, so it knows what it is
/// listening to and what language to write the notes in. Left on
/// [auto] it says nothing and lets the AI work it out, which handles lectures
/// that switch between languages mid-sentence.
enum TranscriptionLanguage {
  auto('auto', 'Auto-detect', 'Best for lectures that mix languages', null),
  english(
    'en',
    'English',
    'Lecture is in English',
    'The lecture is in English. Write the notes in English.',
  ),
  urdu(
    'ur',
    'Urdu',
    'Notes in Roman Urdu',
    'The lecture is in Urdu. Write the notes in Roman Urdu — Urdu written '
        'with English letters — keeping technical terms in English.',
  );

  const TranscriptionLanguage(
    this.code,
    this.label,
    this.description,
    this.promptLine,
  );

  final String code;
  final String label;
  final String description;

  /// The sentence added to the prompt, or null to let the AI decide.
  final String? promptLine;

  static const _prefKey = 'transcriptionLanguage';

  static TranscriptionLanguage fromCode(String? code) => values.firstWhere(
    (language) => language.code == code,
    orElse: () => TranscriptionLanguage.auto,
  );

  static Future<TranscriptionLanguage> load() async {
    final prefs = await SharedPreferences.getInstance();
    return fromCode(prefs.getString(_prefKey));
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, code);
  }
}
