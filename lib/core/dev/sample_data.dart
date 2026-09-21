import 'package:sqflite/sqflite.dart';

import '../../features/recording/data/local/recording_database.dart';

/// Fills the app with believable lectures for testing the UI.
///
/// Debug builds only — Settings hides the entry point in release. Every row
/// is keyed with [_prefix], so [clear] removes exactly what [seed] added and
/// never touches real recordings.
///
/// Modelled on a real BCS-6A timetable: its six courses, its weekly classes
/// (rooms, labs and a free Thursday included) and a lecture from each. Lecture
/// dates follow the timetable, and deadlines are relative to today, so tasks,
/// quizzes and reminders always look current. Sample lectures have notes but
/// no audio: sharing one to an AI app reports that there is nothing to send.
class SampleData {
  SampleData._();

  static const _prefix = 'sample-';

  static const _subjects = [
    ('la', 'Linear Algebra', '#5244e3'),
    ('cyber', 'Intro to Cyber Security', '#dc2626'),
    ('toa', 'Theory of Automata', '#7c3aed'),
    ('arch', 'Intro to Computer Architecture', '#0e7490'),
    ('ml', 'Machine Learning Fundamentals', '#128b62'),
    ('db', 'Advanced Database Systems', '#2e78e6'),
  ];

  /// (subject, weekday, start, end, room, lab)
  static const _timetable = [
    ('la', DateTime.monday, '08:30', '10:00', 'G-09', false),
    ('cyber', DateTime.monday, '11:00', '13:00', 'G-08', false),
    ('la', DateTime.monday, '13:30', '15:00', 'G-11', false),
    ('toa', DateTime.monday, '15:00', '16:30', 'F-02', false),
    ('arch', DateTime.tuesday, '09:00', '10:30', '504', true),
    ('ml', DateTime.tuesday, '11:00', '13:00', 'B-19', false),
    ('db', DateTime.tuesday, '13:30', '16:30', 'Lab-4', true),
    ('db', DateTime.wednesday, '08:30', '10:30', 'F-11', false),
    ('arch', DateTime.wednesday, '11:00', '13:00', 'G-01', false),
    ('ml', DateTime.wednesday, '13:30', '16:30', 'Lab-9', true),
    ('cyber', DateTime.friday, '08:30', '11:30', 'Lab-2', true),
    ('arch', DateTime.friday, '11:30', '13:00', 'Lab-9', true),
    ('toa', DateTime.friday, '15:00', '16:30', 'F-05', false),
  ];

  static Future<bool> isLoaded() async {
    final db = await RecordingDatabase.database;
    final rows = await db.rawQuery(
      "SELECT 1 FROM subjects WHERE id LIKE '$_prefix%' LIMIT 1",
    );
    return rows.isNotEmpty;
  }

