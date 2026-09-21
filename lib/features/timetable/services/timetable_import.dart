/// Reading a timetable out of a screenshot, by way of the student's own AI.
///
/// The app cannot read images itself — it has no network and no model — so
/// the screenshot is shared to an AI app with [TimetableImport.prompt], and
/// the reply is pasted back and read by [TimetableImport.parse].
///
/// The format asked for is one pipe-separated line per class. It survives
/// being copied out of a chat app, which strips markdown, and is easy to find
/// even when the AI wraps it in a table or adds a sentence before it.
class TimetableImport {
  TimetableImport._();

  static const prompt = '''
The attached image is my university class timetable. Turn it into a list I can import into my study app.

Reply with ONE LINE PER CLASS, in exactly this format, and nothing else:

Day | Start | End | Course | Room | Type

- Day: Monday, Tuesday, Wednesday, Thursday, Friday, Saturday or Sunday.
- Start and End: 24-hour time, like 08:30 or 13:30.
- Course: the course name, spelled the same way every time it appears. Use the full name rather than an abbreviation. Leave "(Lab)" out of the name — a lab uses the same course name as its lecture.
- Room: the room or lab it is in, or "-" if the timetable does not say.
- Type: "lab" for a lab or practical, otherwise "class".

If a class runs across several periods in a row, write it once, from when it starts to when it ends. Leave out breaks, free periods and teacher names.

Example:
Monday | 08:30 | 10:00 | Linear Algebra | G-09 | class
Tuesday | 13:30 | 16:30 | Advanced Database Systems | Lab-4 | lab

No heading, no explanation, no closing remarks — only the lines.
''';

  /// Read every class line in [reply]. Anything that is not one is ignored
  /// and counted in [TimetableParse.skipped], so a stray sentence or table
  /// header costs nothing.
  static TimetableParse parse(String reply) {
    final classes = <ImportedClass>[];
    final seen = <String>{};
    var skipped = 0;

    for (final raw in reply.split('\n')) {
      final line = _clean(raw);
      if (line.isEmpty) continue;

      final parsed = _parseLine(line);
      if (parsed == null) {
        // Only count lines that look like a class — fields and a time — so a
        // table header or rule line is not reported as a failure.
        if (line.contains('|') && RegExp(r'\d[:.]\d\d').hasMatch(line)) {
          skipped++;
        }
        continue;
      }
      // The same class twice (an AI repeating itself) is imported once.
      if (seen.add(parsed.key)) classes.add(parsed);
    }

    classes.sort((a, b) {
      final byDay = a.weekday.compareTo(b.weekday);
      return byDay != 0 ? byDay : a.startMinute.compareTo(b.startMinute);
    });

    return TimetableParse(classes: classes, skipped: skipped);
  }

  static ImportedClass? _parseLine(String line) {
    var fields = line
        .split(RegExp(r'\s*[|\t]\s*'))
        .map((f) => f.trim())
        .toList();
    // Markdown table rows start and end with a pipe.
    while (fields.isNotEmpty && fields.first.isEmpty) {
      fields.removeAt(0);
    }
    while (fields.isNotEmpty && fields.last.isEmpty) {
      fields.removeLast();
    }
    if (fields.length < 3) return null;

    final weekday = _weekday(fields[0]);
    if (weekday == null) return null;

    // "08:30 - 10:00" in one field instead of two.
    final range = RegExp(
      r'^(.+?)\s*(?:-|–|—|to)\s*(\d{1,2}[:.]\d{2}\s*(?:[ap]\.?m\.?)?)$',
      caseSensitive: false,
    ).firstMatch(fields[1]);
    if (range != null && _minutes(range.group(1)!) != null) {
      fields = [fields[0], range.group(1)!, range.group(2)!, ...fields.skip(2)];
    }
    if (fields.length < 4) return null;

    var start = _minutes(fields[1]);
    var end = _minutes(fields[2]);
    if (start == null || end == null) return null;
    // A 12-hour sheet read without AM/PM. Nobody has class from 1 to 7 in
    // the morning, so "1:30" is afternoon; and "1:00" ending an "11:00"
    // class is too.
    if (start >= 60 && start < 7 * 60 && !_hasHalf(fields[1])) {
      start += 12 * 60;
    }
    // Only when that gives a believable class, so a line that is simply
    // backwards is rejected rather than turned into an 11-hour lecture.
    if (end <= start &&
        end < 12 * 60 &&
        !_hasHalf(fields[2]) &&
        end + 12 * 60 - start <= _longestClass) {
      end += 12 * 60;
    }
    if (end <= start) return null;
    if (start >= 24 * 60 || end > 24 * 60) return null;

    var subject = fields[3];
    var isLab = false;
    final labSuffix = RegExp(
      r'\s*[\(\[]\s*lab\s*[\)\]]\s*$',
      caseSensitive: false,
    );
    if (labSuffix.hasMatch(subject)) {
      isLab = true;
      subject = subject.replaceFirst(labSuffix, '');
    }
    subject = subject.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (subject.isEmpty) return null;

    final room = fields.length > 4 ? _room(fields[4]) : null;
    if (fields.length > 5) {
      final type = fields[5].toLowerCase();
      if (type.contains('lab') || type.contains('practical')) isLab = true;
    }

    return ImportedClass(
      weekday: weekday,
      startMinute: start,
      endMinute: end,
      subject: subject,
      room: room,
      isLab: isLab,
    );
  }

