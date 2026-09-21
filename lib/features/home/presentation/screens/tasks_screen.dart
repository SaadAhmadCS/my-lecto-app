import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../recording/data/local/recording_dao.dart';
import '../../../recording/data/local/recording_feed.dart';
import '../../../subjects/data/subject_dao.dart';
import '../../data/home_digest.dart';
import '../widgets/home_task_row.dart';

/// Every task your lectures handed out, still to do first.
///
/// Tasks are not entered by hand: they are the checklist items in each
/// lecture's notes, and ticking one here ticks it in those notes.
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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final digest = await _builder.build();
    if (!mounted) return;

    final ordered = digest.todayTasks;
    setState(() {
      _open = ordered.where((task) => !task.done).toList();
      _done = digest.tasks.where((task) => task.done).toList();
      _isLoading = false;
    });
  }

  Future<void> _toggle(HomeTask task) async {
    final changed = await _builder.toggleTask(task);
    if (!mounted) return;
    if (!changed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Couldn\'t update that task. Open its lecture instead.'),
        ),
      );
    }
    await _load();
  }

  void _openLecture(HomeTask task) {
    context.push(
      '/recording/${task.recordingId}'
      '?title=${Uri.encodeComponent(task.recordingTitle)}',
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(
          'Tasks',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.huge * 2.2,
                ),
                children: [
                  if (_open.isEmpty && _done.isEmpty)
                    _buildEmpty(context)
                  else ...[
                    _SectionLabel(
                      _open.isEmpty ? 'All done' : 'To do · ${_open.length}',
                    ),
                    for (final task in _open) _row(task),
                    if (_done.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      _SectionLabel('Done · ${_done.length}'),
                      for (final task in _done) _row(task),
                    ],
                  ],
                ],
              ),
            ),
    );
  }

  Widget _row(HomeTask task) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: HomeTaskRow(
        task: task,
        onTap: () => _openLecture(task),
        onToggle: () => _toggle(task),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.huge),
      child: Column(
        children: [
          const Icon(Icons.checklist_rounded,
              size: 44, color: AppColors.textMuted),
          const SizedBox(height: AppSpacing.base),
          Text(
            'No tasks yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'When a lecture hands out work, your AI lists it in the notes and '
            'it shows up here.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}