  static Future<void> seed() async {
    await clear();
    final db = await RecordingDatabase.database;
    final now = DateTime.now();
    final stamp = now.subtract(const Duration(days: 30)).toIso8601String();

    await db.transaction((txn) async {
      // A sample course the student's own timetable adopted survived the last
      // clear; keep it as it is.
      for (final (id, name, color) in _subjects) {
        await txn.insert('subjects', {
          'id': '$_prefix$id',
          'name': name,
          'color': color,
          'created_at': stamp,
          'updated_at': stamp,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      // Never pile a sample week on top of a timetable the student set up.
      final hasTimetable = (await txn.query(
        'timetable_slots',
        limit: 1,
      )).isNotEmpty;
      if (!hasTimetable) {
        var n = 0;
        for (final (subject, weekday, start, end, room, lab) in _timetable) {
          await txn.insert('timetable_slots', {
            'id': '${_prefix}slot-${n++}',
            'subject_id': '$_prefix$subject',
            'weekday': weekday,
            'start_minute': _minutes(start),
            'end_minute': _minutes(end),
            'room': room,
            'is_lab': lab ? 1 : 0,
            'remind': 1,
            'created_at': stamp,
          });
        }
      }

      for (final lecture in _lectures(now)) {
        final created = _lastClass(now, lecture.weekday, lecture.start);
        await txn.insert('recordings', {
          'id': '$_prefix${lecture.id}',
          'subject_id': '$_prefix${lecture.subject}',
          'title': lecture.title,
          'status': 'completed',
          'total_duration_ms': lecture.minutes * 60 * 1000,
          'created_at': created.toIso8601String(),
          'updated_at': created.toIso8601String(),
          'notes_markdown': lecture.notes,
          'transcript_markdown': lecture.transcript,
          'notes_updated_at': lecture.notes == null
              ? null
              : created.toIso8601String(),
        });
      }
    });
  }

  /// Remove the sample lectures and whatever else is still only sample.
  ///
  /// A sample course the student has since put their own classes or
  /// recordings in is theirs now, and stays — as do those classes.
  static Future<void> clear() async {
    final db = await RecordingDatabase.database;
    await db.transaction((txn) async {
      for (final table in ['photos', 'audio_chunks']) {
        await txn.delete(table, where: "recording_id LIKE '$_prefix%'");
      }
      await txn.delete('recordings', where: "id LIKE '$_prefix%'");
      await txn.delete('timetable_slots', where: "id LIKE '$_prefix%'");
      await txn.delete(
        'subjects',
        where:
            "id LIKE '$_prefix%' "
            'AND id NOT IN (SELECT subject_id FROM timetable_slots) '
            'AND id NOT IN (SELECT subject_id FROM recordings)',
      );
    });
  }

  static int _minutes(String hhmm) {
    final parts = hhmm.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  /// The most recent time this class met: today if it has started already,
  /// otherwise the same weekday last week.
  static DateTime _lastClass(DateTime now, int weekday, String start) {
    final minute = _minutes(start);
    var date = DateTime(
      now.year,
      now.month,
      now.day,
      minute ~/ 60,
      minute % 60 + 10,
    );
    while (date.weekday != weekday || date.isAfter(now)) {
      date = DateTime(
        date.year,
        date.month,
        date.day - 1,
        date.hour,
        date.minute,
      );
    }
    return date;
  }

  static String _day(DateTime now, int offset) {
    final d = DateTime(now.year, now.month, now.day + offset);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  static List<_Lecture> _lectures(DateTime now) {
    String d(int offset) => _day(now, offset);

    return [
      _Lecture(
        id: 'la-1',
        subject: 'la',
        weekday: DateTime.monday,
        start: '08:30',
        title: 'Eigenvalues and eigenvectors',
        minutes: 86,
        notes:
            '''
## Summary
Introduced eigenvalues and eigenvectors as the directions a matrix only stretches. Worked through finding them from the characteristic polynomial, then used them to diagonalise a 2×2 matrix.

## Key Concepts
- **Eigenvector** — a non-zero vector v with Av = λv; A only scales it.
- **Eigenvalue** — the scale factor λ for that eigenvector.
- **Characteristic polynomial** — det(A − λI) = 0; its roots are the eigenvalues.
- **Diagonalisation** — A = PDP⁻¹, with eigenvectors in P and eigenvalues on D's diagonal.

## Important
- Quiz 2 is closed book, but one A4 formula sheet is allowed.
- Office hours move to Thursday 2–4 pm this week only.

## Assignments
- [ ] Problem set 3 — due ${d(0)} — questions 1–10, handwritten, submit on the LMS as one PDF — 5% of the grade

## Quizzes & Exams
- ${d(7)} — Quiz 2 — eigenvalues, eigenvectors and diagonalisation — 20 minutes, in class

## Tasks
- [ ] Diagonalise the 3×3 example from the board
- [x] Read section 5.1
''',
      ),
      _Lecture(
        id: 'toa-1',
        subject: 'toa',
        weekday: DateTime.friday,
        start: '15:00',
        title: 'From NFA to DFA',
        minutes: 84,
        notes:
            '''
## Summary
Showed that every NFA has an equivalent DFA using the subset construction, and worked an example that grew from 3 states to 5. Ended on why ε-closures are needed first.

## Key Concepts
- **NFA** — may have several moves, or none, on a symbol; accepts if any path accepts.
- **Subset construction** — each DFA state is a set of NFA states.
- **ε-closure** — every state reachable on empty moves alone.
- **State explosion** — n NFA states can need up to 2ⁿ DFA states.

## Important
- "The subset construction will definitely be on the final" — the lecturer said this twice.

## Assignments
- [ ] Assignment 2 — due ${d(10)} — convert and minimise the automata on sheet 4, groups of two allowed

## Quizzes & Exams
- ${d(3)} — Quiz 1 — finite automata, NFA to DFA — first 15 minutes of class

## Tasks
- [ ] Convert the three NFAs on sheet 4 to DFAs
- [ ] Minimise the result of question 2
''',
      ),
      _Lecture(
        id: 'db-1',
        subject: 'db',
        weekday: DateTime.wednesday,
        start: '08:30',
        title: 'Indexing with B+ trees',
        minutes: 112,
        notes:
            '''
## Summary
Covered why indexes speed up lookups, how a B+ tree keeps every leaf at the same depth, and what splits and merges do on insert and delete.

## Key Concepts
- **Index** — a separate structure that finds rows without scanning the table.
- **B+ tree** — balanced tree where data pointers live only in the linked leaves.
- **Fan-out** — children per node; high fan-out keeps the tree shallow.
- **Clustered index** — the table is stored in index order; only one per table.

## Tasks
- [ ] Insert keys 5–40 into an order-4 B+ tree by hand
- [x] Read chapter 14

## Deadlines
- ${d(9)} — Midterm exam
''',
      ),
      _Lecture(
        id: 'arch-1',
        subject: 'arch',
        weekday: DateTime.wednesday,
        start: '11:00',
        title: 'Pipelining and hazards',
        minutes: 24,
        notes:
            '''
## Summary
Split instruction execution into five stages to overlap instructions, then looked at the three hazards that stall a pipeline and how forwarding fixes most data hazards.

## Key Concepts
- **Pipelining** — overlapping fetch, decode, execute, memory and write-back.
- **Data hazard** — an instruction needs a result that is not written yet.
- **Forwarding** — passing a result straight from one stage to the next.
- **Control hazard** — the pipeline does not yet know which way a branch goes.

## Important
- Lab moves to Room 504 from next week.
- Bring the MIPS simulator installed on your laptop to every lab.

## Assignments
- [ ] Lab report 2 — due ${d(5)} — MIPS simulator results, submit on the LMS — 10 marks

## Tasks
- [ ] Draw the pipeline diagram for the 6-instruction example
''',
        transcript: '''
Right, let's start. Last week an instruction ran from start to finish before the next one began. Today we stop doing that.

Think of a laundry. You don't wait for one load to dry before you start washing the next. Same idea here: five stages — fetch, decode, execute, memory, write-back — and a new instruction enters every cycle.

But there's a catch. Say the second instruction needs the result of the first. The first hasn't written it back yet. That's a data hazard, and without help the pipeline has to stall.

The help is forwarding. The result exists at the end of execute, so we pass it straight across instead of waiting for write-back. That fixes most cases. Loads are the exception — we'll see why next week.
''',
      ),
      _Lecture(
        id: 'ml-1',
        subject: 'ml',
        weekday: DateTime.tuesday,
        start: '11:00',
        title: 'Linear regression and gradient descent',
        minutes: 108,
        notes:
            '''
## Summary
Fitted a line by minimising mean squared error, first in closed form and then with gradient descent. Spent time on how the learning rate decides whether training converges.

## Key Concepts
- **Linear regression** — predicts y as a weighted sum of the features plus a bias.
- **Mean squared error** — the average squared gap between prediction and truth.
- **Gradient descent** — step the weights against the gradient of the loss.
- **Learning rate** — too high overshoots and diverges; too low crawls.

## Assignments
- [ ] Assignment 1 — due ${d(4)} — implement gradient descent in NumPy, submit the notebook — 10% of the grade

## Tasks
- [ ] Plot loss against iterations for three learning rates
''',
      ),
      _Lecture(
        id: 'cyber-1',
        subject: 'cyber',
        weekday: DateTime.monday,
        start: '11:00',
        title: 'The CIA triad and threat models',
        minutes: 104,
        notes: '''
## Summary
Defined security through confidentiality, integrity and availability, then built a simple threat model for a university portal: assets, attackers and likely attacks.

## Key Concepts
- **Confidentiality** — only the right people can read it.
- **Integrity** — nobody can change it without it being noticed.
- **Availability** — it is there when it is needed.
- **Threat model** — what you protect, from whom, and how they would attack.

## Tasks
- [ ] Write a one-page threat model for your bank's app
''',
      ),
      // Two still waiting for notes, for the "needs your AI" strip.
      _Lecture(
        id: 'ml-2',
        subject: 'ml',
        weekday: DateTime.wednesday,
        start: '13:30',
        title: 'Lab: scikit-learn pipelines',
        minutes: 162,
      ),
      _Lecture(
        id: 'cyber-2',
        subject: 'cyber',
        weekday: DateTime.friday,
        start: '08:30',
        title: 'Lab: packet capture with Wireshark',
        minutes: 171,
      ),
    ];
  }
}

class _Lecture {
  final String id;
  final String subject;

  /// The class it was recorded in, which sets its date.
  final int weekday;
  final String start;
  final String title;
  final int minutes;
  final String? notes;
  final String? transcript;

  const _Lecture({
    required this.id,
    required this.subject,
    required this.weekday,
    required this.start,
    required this.title,
    required this.minutes,
    this.notes,
    this.transcript,
  });
}
