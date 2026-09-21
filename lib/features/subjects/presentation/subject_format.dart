/// Small helpers shared by the Subjects screens.
library;

String formatHours(int ms) {
  final minutes = ms ~/ 60000;
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
}

/// "LA" for Linear Algebra, "TA" for Theory of Automata.
///
/// Lead-in words are skipped when enough is left, so "Intro to Computer
/// Architecture" is CA and "Intro to Cyber Security" is CS — not both IC.
String subjectInitials(String name) {
  const skip = {'to', 'of', 'and', 'the', 'in', 'for', '&'};
  const leadIns = {
    'intro',
    'introduction',
    'advanced',
    'adv',
    'basic',
    'basics',
    'principles',
    'fundamentals',
    'foundations',
    'applied',
  };
  var words = name
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && !skip.contains(w.toLowerCase()))
      .toList();
  final core = words
      .where((w) => !leadIns.contains(w.toLowerCase().replaceAll('.', '')))
      .toList();
  if (core.length >= 2) words = core;
  if (words.isEmpty) return '?';
  if (words.length == 1) {
    final word = words.first;
    return word.substring(0, word.length < 2 ? word.length : 2).toUpperCase();
  }
  return (words[0][0] + words[1][0]).toUpperCase();
}
