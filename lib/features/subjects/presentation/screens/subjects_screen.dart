import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/errors/error_messages.dart';
import '../../data/subject_dao.dart';
import '../../../timetable/services/class_reminder_service.dart';
import '../subject_format.dart';
import '../widgets/create_subject_sheet.dart';
import '../../../../shared/widgets/page_title.dart';
import '../../../recording/data/local/recording_database.dart';
import '../../../timetable/data/class_slot.dart';
import '../../../timetable/data/timetable_dao.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// Subjects screen — organize lectures by subject/course.
///
/// Shows a grid of user-created subjects with color-coded cards.
/// Supports creating new subjects and viewing recordings per subject.
class SubjectsScreen extends StatefulWidget {
  const SubjectsScreen({super.key});

  @override
  State<SubjectsScreen> createState() => _SubjectsScreenState();
}

class _SubjectsScreenState extends State<SubjectsScreen> {
  late final SubjectDao _subjectDao = context.read<SubjectDao>();
  List<Map<String, dynamic>> _subjects = [];
  bool _isLoading = true;
  bool _hasError = false;
  bool _isGridView = true;

  static const _viewModePrefKey = 'subjectsGridView';

  @override
  void initState() {
    super.initState();
    _loadViewMode();
    _loadSubjects();
  }

