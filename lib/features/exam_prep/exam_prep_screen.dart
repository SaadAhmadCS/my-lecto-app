import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/errors/error_messages.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/motion.dart';
import '../../shared/widgets/page_title.dart';
import '../../shared/widgets/primary_pill_button.dart';
import '../recording/data/local/recording_database.dart';
import '../subjects/data/subject_dao.dart';
import '../timetable/data/class_slot.dart';
import 'exam_prep_service.dart';

/// Get ready for a quiz or exam with the student's own AI.
///
/// Pick the course, the exam and the lectures it covers; Lecto packs their
/// notes, the teacher's exam hints and (optionally) transcripts with a prompt
/// asking the AI to prepare the student the way this teacher examines.
class ExamPrepScreen extends StatefulWidget {
  final String? subjectId;

  /// Preselect an announced exam by title (and date, "YYYY-MM-DD").
  final String? examTitle;
  final String? examDate;

  const ExamPrepScreen({
    super.key,
    this.subjectId,
    this.examTitle,
    this.examDate,
  });

  @override
  State<ExamPrepScreen> createState() => _ExamPrepScreenState();
}

/// Exams a student can name when the lectures announced none.
const _commonExams = ['Quiz', 'Midterm', 'Final exam'];

class _ExamPrepScreenState extends State<ExamPrepScreen> {
  late final SubjectDao _subjects = context.read<SubjectDao>();

  List<Map<String, dynamic>> _courses = const [];
  Map<String, dynamic>? _course;
  List<PrepLecture> _lectures = const [];
  List<PrepExam> _announced = const [];

  /// The announced exam picked, or null for [_customTitle].
  PrepExam? _exam;
  String _customTitle = _commonExams.first;
  final Set<String> _selected = {};
  bool _includeTranscripts = true;
  bool _isLoading = true;
  bool _isSharing = false;

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    final all = await _subjects.listSubjects();
    final courses = all
        .where((s) => s['id'] != RecordingDatabase.unsortedSubjectId)
        .toList();
    if (!mounted) return;

