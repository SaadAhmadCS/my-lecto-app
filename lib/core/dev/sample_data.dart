import '../../features/recording/data/local/recording_database.dart';

/// Fills the app with believable lectures for testing the UI.
///
/// Debug builds only — Settings hides the entry point in release. Every row
/// is keyed with [_prefix], so [clear] removes exactly what [seed] added and
/// never touches real recordings.
///
/// Dates are relative to today, so tasks, deadlines and the streak always look
/// current. Sample lectures have notes but no audio: sharing one to an AI app
/// reports that there is nothing to send.
class SampleData {
  SampleData._();

  static const _prefix = 'sample-';

  static const _subjects = [
    ('calculus', 'Calculus II', '#5244e3'),
    ('physics', 'Physics', '#2e78e6'),
    ('orgchem', 'Organic Chemistry', '#128b62'),
    ('dsa', 'Data Structures', '#f16743'),
    ('english', 'English Literature', '#d946a6'),
  ];

  static Future<bool> isLoaded() async {
    final db = await RecordingDatabase.database;
    final rows = await db.rawQuery(
      "SELECT 1 FROM recordings WHERE id LIKE '$_prefix%' LIMIT 1",
    );
    return rows.isNotEmpty;
  }

  static Future<void> seed() async {
    await clear();
    final db = await RecordingDatabase.database;
    final now = DateTime.now();

    await db.transaction((txn) async {
      for (final (id, name, color) in _subjects) {
        final at = now.subtract(const Duration(days: 30)).toIso8601String();
        await txn.insert('subjects', {
          'id': '$_prefix$id',
          'name': name,
          'color': color,
          'created_at': at,
          'updated_at': at,
        });
      }

      for (final lecture in _lectures(now)) {
        final created = now
            .subtract(Duration(days: lecture.daysAgo))
            .copyWith(hour: lecture.hour, minute: 10);
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
          'notes_updated_at':
              lecture.notes == null ? null : created.toIso8601String(),
        });
      }
    });
  }

  static Future<void> clear() async {
    final db = await RecordingDatabase.database;
    await db.transaction((txn) async {
      for (final table in ['photos', 'audio_chunks']) {
        await txn.delete(table, where: "recording_id LIKE '$_prefix%'");
      }
      await txn.delete('recordings', where: "id LIKE '$_prefix%'");
      await txn.delete('subjects', where: "id LIKE '$_prefix%'");
    });
  }

  static String _day(DateTime now, int offset) {
    final d = DateTime(now.year, now.month, now.day).add(Duration(days: offset));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  static List<_Lecture> _lectures(DateTime now) {
    String d(int offset) => _day(now, offset);

    return [
      _Lecture(
        id: 'calc-1',
        subject: 'calculus',
        title: 'Integration by parts',
        daysAgo: 0,
        hour: 9,
        minutes: 52,
        notes: '''
## Summary
Integration by parts turns the integral of a product into something easier, using the product rule in reverse. The lecture worked through choosing u and dv with the LIATE rule and finished with repeated application for e^x sin x.

## Key Concepts
- **Integration by parts** — ∫u dv = uv − ∫v du, the product rule run backwards.
- **LIATE** — pick u in the order Logarithmic, Inverse trig, Algebraic, Trig, Exponential.
- **Cyclic integrals** — applying the rule twice can return the original integral, which you then solve for algebraically.
- **Tabular method** — a shortcut when u differentiates to zero after a few steps.

## Tasks
- [ ] Finish problem set 4, questions 1–12
- [ ] Rework the e^x sin x example without notes
- [x] Read section 7.1

## Deadlines
- ${d(0)} — Problem set 4 due
- ${d(3)} — Quiz on integration by parts
''',
      ),
      _Lecture(
        id: 'phys-1',
        subject: 'physics',
        title: 'Newton\'s laws in rotating frames',
        daysAgo: 1,
        hour: 11,
        minutes: 75,
        notes: '''
## Summary
Extended Newton's laws to non-inertial, rotating frames by introducing fictitious forces. Covered centrifugal and Coriolis forces with examples from weather systems and a turntable demo.

## Key Concepts
- **Inertial frame** — a frame where Newton's first law holds without extra forces.
- **Centrifugal force** — the outward fictitious force felt in a rotating frame, mω²r.
- **Coriolis force** — −2m(ω × v), deflects moving objects sideways in a rotating frame.
- **Foucault pendulum** — its plane of swing rotates, showing Earth's rotation.

## Tasks
- [ ] Lab report draft for the turntable experiment
- [ ] Watch the Foucault pendulum video on the course page

## Deadlines
- ${d(0)} — Lab report draft
- ${d(4)} — Lab report 3 final submission
''',
      ),
      _Lecture(
        id: 'chem-1',
        subject: 'orgchem',
        title: 'SN1 vs SN2 reactions',
        daysAgo: 2,
        hour: 14,
        minutes: 24,
        notes: '''
## Summary
Compared the two nucleophilic substitution mechanisms: SN2 is one concerted step with inversion, SN1 goes through a carbocation and gives a racemic mix.

## Key Concepts
- **SN2** — bimolecular, one step, backside attack, inversion of configuration.
- **SN1** — unimolecular, carbocation intermediate, favoured by tertiary substrates.
- **Leaving group** — weaker bases leave more easily; I⁻ > Br⁻ > Cl⁻.
- **Solvent effects** — polar protic favours SN1, polar aprotic favours SN2.

## Tasks
- [x] Read chapter 7
- [ ] Mechanism practice sheet

## Deadlines
- ${d(6)} — Midterm exam
''',
        transcript: '''
Okay, let's get started. Last time we finished with alkyl halides, and today we're asking what happens when a nucleophile comes along.

There are two ways this can go. In the first, the nucleophile attacks at the same time as the leaving group leaves. We call that SN2 — substitution, nucleophilic, bimolecular — because the rate depends on both the substrate and the nucleophile.

The second way is stepwise. The leaving group goes first, you get a carbocation, and then the nucleophile comes in. That's SN1, and its rate depends only on the substrate.

So which one happens? Look at the substrate first. Methyl and primary go SN2. Tertiary goes SN1, because the carbocation is stable and the back is too crowded to attack. Secondary is the awkward one — it depends on the solvent and the nucleophile.
''',
      ),
      _Lecture(
        id: 'dsa-1',
        subject: 'dsa',
        title: 'Hash tables and collisions',
        daysAgo: 3,
        hour: 10,
        minutes: 68,
        notes: '''
## Summary
How hash tables get O(1) average lookups, what happens when two keys land in the same bucket, and why the load factor decides when to resize.

## Key Concepts
- **Hash function** — maps a key to a bucket index; should spread keys evenly.
- **Chaining** — each bucket holds a list of entries that collided.
- **Open addressing** — on a collision, probe for the next free slot.
- **Load factor** — entries ÷ buckets; resize when it passes about 0.75.

## Tasks
- [ ] Implement a hash map with chaining in Java
- [ ] Assignment 2: benchmark chaining vs linear probing

## Deadlines
- ${d(5)} — Assignment 2 submission
- ${d(10)} — Quiz 2 on hashing and trees
''',
      ),
      _Lecture(
        id: 'eng-1',
        subject: 'english',
        title: 'Symbolism in The Great Gatsby',
        daysAgo: 4,
        hour: 13,
        minutes: 55,
        notes: '''
## Summary
Discussed the green light, the valley of ashes and Dr T. J. Eckleburg's eyes as symbols of longing, moral decay and a watching, absent God.

## Key Concepts
- **The green light** — Gatsby's hope and the unreachable past.
- **Valley of ashes** — the grey cost of the wealthy's carelessness.
- **Eckleburg's eyes** — a billboard read as a god looking down on a godless world.

## Tasks
- [ ] Essay outline on one symbol, 500 words

## Deadlines
- ${d(8)} — Essay submission
''',
      ),
      _Lecture(
        id: 'calc-0',
        subject: 'calculus',
        title: 'Substitution rule review',
        daysAgo: 5,
        hour: 9,
        minutes: 48,
        notes: '''
## Summary
Reviewed u-substitution for definite and indefinite integrals, including changing the limits instead of substituting back.

## Key Concepts
- **u-substitution** — reverse of the chain rule; set u to the inner function.
- **Changing limits** — convert the bounds to u-values and never substitute back.

## Tasks
- [x] Problem set 3
''',
      ),
      // Two still waiting for notes, for the "needs your AI" strip.
      _Lecture(
        id: 'phys-2',
        subject: 'physics',
        title: 'Angular momentum',
        daysAgo: 0,
        hour: 15,
        minutes: 41,
      ),
      _Lecture(
        id: 'dsa-2',
        subject: 'dsa',
        title: 'Binary search trees',
        daysAgo: 1,
        hour: 16,
        minutes: 12,
      ),
    ];
  }
}

class _Lecture {
  final String id;
  final String subject;
  final String title;
  final int daysAgo;
  final int hour;
  final int minutes;
  final String? notes;
  final String? transcript;

  const _Lecture({
    required this.id,
    required this.subject,
    required this.title,
    required this.daysAgo,
    required this.hour,
    required this.minutes,
    this.notes,
    this.transcript,
  });
}
