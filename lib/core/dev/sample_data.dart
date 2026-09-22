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
            """
## Summary
Introduced eigenvalues and eigenvectors as the directions a matrix only stretches. Worked through finding them from the characteristic polynomial, then used them to diagonalise a 2×2 matrix.

## Important
- "Quiz 2 is closed book, but you may bring one A4 formula sheet." — [0:04:12]
- Office hours move to Thursday 2–4 pm this week only. — [0:06:40]

## Exam Hints
- "Diagonalisation will definitely come in the final — every year." — [0:58:30]
- "Most of you lose marks by forgetting to check that the eigenvector is non-zero." — [1:12:05]
- He marks the working, not the answer: show the characteristic polynomial. — [1:14:20]

## Assignments
- [ ] Problem set 3 — due ${d(2)} — "questions 1 to 10, handwritten, one PDF on the LMS" — 5% of the grade — [1:21:40]

## Quizzes & Exams
- ${d(7)} — Quiz 2 — eigenvalues, eigenvectors and diagonalisation — 20 minutes, in class — [0:03:55]

## Tasks
- [ ] Diagonalise the 3×3 example from the board — [1:18:10]
- [x] Read section 5.1 — [1:19:02]

## Study Guide
### What an eigenvector is
- A matrix usually rotates and stretches a vector. For a few special directions it only stretches: those are the eigenvectors.
- Formally: a non-zero vector v with Av = λv. The number λ is the eigenvalue — how much that direction is stretched.
- Negative λ means the direction flips; λ = 1 means the direction is untouched.

### Finding them by hand
- Move everything to one side: (A − λI)v = 0. A non-zero v exists only when A − λI squashes space flat, so det(A − λI) = 0.
- That determinant is the characteristic polynomial. Its roots are the eigenvalues.
- Worked on the board with A = [[4, 1], [2, 3]]: det = (4 − λ)(3 − λ) − 2 = λ² − 7λ + 10, so λ = 5 and λ = 2.
- Substitute each λ back and solve for v. For λ = 5 the rows both give 2x = y, so v = (1, 2) — any multiple works.

### Diagonalisation
- Put the eigenvectors in the columns of P and the eigenvalues down the diagonal of D. Then A = PDP⁻¹.
- Why it matters: A^n = PD^nP⁻¹, and taking a power of a diagonal matrix is just taking powers of the numbers on it.
- It only works when there are enough independent eigenvectors. A repeated eigenvalue can fail this, and that is the case the exam likes.

## Key Concepts
- **Eigenvector** — a non-zero vector v with Av = λv; A only scales it.
- **Eigenvalue** — the scale factor λ for that eigenvector.
- **Characteristic polynomial** — det(A − λI) = 0; its roots are the eigenvalues.
- **Diagonalisation** — A = PDP⁻¹, eigenvectors in P, eigenvalues on D.
""",
      ),
      _Lecture(
        id: 'db-1',
        subject: 'db',
        weekday: DateTime.tuesday,
        start: '13:30',
        title: 'Lab: the aggregation pipeline',
        minutes: 140,
        notes:
            """
## Summary
Built aggregation pipelines against a live cluster: matching, unwinding arrays, grouping with accumulators, then shaping the output. Ended with a count of tutorials per author.

## Important
- "The manual is in the shared folder as ATP Labs 3 — don't use last year's." — [0:02:30]
- Write every key in quotes, or spaces in field names will break the pipeline later. — [0:41:15]
- A paused cluster has to be resumed by hand before anything runs. — [0:08:05]

## Exam Hints
- "In the viva I will ask you to explain a pipeline stage by stage." — [1:52:10]
- "\$unwind before \$group — the other way round is the mistake I see every semester." — [1:10:44]

## Assignments
- [ ] Lab report 3 — due ${d(5)} — "screenshots of each query and its output, submitted as one PDF" — 10% — [2:04:30]

## Quizzes & Exams
- ${d(12)} — Lab viva — everything from lab 1 to lab 4, at your own machine — [1:51:20]

## Tasks
- [ ] Rewrite today's last query using \$project — [2:01:10]

## Study Guide
### The pipeline idea
- An aggregation is a list of stages. Each stage takes documents in and passes documents out; the next stage only sees what the one before produced.
- The lecturer compared it to a UNIX shell pipeline: the pipe passes the result of one command straight into the next.

### \$match — filter first
- Put it first whenever you can: everything after it then works on fewer documents, and an index can still be used.
- Syntax as typed: db.students.aggregate([{ \$match: { semester: 1 } }])

### \$unwind — one document per array element
- A student with three skills becomes three documents, one per skill, so the skills can be grouped or counted.
- Syntax as typed: { \$unwind: "\$skills" } — the dollar sign marks a field path.

### \$group — collapse with an accumulator
- _id is the grouping key; every other field is an accumulator such as \$sum, \$avg or \$max.
- Counting per author, exactly as on screen: { \$group: { _id: "\$author", tutorials: { \$sum: 1 } } }

### \$project — shape the output
- Chooses which fields survive, and can rename or compute new ones. Useful last, once the numbers are right.

## Key Concepts
- **Pipeline** — stages in order, output of one feeding the next.
- **\$match** — filter documents, best placed first.
- **\$unwind** — flatten an array into one document per element.
- **\$group** — collapse documents by a key using accumulators.
- **\$project** — keep, rename or compute the fields you want.
""",
      ),
      _Lecture(
        id: 'ml-1',
        subject: 'ml',
        weekday: DateTime.wednesday,
        start: '11:00',
        title: 'Decision trees and splitting criteria',
        minutes: 118,
        notes:
            """
## Summary
Built a decision tree by hand: what the nodes mean, how entropy and information gain choose a split, and why the Gini index is often used instead. Finished on overfitting and the hyperparameters that hold a tree back.

## Important
- "Bring a calculator to the midterm — entropy by hand, no phones." — [0:11:20]
- The class on Friday moves to room B-19. — [0:03:02]

## Exam Hints
- "You will be given a small table and asked for the information gain of one split." — [1:31:40]
- "Everyone writes log base 10 by accident. It is log base 2." — [0:47:55]

## Quizzes & Exams
- ${d(9)} — Midterm — decision trees, entropy, overfitting — one hour, open notes — [0:10:50]

## Tasks
- [ ] Compute entropy for the weather dataset by hand — [1:36:15]
- [x] Install scikit-learn before the lab — [0:14:40]

## Study Guide
### The shape of a tree
- Root node: the whole dataset before any split. Internal nodes: a test on one attribute. Leaves: a class, with no further split.
- Building is recursive — split, then treat each side as a smaller problem.

### Entropy
- Entropy measures how mixed a node is. All one class → 0. A perfect 50/50 split of two classes → 1.
- Formula written on the board: H = −Σ p·log₂(p), summed over the classes in the node.
- Worked example: 9 yes and 5 no gives H = −(9/14)log₂(9/14) − (5/14)log₂(5/14) ≈ 0.94.

### Information gain
- Gain = entropy of the parent − the weighted average entropy of the children.
- The attribute with the highest gain is chosen for the split. The weighting is by how many rows fall into each branch.

### Gini index
- Gini = 1 − Σ p². Cheaper than entropy because there is no logarithm, and it usually picks the same split.

### Overfitting, and what holds it back
- An unrestricted tree grows until every leaf is pure, which memorises noise and fails on new data.
- max_depth, min_samples_split and min_samples_leaf stop it early; pruning cuts branches back afterwards.

## Key Concepts
- **Entropy** — how mixed a node is; 0 when pure.
- **Information gain** — the drop in entropy a split buys.
- **Gini index** — a cheaper impurity measure, 1 − Σ p².
- **Overfitting** — a tree that memorises the training data.
- **Pruning** — cutting branches back to generalise better.
""",
      ),
      _Lecture(
        id: 'toa-1',
        subject: 'toa',
        weekday: DateTime.friday,
        start: '15:00',
        title: 'From NFA to DFA',
        minutes: 84,
        notes: """
## Summary
Converted a non-deterministic automaton into a deterministic one by subset construction, then trimmed the unreachable states.

## Exam Hints
- "The conversion question is worth 15 marks and it is always on the paper." — [1:02:30]

## Tasks
- [ ] Convert the three-state NFA from the handout — [1:14:00]

## Study Guide
### Subset construction
- Each DFA state is a set of NFA states. Start from the ε-closure of the NFA's start state.
- For every input symbol, take the union of what each state in the set can reach, then close it again.
- Stop when no new sets appear. Any set containing an NFA accepting state is accepting.

### Trimming
- States no path can reach are dropped; they cannot change the language.

## Key Concepts
- **ε-closure** — every state reachable without reading input.
- **Subset construction** — a DFA state is a set of NFA states.
""",
      ),
      _Lecture(
        id: 'arch-1',
        subject: 'arch',
        weekday: DateTime.wednesday,
        start: '11:00',
        title: 'Pipelining and hazards',
        minutes: 24,
        notes: """
## Summary
A short session on the five-stage pipeline and the three kinds of hazard.

## Important
- "The lab on Friday is cancelled; we meet next week instead." — [0:01:40]

## Key Concepts
- **Structural hazard** — two instructions want the same hardware.
- **Data hazard** — an instruction needs a result that is not ready.
- **Control hazard** — the next instruction depends on a branch.
""",
      ),
      // Two with no notes yet, to show the "needs your AI" state.
      _Lecture(
        id: 'cyber-1',
        subject: 'cyber',
        weekday: DateTime.monday,
        start: '11:00',
        title: 'The CIA triad and threat models',
        minutes: 104,
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

  const _Lecture({
    required this.id,
    required this.subject,
    required this.weekday,
    required this.start,
    required this.title,
    required this.minutes,
    this.notes,
  });
}