    var course = courses.isEmpty ? null : courses.first;
    for (final c in courses) {
      if (c['id'] == widget.subjectId) course = c;
    }
    // With nothing asked for, start on a course that has notes.
    if (widget.subjectId == null) {
      for (final c in courses) {
        final count =
            (c['_count'] as Map<String, dynamic>?)?['recordings'] as int? ?? 0;
        if (count > 0) {
          course = c;
          break;
        }
      }
    }
    setState(() => _courses = courses);
    if (course != null) {
      await _pickCourse(course, preselect: true);
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickCourse(
    Map<String, dynamic> course, {
    bool preselect = false,
  }) async {
    setState(() {
      _course = course;
      _isLoading = true;
    });
    final lectures = await ExamPrepService.lectures(course['id'] as String);
    final announced = ExamPrepService.announcedExams(lectures);
    if (!mounted || _course != course) return;

    PrepExam? exam;
    if (preselect && widget.examTitle != null) {
      for (final e in announced) {
        final sameDate =
            widget.examDate == null ||
            (e.date != null &&
                e.date!.toIso8601String().startsWith(widget.examDate!));
        if (e.title == widget.examTitle && sameDate) exam = e;
      }
    }
    // The next announced exam is the likeliest reason to be here.
    exam ??=
        announced.isEmpty ||
            (announced.first.date != null &&
                announced.first.date!.isBefore(_today))
        ? null
        : announced.first;

    setState(() {
      _lectures = lectures;
      _announced = announced;
      _exam = exam;
      _isLoading = false;
      _selectDefaultLectures();
      _includeTranscripts =
          ExamPrepService.wordCount(_chosen, includeTranscripts: true) <=
          ExamPrepService.largePackWords;
    });
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Every lecture with notes, up to the exam.
  void _selectDefaultLectures() {
    final until = _exam?.date;
    _selected
      ..clear()
      ..addAll([
        for (final l in _lectures)
          if (l.hasNotes &&
              (until == null ||
                  !l.recordedAt.isAfter(until.add(const Duration(days: 1)))))
            l.id,
      ]);
  }

  void _selectSince(PrepExam previous) {
    final from = previous.date!;
    final until = _exam?.date;
    setState(() {
      _selected
        ..clear()
        ..addAll([
          for (final l in _lectures)
            if (l.hasNotes &&
                l.recordedAt.isAfter(from) &&
                (until == null ||
                    !l.recordedAt.isAfter(until.add(const Duration(days: 1)))))
              l.id,
        ]);
    });
  }

  List<PrepLecture> get _chosen =>
      _lectures.where((l) => _selected.contains(l.id)).toList();

  PrepExam get _target => _exam ?? PrepExam(title: _customTitle);

  Future<void> _send() async {
    final course = _course;
    if (course == null || _selected.isEmpty || _isSharing) return;
    setState(() => _isSharing = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final name = course['name'] as String? ?? 'Course';
      final teacher = course['teacher'] as String?;
      final chosen = _chosen;
      await ExamPrepService.share(
        course: name,
        exam: _target,
        pack: ExamPrepService.buildPack(
          course: name,
          exam: _target,
          lectures: chosen,
          includeTranscripts: _includeTranscripts,
          teacher: teacher,
        ),
        prompt: ExamPrepService.buildPrompt(
          course: name,
          exam: _target,
          lectureCount: chosen.length,
          includeTranscripts: _includeTranscripts,
          teacher: teacher,
          isLab: course['isLab'] == true,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(ErrorMessages.from(e, action: 'share the notes')),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chosen = _chosen;
    final hints = chosen.fold<int>(0, (sum, l) => sum + l.examHintCount);
    final words = ExamPrepService.wordCount(
      chosen,
      includeTranscripts: _includeTranscripts,
    );
    final withNotes = _lectures.where((l) => l.hasNotes).length;
    final previous = _exam == null
        ? null
        : ExamPrepService.previousExam(_announced, _exam!);

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: PrimaryPillButton(
            label: _isSharing
                ? 'Opening…'
                : chosen.isEmpty
                ? 'Pick at least one lecture'
                : 'Send ${chosen.length} lecture${chosen.length == 1 ? '' : 's'} to my AI',
            icon: Icons.auto_awesome_rounded,
            onPressed: chosen.isEmpty || _isSharing ? null : _send,
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            const PageTitle(
              title: 'Exam prep',
              subtitle: 'Your AI studies every lecture and preps you',
              showBack: true,
            ),
            const SizedBox(height: 18),
            const _Hero(),
            const SizedBox(height: 24),
            if (_courses.isEmpty && !_isLoading)
              const _Empty(
                icon: Icons.folder_off_outlined,
                title: 'No courses yet',
                body: 'Add your subjects and record a few lectures first.',
              )
            else ...[
              const _Label('Course'),
              _CourseStrip(
                courses: _courses,
                selectedId: _course?['id'] as String?,
                onPick: _pickCourse,
              ),
              const SizedBox(height: 24),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                )
              else if (withNotes == 0)
                const _Empty(
                  icon: Icons.notes_rounded,
                  title: 'No notes in this course yet',
                  body:
                      'Record its lectures and paste back your AI\'s notes — '
                      'then they can be sent here to prepare you.',
                )
              else ...[
                const _Label('Preparing for'),
                _ExamPicker(
                  announced: _announced,
                  selected: _exam,
                  customTitle: _customTitle,
                  today: _today,
                  onAnnounced: (exam) => setState(() {
                    _exam = exam;
                    _selectDefaultLectures();
                  }),
                  onCustom: (title) => setState(() {
                    _exam = null;
                    _customTitle = title;
                    _selectDefaultLectures();
                  }),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Expanded(child: _Label('Lectures it covers')),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${chosen.length} of $withNotes',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _QuickChip(
                      label: 'All with notes',
                      onTap: () => setState(_selectDefaultLectures),
                    ),
                    if (previous != null)
                      _QuickChip(
                        label: 'Since ${previous.title}',
                        onTap: () => _selectSince(previous),
                      ),
                    _QuickChip(
                      label: 'None',
                      onTap: () => setState(_selected.clear),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final lecture in _lectures.reversed)
                  _LectureRow(
                    lecture: lecture,
                    selected: _selected.contains(lecture.id),
                    onChanged: lecture.hasNotes
                        ? (on) => setState(() {
                            on
                                ? _selected.add(lecture.id)
                                : _selected.remove(lecture.id);
                          })
                        : null,
                  ),
                // Only lectures from before study guides have transcripts.
                if (chosen.any((l) => l.fullTranscript != null)) ...[
                  const SizedBox(height: 16),
                  _TranscriptSwitch(
                    value: _includeTranscripts,
                    onChanged: (v) => setState(() => _includeTranscripts = v),
                  ),
                ],
                const SizedBox(height: 16),
                _PackSummary(
                  lectures: chosen.length,
                  hints: hints,
                  words: words,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Pieces ────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: AppColors.navBar,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -4,
            bottom: -8,
            child: SvgPicture.asset(
              'assets/images/home_quizzes.svg',
              width: 124,
              height: 124,
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 124, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.tips_and_updates_rounded,
                      size: 15,
                      color: Color(0xFFFFC857),
                    ),
                    SizedBox(width: 6),
                    Text(
                      'KNOW WHAT\'S COMING',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                        color: Color(0xFFFFC857),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Text(
                  'Every hint, warning and topic your teacher gave — '
                  'turned into a prep plan and a practice paper.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textOnPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseStrip extends StatelessWidget {
  final List<Map<String, dynamic>> courses;
  final String? selectedId;
  final ValueChanged<Map<String, dynamic>> onPick;

  const _CourseStrip({
    required this.courses,
    required this.selectedId,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: courses.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final course = courses[i];
          final selected = course['id'] == selectedId;
          final color = AppColors.fromHex(course['color'] as String?);
          final ink = Color.lerp(color, Colors.black, 0.35)!;
          return Material(
            color: selected ? color : color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(100),
            child: InkWell(
              borderRadius: BorderRadius.circular(100),
              onTap: () {
                Feel.select();
                onPick(course);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    if (course['isLab'] == true) ...[
                      Icon(
                        ClassKindIcon.labIcon,
                        size: 16,
                        color: selected ? AppColors.textOnPrimary : ink,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      course['name'] as String? ?? '',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: selected ? AppColors.textOnPrimary : ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ExamPicker extends StatelessWidget {
  final List<PrepExam> announced;
  final PrepExam? selected;
  final String customTitle;
  final DateTime today;
  final ValueChanged<PrepExam> onAnnounced;
  final ValueChanged<String> onCustom;

  const _ExamPicker({
    required this.announced,
    required this.selected,
    required this.customTitle,
    required this.today,
    required this.onAnnounced,
    required this.onCustom,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final exam in announced)
          _ExamTile(
            exam: exam,
            today: today,
            selected: selected?.key == exam.key,
            onTap: () => onAnnounced(exam),
          ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final title in _commonExams)
                ChoiceChip(
                  label: Text(title),
                  selected: selected == null && customTitle == title,
                  onSelected: (_) {
                    Feel.select();
                    onCustom(title);
                  },
                  selectedColor: AppColors.inkSky,
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: selected == null && customTitle == title
                        ? AppColors.textOnPrimary
                        : AppColors.inkSky,
                  ),
                  backgroundColor: AppColors.tintSky,
                  side: BorderSide.none,
                  showCheckmark: false,
                  shape: const StadiumBorder(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExamTile extends StatelessWidget {
  final PrepExam exam;
  final DateTime today;
  final bool selected;
  final VoidCallback onTap;

  const _ExamTile({
    required this.exam,
    required this.today,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final date = exam.date;
    final days = date == null
        ? null
        : DateTime(date.year, date.month, date.day).difference(today).inDays;
    final when = switch (days) {
      null => 'No date given',
      < 0 => 'Was ${-days} day${days == -1 ? '' : 's'} ago',
      0 => 'Today',
      1 => 'Tomorrow',
      _ => 'In $days days',
    };
    final past = days != null && days < 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AppColors.tintSky : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? AppColors.inkSky : AppColors.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.inkSky
                        : AppColors.tintSky.withValues(alpha: past ? 0.5 : 1),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.quiz_rounded,
                    size: 21,
                    color: selected
                        ? AppColors.textOnPrimary
                        : AppColors.inkSky.withValues(alpha: past ? 0.5 : 1),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exam.title,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: past
                              ? AppColors.textSecondary
                              : AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        [when, ?exam.details].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      labelStyle: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
      ),
      backgroundColor: AppColors.surface,
      side: const BorderSide(color: AppColors.border),
      shape: const StadiumBorder(),
    );
  }
}

class _LectureRow extends StatelessWidget {
  final PrepLecture lecture;
  final bool selected;
  final ValueChanged<bool>? onChanged;

  const _LectureRow({
    required this.lecture,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final d = lecture.recordedAt;
    final date = MaterialLocalizations.of(context).formatShortMonthDay(d);
    final hints = lecture.examHintCount;
    final detail = !enabled
        ? 'Needs your AI first'
        : [
            date,
            if (hints > 0) '$hints exam hint${hints == 1 ? '' : 's'}',
            if (lecture.fullTranscript != null) 'transcript',
          ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled
              ? () {
                  Feel.select();
                  onChanged!(!selected);
                }
              : null,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lecture.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: enabled
                              ? AppColors.textPrimary
                              : AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (hints > 0) ...[
                            const Icon(
                              Icons.tips_and_updates_rounded,
                              size: 13,
                              color: Color(0xFFB7791F),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(
                              detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: enabled
                                    ? AppColors.textSecondary
                                    : AppColors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Checkbox(
                  value: selected && enabled,
                  onChanged: enabled ? (v) => onChanged!(v ?? false) : null,
                  activeColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TranscriptSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _TranscriptSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppColors.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        secondary: const Icon(
          Icons.record_voice_over_outlined,
          color: AppColors.textPrimary,
        ),
        title: const Text(
          'Include transcripts',
          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
        ),
        subtitle: const Text(
          'The teacher\'s exact words — catches hints the notes missed',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _PackSummary extends StatelessWidget {
  final int lectures;
  final int hints;
  final int words;

  const _PackSummary({
    required this.lectures,
    required this.hints,
    required this.words,
  });

  @override
  Widget build(BuildContext context) {
    final large = words > ExamPrepService.largePackWords;
    final thousands = (words / 1000).toStringAsFixed(words < 10000 ? 1 : 0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: large ? AppColors.warningBg : AppColors.tintMint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            large ? Icons.warning_amber_rounded : Icons.inventory_2_outlined,
            size: 20,
            color: large ? AppColors.warning : AppColors.inkMint,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              large
                  ? 'About ${thousands}k words — some AI apps may cut this '
                        'short. Turn off transcripts or pick fewer lectures.'
                  : '$lectures lecture${lectures == 1 ? '' : 's'} · '
                        '$hints exam hint${hints == 1 ? '' : 's'} · '
                        'about ${thousands}k words. Sent as a text file with '
                        'the prep instructions.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: large ? AppColors.warning : AppColors.inkMint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;

  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _Empty({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 30, color: AppColors.textMuted),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
