import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../recording/data/local/recording_feed.dart';
import '../../../timetable/data/class_slot.dart';
import '../../../timetable/data/timetable_dao.dart';
import '../../data/home_digest.dart';

/// Everything that wants the student's attention, behind the bell.
///
/// Three kinds, most urgent first: tasks that are overdue or due today,
/// lectures still waiting to be sent to their AI, and the next class. Each
/// row goes straight to where it can be dealt with.
class InboxSheet extends StatefulWidget {
  final HomeDigest digest;

  const InboxSheet._({required this.digest});

  static Future<void> show(BuildContext context, HomeDigest digest) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      backgroundColor: AppColors.background,
      barrierColor: AppColors.textPrimary.withValues(alpha: 0.35),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => InboxSheet._(digest: digest),
    );
  }

  /// Items that deserve the bell's dot: urgent tasks and waiting lectures.
  /// The next class is useful to see but not something to act on.
  static int attentionCount(HomeDigest digest) =>
      _urgentTasks(digest).length + digest.awaitingCount;

  static List<HomeTask> _urgentTasks(HomeDigest digest) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return digest.tasks.where((task) {
      final due = task.dueAt;
      if (task.done || due == null) return false;
      return !DateTime(due.year, due.month, due.day).isAfter(today);
    }).toList();
  }

  @override
  State<InboxSheet> createState() => _InboxSheetState();
}

class _InboxSheetState extends State<InboxSheet> {
  List<Map<String, dynamic>> _awaiting = const [];
  ClassSlot? _next;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final feed = context.read<RecordingFeed>();
    final timetable = context.read<TimetableDao>();
    final recordings = await feed.list();
    final slots = await timetable.list();

    final now = DateTime.now();
    ClassSlot? next;
    for (final slot in slots) {
      if (next == null || slot.nextStart(now).isBefore(next.nextStart(now))) {
        next = slot;
      }
    }

    if (!mounted) return;
    setState(() {
      _awaiting = recordings
          .where((r) => r['processingStatus'] == RecordingFeed.awaitingNotes)
          .toList();
      _next = next;
      _isLoading = false;
    });
  }

  void _go(String location) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push(location);
  }

  @override
  Widget build(BuildContext context) {
    final urgent = InboxSheet._urgentTasks(widget.digest);
    final empty = urgent.isEmpty && _awaiting.isEmpty;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              empty ? 'All caught up' : 'Needs you',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      children: [
                        if (empty)
                          const _Row(
                            icon: Icons.celebration_rounded,
                            tint: AppColors.tintMint,
                            ink: AppColors.inkMint,
                            title: 'Nothing waiting on you',
                            subtitle:
                                'No overdue work, every lecture has notes',
                          ),
                        if (urgent.isNotEmpty) ...[
                          _Label('Due', urgent.length),
                          for (final task in urgent)
                            _Row(
                              icon: Icons.checklist_rounded,
                              tint: AppColors.errorBg,
                              ink: AppColors.error,
                              title: task.text,
                              subtitle: [
                                _dueLabel(task.dueAt!),
                                ?task.subjectName,
                              ].join(' · '),
                              onTap: () => _go(
                                '/recording/${task.recordingId}'
                                '?title=${Uri.encodeComponent(task.recordingTitle)}',
                              ),
                            ),
                        ],
                        if (_awaiting.isNotEmpty) ...[
                          _Label('Needs your AI', _awaiting.length),
                          for (final r in _awaiting)
                            _Row(
                              icon: Icons.auto_awesome_rounded,
                              tint: AppColors.tintCoral,
                              ink: AppColors.primary,
                              title: r['title'] as String? ?? 'Recording',
                              subtitle:
                                  'Share it to your AI to get notes'
                                  '${(r['subject'] as Map?)?['name'] != null ? ' · ${(r['subject'] as Map)['name']}' : ''}',
                              onTap: () => _go(
                                '/recording/${r['id']}'
                                '?title=${Uri.encodeComponent(r['title'] as String? ?? '')}',
                              ),
                            ),
                        ],
                        if (_next != null) ...[
                          const _Label('Next class', null),
                          _Row(
                            icon: _next!.kindIcon,
                            tint: _next!.color.withValues(alpha: 0.13),
                            ink: _next!.color,
                            title: _next!.displayName,
                            subtitle: [
                              _classWhen(context, _next!),
                              ?_next!.room,
                            ].join(' · '),
                            onTap: () => _go('/timetable'),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _dueLabel(DateTime due) {
    final now = DateTime.now();
    final days = DateTime(
      due.year,
      due.month,
      due.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
    if (days == -1) return 'Overdue by a day';
    if (days < 0) return 'Overdue by ${-days} days';
    return 'Due today';
  }

  static String _classWhen(BuildContext context, ClassSlot slot) {
    final now = DateTime.now();
    final start = slot.nextStart(now);
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(start),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final days = DateTime(
      start.year,
      start.month,
      start.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
    final day = switch (days) {
      0 => 'Today',
      1 => 'Tomorrow',
      _ => ClassSlot.weekdayLong[start.weekday - 1],
    };
    return '$day $time';
  }
}

class _Label extends StatelessWidget {
  final String text;
  final int? count;

  const _Label(this.text, this.count);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 6, bottom: 8),
      child: Text(
        count == null ? text.toUpperCase() : '${text.toUpperCase()}  ·  $count',
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

class _Row extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final Color ink;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _Row({
    required this.icon,
    required this.tint,
    required this.ink,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, size: 21, color: ink),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textMuted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
