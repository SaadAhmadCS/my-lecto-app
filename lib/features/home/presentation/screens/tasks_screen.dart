import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/page_title.dart';
import '../../../recording/data/local/recording_dao.dart';
import '../../../recording/data/local/recording_feed.dart';
import '../../../subjects/data/subject_dao.dart';
import '../../data/home_digest.dart';
import '../widgets/home_task_row.dart';

/// Every task your lectures handed out.
///
/// Tasks are not entered by hand: they are the checklist items in each
/// lecture's notes, and ticking one here ticks it in those notes. To-dos are
/// grouped by how soon they are due — overdue, today, this week, later — so
/// the list reads as a plan rather than a pile.
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  late final HomeDigestBuilder _builder = HomeDigestBuilder(
    dao: context.read<RecordingDao>(),
    feed: context.read<RecordingFeed>(),
    subjects: context.read<SubjectDao>(),
  );

  List<HomeTask> _open = const [];
  List<HomeTask> _done = const [];
  bool _showDone = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Show the last digest straight away; the load below refreshes it.
    final cached = HomeDigestBuilder.last;
    if (cached != null) _apply(cached);
    _load();
  }

  Future<void> _load() async {
    final digest = await _builder.build();
    if (!mounted) return;
    setState(() => _apply(digest));
  }

  void _apply(HomeDigest digest) {
    _open = digest.todayTasks.where((task) => !task.done).toList();
    _done = digest.tasks.where((task) => task.done).toList();
    _isLoading = false;
  }

  Future<void> _toggle(HomeTask task) async {
    final changed = await _builder.toggleTask(task);
    if (!mounted) return;
    if (!changed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Couldn\'t update that task. Open its lecture instead.',
          ),
        ),
      );
    }
    await _load();
  }

  void _openLecture(HomeTask task) {
    context
        .push(
          '/recording/${task.recordingId}'
          '?title=${Uri.encodeComponent(task.recordingTitle)}',
        )
        .then((_) => _load());
  }

  /// Open tasks in due-date buckets, in order, skipping empty ones.
  List<(_Bucket, List<HomeTask>)> get _buckets {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final groups = <_Bucket, List<HomeTask>>{};
    for (final task in _open) {
      groups.putIfAbsent(_Bucket.of(task.dueAt, today), () => []).add(task);
    }
    return [
      for (final bucket in _Bucket.values)
        if (groups[bucket] != null) (bucket, groups[bucket]!),
    ];
  }

  int get _dueThisWeek {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _open.where((task) {
      final bucket = _Bucket.of(task.dueAt, today);
      return bucket == _Bucket.today || bucket == _Bucket.week;
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 130),
                  children: [
                    const PageTitle(
                      title: 'Tasks',
                      subtitle: 'Straight from your lecture notes',
                    ),
                    const SizedBox(height: 18),
                    _ProgressHero(
                      open: _open.length,
                      done: _done.length,
                      dueThisWeek: _dueThisWeek,
                    ),
                    const SizedBox(height: 18),
                    if (_open.isEmpty && _done.isEmpty)
                      const _EmptyTasks()
                    else ...[
                      _Segmented(
                        showDone: _showDone,
                        openCount: _open.length,
                        doneCount: _done.length,
                        onChanged: (v) => setState(() => _showDone = v),
                      ),
                      const SizedBox(height: 16),
                      if (_showDone)
                        ..._rows(_done)
                      else if (_open.isEmpty)
                        const _AllDone()
                      else
                        for (final (bucket, tasks) in _buckets) ...[
                          _BucketLabel(bucket: bucket, count: tasks.length),
                          ..._rows(tasks),
                          const SizedBox(height: 8),
                        ],
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  List<Widget> _rows(List<HomeTask> tasks) => [
    for (final task in tasks)
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: HomeTaskRow(
          task: task,
          onTap: () => _openLecture(task),
          onToggle: () => _toggle(task),
        ),
      ),
  ];
}

/// When a task is due, coarsely.
enum _Bucket {
  overdue('Overdue', AppColors.error),
  today('Today', AppColors.primary),
  week('This week', Color(0xFFA66E0A)),
  later('Later', AppColors.inkSky),
  undated('No date', AppColors.textMuted);

  const _Bucket(this.label, this.color);
  final String label;
  final Color color;

  static _Bucket of(DateTime? due, DateTime today) {
    if (due == null) return _Bucket.undated;
    final days = DateTime(
      due.year,
      due.month,
      due.day,
    ).difference(today).inDays;
    if (days < 0) return _Bucket.overdue;
    if (days == 0) return _Bucket.today;
    if (days < 7) return _Bucket.week;
    return _Bucket.later;
  }
}

/// How much is left, with a ring that fills as tasks get ticked.
class _ProgressHero extends StatelessWidget {
  final int open;
  final int done;
  final int dueThisWeek;

  const _ProgressHero({
    required this.open,
    required this.done,
    required this.dueThisWeek,
  });

  @override
  Widget build(BuildContext context) {
    final total = open + done;
    final progress = total == 0 ? 0.0 : done / total;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
      decoration: BoxDecoration(
        color: AppColors.tintMint,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$open',
                      style: const TextStyle(
                        fontSize: 52,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -2,
                        color: AppColors.inkMint,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'to do',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.inkMint,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  total == 0
                      ? 'Nothing assigned yet'
                      : '$dueThisWeek due this week · $done done',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkMint.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
          // The clipboard, ringed by how much of it is ticked off.
          SizedBox(
            width: 104,
            height: 104,
            child: Stack(
              alignment: Alignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => CustomPaint(
                    size: const Size.square(104),
                    painter: _RingPainter(progress: value),
                  ),
                ),
                SvgPicture.asset(
                  'assets/images/home_tasks.svg',
                  width: 78,
                  height: 78,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;

  const _RingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(5);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..color = AppColors.inkMint.withValues(alpha: 0.12);
    canvas.drawArc(rect, 0, math.pi * 2, false, track);
    if (progress <= 0) return;
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = AppColors.success;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false, fill);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

/// "To do · 8 | Done · 2".
class _Segmented extends StatelessWidget {
  final bool showDone;
  final int openCount;
  final int doneCount;
  final ValueChanged<bool> onChanged;

  const _Segmented({
    required this.showDone,
    required this.openCount,
    required this.doneCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget segment(String label, bool selected, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.navBar : Colors.transparent,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: selected
                    ? AppColors.textOnPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        children: [
          segment('To do · $openCount', !showDone, () => onChanged(false)),
          segment('Done · $doneCount', showDone, () => onChanged(true)),
        ],
      ),
    );
  }
}

class _BucketLabel extends StatelessWidget {
  final _Bucket bucket;
  final int count;

  const _BucketLabel({required this.bucket, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10, top: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: bucket.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            bucket.label.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              color: bucket.color,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _AllDone extends StatelessWidget {
  const _AllDone();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Text('🎉', style: TextStyle(fontSize: 40)),
          SizedBox(height: 10),
          Text(
            'All caught up',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Every task from your lectures is ticked off.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _EmptyTasks extends StatelessWidget {
  const _EmptyTasks();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        children: [
          Text(
            'No tasks yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'When a lecture hands out work, your AI lists it in the notes and '
            'it lands here — ready to tick off.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
