import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/notes_parser.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../recording/data/local/recording_dao.dart';
import '../../../recording/data/local/recording_feed.dart';
import '../../../subjects/data/subject_dao.dart';
import '../widgets/home_action_card.dart';
import '../widgets/home_task_row.dart';

/// The dashboard: what needs doing, and the four ways in.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final RecordingFeed _feed = context.read<RecordingFeed>();
  late final RecordingDao _dao = context.read<RecordingDao>();
  late final SubjectDao _subjectDao = context.read<SubjectDao>();

  List<_DueTask> _tasks = const [];
  int _subjectCount = 0;
  int _recordingCount = 0;
  int _awaitingCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final subjects = await _subjectDao.listSubjects();
      final recordings = await _feed.list();
      final awaiting = await _feed.awaitingCount();
      final tasks = await _collectTasks(recordings);

      if (!mounted) return;
      setState(() {
        _subjectCount = subjects.length;
        _recordingCount = recordings.length;
        _awaitingCount = awaiting;
        _tasks = tasks;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  /// Pull the checklist items out of every recording's notes.
  ///
  /// Tasks are not stored separately — they live inside the markdown the AI
  /// returned, so they are parsed back out on demand.
  Future<List<_DueTask>> _collectTasks(
    List<Map<String, dynamic>> recordings,
  ) async {
    final collected = <_DueTask>[];

    for (final recording in recordings) {
      final id = recording['id'] as String;
      final notes = await _dao.getNotes(id);
      if (notes == null) continue;

      final parsed = NotesParser.parse(notes.notesMarkdown);
      final subject = recording['subject'] as Map<String, dynamic>?;

      for (final task in parsed.tasks) {
        collected.add(_DueTask(
          text: task.text,
          done: task.done,
          recordingId: id,
          recordingTitle: recording['title'] as String? ?? 'Recording',
          subjectName: subject?['name'] as String?,
        ));
      }
    }

    // Unfinished work first — that is what the screen is for.
    collected.sort((a, b) {
      if (a.done == b.done) return 0;
      return a.done ? 1 : -1;
    });
    return collected;
  }

  int get _openTaskCount => _tasks.where((t) => !t.done).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.base,
              AppSpacing.lg,
              AppSpacing.huge * 2,
            ),
            children: [
              _buildGreeting(context),
              const SizedBox(height: AppSpacing.lg),
              _buildActionGrid(context),
              if (_awaitingCount > 0) ...[
                const SizedBox(height: AppSpacing.base),
                _buildAwaitingPill(context),
              ],
              const SizedBox(height: AppSpacing.xl),
              _buildTasks(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGreeting(BuildContext context) {
    final now = DateTime.now();
    final open = _openTaskCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _formatDate(now).toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // The headline states the one thing worth knowing on opening the app.
        RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
            children: _isLoading
                ? const [TextSpan(text: 'Getting things ready…')]
                : open > 0
                    ? [
                        TextSpan(
                          text: '$open thing${open == 1 ? '' : 's'} ',
                          style: const TextStyle(color: AppColors.primary),
                        ),
                        const TextSpan(text: 'to do.'),
                      ]
                    : _recordingCount == 0
                        ? [const TextSpan(text: 'Record your first lecture.')]
                        : [const TextSpan(text: 'Nothing due. Nice.')],
          ),
        ),
      ],
    );
  }

  Widget _buildActionGrid(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: [
              HomeActionCard(
                title: 'Record',
                subtitle: 'Tap to record',
                icon: Icons.mic_rounded,
                background: AppColors.primary,
                foreground: AppColors.textOnPrimary,
                tall: true,
                onTap: () => context.push('/record'),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            children: [
              HomeActionCard(
                title: 'Subjects',
                subtitle: _subjectCount == 1
                    ? '1 subject'
                    : '$_subjectCount subjects',
                icon: Icons.folder_rounded,
                background: AppColors.tintLavender,
                foreground: AppColors.inkLavender,
                onTap: () => context.go('/subjects'),
              ),
              const SizedBox(height: AppSpacing.md),
              HomeActionCard(
                title: 'Lectures',
                subtitle: _recordingCount == 1
                    ? '1 recording'
                    : '$_recordingCount recordings',
                icon: Icons.graphic_eq_rounded,
                background: AppColors.tintMint,
                foreground: AppColors.inkMint,
                onTap: () => context.go('/transcripts'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Nothing else surfaces recordings with no notes — no upload, no
  /// processing — so without this they pile up unnoticed.
  Widget _buildAwaitingPill(BuildContext context) {
    final label = _awaitingCount == 1
        ? '1 recording needs your AI'
        : '$_awaitingCount recordings need your AI';

    return InkWell(
      onTap: () => context.go('/transcripts'),
      borderRadius: BorderRadius.circular(100),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.tintCoral,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome_rounded,
                size: 18, color: AppColors.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.inkCoral,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildTasks(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: AppSpacing.xxl),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (_tasks.isEmpty) return _buildEmptyTasks(context);

    final shown = _tasks.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'To do',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            if (_tasks.length > shown.length)
              Text(
                '${_tasks.length - shown.length} more',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ...shown.map(
          (task) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: HomeTaskRow(
              text: task.text,
              done: task.done,
              context: task.subjectName ?? task.recordingTitle,
              onTap: () => context.push(
                '/recording/${task.recordingId}'
                '?title=${Uri.encodeComponent(task.recordingTitle)}',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyTasks(BuildContext context) {
    final hasRecordings = _recordingCount > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(
            hasRecordings
                ? Icons.checklist_rounded
                : Icons.mic_none_rounded,
            size: 36,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            hasRecordings ? 'No tasks yet' : 'No lectures yet',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            hasRecordings
                ? 'Tasks appear here once your AI finds them in a lecture.'
                : 'Record a lecture, share it to your AI app, then paste the '
                    'reply back.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) {
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${days[date.weekday - 1]} ${date.day} ${months[date.month - 1]}';
  }
}

/// A checklist item, with the lecture it came from.
class _DueTask {
  final String text;
  final bool done;
  final String recordingId;
  final String recordingTitle;
  final String? subjectName;

  const _DueTask({
    required this.text,
    required this.done,
    required this.recordingId,
    required this.recordingTitle,
    this.subjectName,
  });
}
