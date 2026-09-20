import 'package:shared_preferences/shared_preferences.dart';

/// Language hint sent with new recordings (TRX-015).
///
/// [code] is an ISO-639-1 code passed to the speech-to-text provider, or
/// `auto` to let it detect the language (handles English/Urdu code-switching).
enum TranscriptionLanguage {
  auto('auto', 'Auto-detect', 'Best for lectures that mix languages'),
  english('en', 'English', 'Lecture is in English'),
  urdu('ur', 'Urdu', 'Transcribed in Roman Urdu');

  const TranscriptionLanguage(this.code, this.label, this.description);

  final String code;
  final String label;
  final String description;

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
