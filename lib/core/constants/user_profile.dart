import 'package:shared_preferences/shared_preferences.dart';

/// The name the dashboard greets you by.
///
/// There is no account, so this is simply a preference. Empty until set, and
/// the greeting drops the name rather than inventing one.
class UserProfile {
  UserProfile._();

  static const _nameKey = 'displayName';

  /// The name as last read or set, for showing without waiting on storage.
  static String? cachedName;

  static Future<String> name() async {
    final prefs = await SharedPreferences.getInstance();
    return cachedName = (prefs.getString(_nameKey) ?? '').trim();
  }

  static Future<void> setName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    cachedName = name.trim();
    await prefs.setString(_nameKey, name.trim());
  }

  /// First letter, for the avatar. Falls back to the app's own initial.
  static String initial(String name) =>
      name.isEmpty ? 'L' : name.characters.first.toUpperCase();
}

/// `characters` without the package: good enough for a single initial.
extension _FirstCharacter on String {
  Iterable<String> get characters => split('');
}