  Future<void> _loadViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    final isGrid = prefs.getBool(_viewModePrefKey);
    if (isGrid != null && mounted) setState(() => _isGridView = isGrid);
  }

  Future<void> _toggleViewMode() async {
    setState(() => _isGridView = !_isGridView);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_viewModePrefKey, _isGridView);
  }

  /// Each subject's soonest class, for the "next class" chip.
  Map<String, ClassSlot> _nextClass = const {};

  Future<void> _loadSubjects() async {
    // Keep what is on screen while refreshing; only a first load shows the
    // spinner.
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    final timetable = context.read<TimetableDao>();
    try {
      final subjects = await _subjectDao.listSubjects();
      final slots = await timetable.list();

      final now = DateTime.now();
      final next = <String, ClassSlot>{};
      for (final slot in slots) {
        final current = next[slot.subjectId];
        if (current == null ||
            slot.nextStart(now).isBefore(current.nextStart(now))) {
          next[slot.subjectId] = slot;
        }
      }

      if (mounted) {
        setState(() {
          _subjects = subjects;
          _nextClass = next;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  Future<void> _showCreateDialog() async {
    final created = await showCreateSubjectSheet(context);
    if (created != null) _loadSubjects();
  }

  Future<void> _showEditDialog(Map<String, dynamic> subject) async {
    final saved = await showSubjectSheet(context, existing: subject);
    if (saved != null) _loadSubjects();
  }

  /// Give a course its own lab folder and open it.
  Future<void> _addLab(Map<String, dynamic> subject) async {
    final labId = await _subjectDao.labFor(subject['id'] as String);
    if (!mounted) return;
    await context.push('/subjects/$labId');
    if (mounted) _loadSubjects();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(bottom: false, child: _buildBody()),
    );
  }

  /// Every real subject; Unsorted is shown separately, last.
  List<Map<String, dynamic>> get _courses => _subjects
      .where((s) => s['id'] != RecordingDatabase.unsortedSubjectId)
      .toList();

  Map<String, dynamic>? get _unsorted {
    for (final s in _subjects) {
      if (s['id'] == RecordingDatabase.unsortedSubjectId) return s;
    }
    return null;
  }

  Widget _buildBody() {
    if (_isLoading && _subjects.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Could not load subjects',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.base),
            OutlinedButton.icon(
              onPressed: _loadSubjects,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final courses = _courses;
    final labs = courses.where((s) => s['isLab'] == true).length;
    final theory = courses.length - labs;
    final unsorted = _unsorted;
    final lectures = _subjects.fold<int>(
      0,
      (sum, s) => sum + _recordingCount(s),
    );
    final totalMs = _subjects.fold<int>(
      0,
      (sum, s) => sum + ((s['totalDurationMs'] as int?) ?? 0),
    );

    final tiles = <Widget>[
      for (final subject in courses)
        _SubjectCard(
          subject: subject,
          nextClass: _nextClass[subject['id']],
          compact: !_isGridView,
          onTap: () => _openSubject(subject),
          onMore: () => _showSubjectMenu(subject),
        ),
      if (unsorted != null && _recordingCount(unsorted) > 0)
        _SubjectCard(
          subject: unsorted,
          compact: !_isGridView,
          isUnsorted: true,
          onTap: () => _openSubject(unsorted),
        ),
      _NewSubjectCard(compact: !_isGridView, onTap: _showCreateDialog),
    ];

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadSubjects,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 130),
        children: [
          PageTitle(
            title: 'Subjects',
            subtitle: courses.isEmpty
                ? 'Your courses, and every lecture in them'
                : [
                    '$theory course${theory == 1 ? '' : 's'}',
                    if (labs > 0) '$labs lab${labs == 1 ? '' : 's'}',
                    '$lectures lecture${lectures == 1 ? '' : 's'}',
                  ].join(' · '),
            trailing: _ViewToggle(isGrid: _isGridView, onTap: _toggleViewMode),
          ),
          const SizedBox(height: 18),
          _HoursHero(totalMs: totalMs, lectures: lectures),
          const SizedBox(height: 18),
          if (_isGridView)
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.9,
              children: tiles,
            )
          else
            for (final tile in tiles)
              Padding(padding: const EdgeInsets.only(bottom: 10), child: tile),
        ],
      ),
    );
  }

  static int _recordingCount(Map<String, dynamic> subject) =>
      (subject['_count'] as Map<String, dynamic>?)?['recordings'] as int? ?? 0;

  Future<void> _openSubject(Map<String, dynamic> subject) async {
    await context.push('/subjects/${subject['id']}');
    // Recording counts may have changed
    if (mounted) _loadSubjects();
  }

  void _showSubjectMenu(Map<String, dynamic> subject) {
    showModalBottomSheet(
      useRootNavigator: true,
      context: context,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(
                subject['isLab'] == true ? 'Edit lab' : 'Edit subject',
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _showEditDialog(subject);
              },
            ),
            if (subject['isLab'] != true &&
                !_subjects.any((s) => s['labOf'] == subject['id']))
              ListTile(
                leading: const Icon(Icons.science_outlined),
                title: const Text('Add a lab folder'),
                subtitle: const Text('For a lab with its own teacher'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _addLab(subject);
                },
              ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.error,
              ),
              title: const Text(
                'Delete subject',
                style: TextStyle(color: AppColors.error),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _deleteSubject(subject['id'] as String);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSubject(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: const Text('Delete subject?'),
        content: const Text(
          'Its recordings move to Unsorted and its classes leave the '
          'timetable. A lab of it stays as a folder of its own.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        if (!mounted) return;
        final reminders = context.read<ClassReminderService>();
        await _subjectDao.deleteSubject(id);
        // Its classes went with it, so their reminders must too.
        await reminders.reschedule();
        _loadSubjects();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                ErrorMessages.from(e, action: 'delete the subject'),
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }
}

// ─── Pieces ────────────────────────────────────────────────────────

/// "Today 1:30 PM", "Tomorrow 9:00 AM", "Wed 11:00 AM".
String _nextLabel(BuildContext context, ClassSlot slot) {
  final now = DateTime.now();
  final next = slot.nextStart(now);
  final time = MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay.fromDateTime(next),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
  final today = DateTime(now.year, now.month, now.day);
  final days = DateTime(
    next.year,
    next.month,
    next.day,
  ).difference(today).inDays;
  final day = switch (days) {
    0 => 'Today',
    1 => 'Tomorrow',
    _ => ClassSlot.weekdayShort[next.weekday - 1],
  };
  return '$day $time';
}

class _ViewToggle extends StatelessWidget {
  final bool isGrid;
  final VoidCallback onTap;

  const _ViewToggle({required this.isGrid, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: isGrid ? 'List view' : 'Grid view',
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(
              isGrid ? Icons.view_agenda_outlined : Icons.grid_view_rounded,
              size: 19,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Hours recorded across every course, with the binder illustration.
class _HoursHero extends StatelessWidget {
  final int totalMs;
  final int lectures;

  const _HoursHero({required this.totalMs, required this.lectures});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 128,
      decoration: BoxDecoration(
        color: AppColors.tintLavender,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 0,
            bottom: -6,
            child: SvgPicture.asset(
              'assets/images/home_subjects.svg',
              width: 132,
              height: 132,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 130, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  formatHours(totalMs),
                  style: const TextStyle(
                    fontSize: 38,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.2,
                    color: AppColors.inkLavender,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  lectures == 0
                      ? 'of lectures recorded, so far'
                      : 'recorded across $lectures '
                            'lecture${lectures == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkLavender.withValues(alpha: 0.75),
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

/// One course, in its own colour. [compact] lays it out as a row.
class _SubjectCard extends StatelessWidget {
  final Map<String, dynamic> subject;
  final ClassSlot? nextClass;
  final bool compact;
  final bool isUnsorted;
  final VoidCallback onTap;
  final VoidCallback? onMore;

  const _SubjectCard({
    required this.subject,
    required this.onTap,
    this.nextClass,
    this.compact = false,
    this.isUnsorted = false,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final name = subject['name'] as String? ?? 'Untitled';
    final isLab = subject['isLab'] == true;
    final teacher = subject['teacher'] as String?;
    final color = isUnsorted
        ? AppColors.textSecondary
        : AppColors.fromHex(subject['color'] as String?);
    // A darker shade of the subject's colour, readable on its tint.
    final ink = Color.lerp(color, Colors.black, 0.35)!;
    final count =
        (subject['_count'] as Map<String, dynamic>?)?['recordings'] as int? ??
        0;
    final ms = (subject['totalDurationMs'] as int?) ?? 0;
    final awaiting = (subject['awaitingCount'] as int?) ?? 0;

    final meta = count == 0
        ? 'No lectures yet'
        : '$count lecture${count == 1 ? '' : 's'}'
              '${ms > 0 ? ' · ${formatHours(ms)}' : ''}';

    final badge = Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: isUnsorted || isLab
          ? Icon(
              isUnsorted ? Icons.inbox_rounded : ClassKindIcon.labIcon,
              color: AppColors.textOnPrimary,
              size: 22,
            )
          : Text(
              subjectInitials(name),
              style: const TextStyle(
                color: AppColors.textOnPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            ),
    );

    // Lectures still waiting for notes from the student's AI.
    final needsAi = awaiting == 0
        ? null
        : Tooltip(
            message: '$awaiting need your AI',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    size: 11,
                    color: AppColors.textOnPrimary,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '$awaiting',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textOnPrimary,
                    ),
                  ),
                ],
              ),
            ),
          );

    final next = nextClass == null
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule_rounded, size: 12, color: ink),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    _nextLabel(context, nextClass!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                ),
              ],
            ),
          );

    final title = Text(
      isUnsorted ? 'Unsorted' : name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 15.5,
        height: 1.2,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.2,
        color: ink,
      ),
    );
    final subtitle = Text(
      isUnsorted ? '$meta · quick records' : teacher ?? meta,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: ink.withValues(alpha: 0.7),
      ),
    );

    return Material(
      color: color.withValues(alpha: isUnsorted ? 0.08 : 0.11),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        onLongPress: onMore,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 14),
          child: compact
              ? Row(
                  children: [
                    badge,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(child: title),
                              if (isLab) ...[
                                const SizedBox(width: 6),
                                _LabTag(ink: ink),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          subtitle,
                          if (next != null) ...[
                            const SizedBox(height: 6),
                            next,
                          ],
                        ],
                      ),
                    ),
                    ?needsAi,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        badge,
                        const Spacer(),
                        ?needsAi,
                        if (isLab && needsAi == null) _LabTag(ink: ink),
                      ],
                    ),
                    const Spacer(),
                    title,
                    const SizedBox(height: 3),
                    subtitle,
                    const SizedBox(height: 10),
                    next ??
                        Text(
                          isUnsorted
                              ? 'Move them into a course'
                              : 'No classes set',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: ink.withValues(alpha: 0.5),
                          ),
                        ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Marks a lab folder, so it reads apart from its theory course.
class _LabTag extends StatelessWidget {
  final Color ink;

  const _LabTag({required this.ink});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: ink,
        borderRadius: BorderRadius.circular(100),
      ),
      child: const Text(
        'LAB',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
          color: AppColors.textOnPrimary,
        ),
      ),
    );
  }
}

/// The last tile: add another course.
class _NewSubjectCard extends StatelessWidget {
  final bool compact;
  final VoidCallback onTap;

  const _NewSubjectCard({required this.compact, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final icon = Container(
      width: 46,
      height: 46,
      decoration: const BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.add_rounded,
        color: AppColors.textOnPrimary,
        size: 26,
      ),
    );
    const label = Text(
      'New subject',
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w900,
        color: AppColors.primary,
      ),
    );

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
          child: compact
              ? Row(children: [icon, const SizedBox(width: 12), label])
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [icon, const SizedBox(height: 10), label],
                ),
        ),
      ),
    );
  }
}