  /// Whether two course names are the same course, as timetables and AIs
  /// spell them: "Intro to Cyber Security" is "Introduction to Cyber
  /// Security", and "Machine Learn. Funda." is "Machine Learning
  /// Fundamentals".
  ///
  /// Word by word, each must be a prefix of the other — so abbreviations
  /// match — ignoring filler words. Course numbers must match exactly, so
  /// "Calculus I" is never "Calculus II".
  static bool sameCourse(String a, String b) {
    final x = _courseWords(a);
    final y = _courseWords(b);
    if (x.isEmpty || x.length != y.length) return false;
    for (var i = 0; i < x.length; i++) {
      final p = x[i];
      final q = y[i];
      if (_numbered.hasMatch(p) || _numbered.hasMatch(q)) {
        if (p != q) return false;
      } else if (!p.startsWith(q) && !q.startsWith(p)) {
        return false;
      }
    }
    return true;
  }

  static const _filler = {
    'to',
    'of',
    'and',
    'the',
    'in',
    'for',
    'a',
    'an',
    '&',
  };

  /// Roman or Arabic course numbers: "I", "II", "IV", "2", "101".
  static final _numbered = RegExp(r'^(?:[ivx]+|\d+)$');

  static List<String> _courseWords(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9& ]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && !_filler.contains(w))
      .toList();

  /// Strip bullets, numbering and the markdown chat apps leave behind.
  static String _clean(String raw) {
    var line = raw.trim();
    line = line.replaceFirst(RegExp(r'^(?:[-*•]|\d+[.)])\s+'), '');
    line = line.replaceAll(RegExp(r'[`*_]'), '');
    return line.trim();
  }

  static const _days = {
    'mon': DateTime.monday,
    'tue': DateTime.tuesday,
    'wed': DateTime.wednesday,
    'thu': DateTime.thursday,
    'fri': DateTime.friday,
    'sat': DateTime.saturday,
    'sun': DateTime.sunday,
  };

  /// "Monday", "Mon", "tues", "Th" … The two-letter forms are each one day.
  static int? _weekday(String field) {
    final word = field.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (word.length < 2) return null;
    for (final entry in _days.entries) {
      final matches = word.length == 2
          ? entry.key.startsWith(word)
          : word.startsWith(entry.key);
      if (matches) return entry.value;
    }
    return null;
  }

  /// Minutes after midnight for "08:30", "8.30", "1:30 PM", "13:30".
  static int? _minutes(String field) {
    final match = RegExp(
      r'^(\d{1,2})[:.](\d{2})\s*([ap])?\.?\s*m?\.?$',
      caseSensitive: false,
    ).firstMatch(field.trim());
    if (match == null) return null;

    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (minute > 59 || hour > 23) return null;

    final half = match.group(3)?.toLowerCase();
    if (half == 'p' && hour < 12) hour += 12;
    if (half == 'a' && hour == 12) hour = 0;
    return hour * 60 + minute;
  }

  /// Longest a single class could plausibly run, in minutes.
  static const _longestClass = 6 * 60;

  static bool _hasHalf(String field) =>
      RegExp(r'[ap]\.?\s*m\b', caseSensitive: false).hasMatch(field);

  static String? _room(String field) {
    final room = field.trim();
    if (room.isEmpty) return null;
    if (RegExp(r'^[-–—?]+$').hasMatch(room)) return null;
    if (const {
      'none',
      'n/a',
      'na',
      'tbd',
      'tba',
      'unknown',
    }.contains(room.toLowerCase())) {
      return null;
    }
    return room;
  }
}

/// What a pasted reply held.
class TimetableParse {
  final List<ImportedClass> classes;

  /// Lines that looked like classes but could not be read.
  final int skipped;

  const TimetableParse({required this.classes, required this.skipped});

  bool get isEmpty => classes.isEmpty;

  /// Course names in the order they first appear, one per course however it
  /// was spelled (see [TimetableImport.sameCourse]).
  List<String> get subjects {
    final names = <String>[];
    for (final c in classes) {
      if (!names.any((n) => TimetableImport.sameCourse(n, c.subject))) {
        names.add(c.subject);
      }
    }
    return names;
  }
}

/// One class read from the AI's reply, not yet saved.
class ImportedClass {
  final int weekday;
  final int startMinute;
  final int endMinute;
  final String subject;
  final String? room;
  final bool isLab;

  const ImportedClass({
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
    required this.subject,
    this.room,
    this.isLab = false,
  });

  String get key => '$weekday|$startMinute|$endMinute|${subject.toLowerCase()}';
}
