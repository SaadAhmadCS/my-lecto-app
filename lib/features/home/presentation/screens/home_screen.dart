import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/user_profile.dart';
import '../../../../core/routes/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../recording/data/local/recording_dao.dart';
import '../../../recording/data/local/recording_feed.dart';
import '../../../recording/presentation/bloc/recording_bloc.dart';
import '../../../recording/presentation/widgets/record_subject_sheet.dart';
import '../../../subjects/data/subject_dao.dart';
import '../../data/home_digest.dart';
import '../widgets/home_action_card.dart';
import '../widgets/home_header.dart';
import '../widgets/home_task_row.dart';
import '../widgets/upcoming_card.dart';

/// The dashboard: what is due, and the four ways in.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeDigestBuilder _builder = HomeDigestBuilder(
    dao: context.read<RecordingDao>(),
    feed: context.read<RecordingFeed>(),
    subjects: context.read<SubjectDao>(),
  );

  HomeDigest _digest = const HomeDigest();
  String _name = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final digest = await _builder.build();
    final name = await UserProfile.name();

    if (!mounted) return;
    setState(() {
      _digest = digest;
      _name = name;
      _isLoading = false;
    });
  }

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
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.huge * 2.2,
            ),
            children: [
              HomeHeader(
                name: _name,
                streakDays: _digest.streakDays,
                needsAttention: _digest.awaitingCount,
                onAvatarTap: _editName,
                onBellTap: () => context.go('/transcripts'),
              ),
              const SizedBox(height: AppSpacing.lg),
              _buildGreeting(context),
              const SizedBox(height: AppSpacing.lg),
              _buildGrid(context),
              if (_digest.awaitingCount > 0) ...[
                const SizedBox(height: AppSpacing.base),
                _buildAwaitingPill(context),
              ],
              const SizedBox(height: AppSpacing.xl),
              _buildToday(context),
              const SizedBox(height: AppSpacing.xl),
              _buildComingUp(context),
            ],
          ),
        ),
      ),
    );
  }

  /// "Hey Saad, 3 things due today." — the one thing worth knowing on open.
  Widget _buildGreeting(BuildContext context) {
    final theme = Theme.of(context);
    final due = _digest.openTaskCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _name.isEmpty ? 'Hey there,' : 'Hey $_name,',
          style: theme.textTheme.headlineMedium?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        RichText(
          text: TextSpan(
            style: theme.textTheme.displayMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
            children: _isLoading
                ? const [TextSpan(text: 'one moment…')]
                : due > 0
                    ? [
                        TextSpan(
                          text: '$due thing${due == 1 ? '' : 's'} ',
                          style: const TextStyle(color: AppColors.primary),
                        ),
                        const TextSpan(text: 'to do.'),
                      ]
                    : _digest.recordingCount == 0
                        ? [const TextSpan(text: 'record your first lecture.')]
                        : [const TextSpan(text: 'nothing due. Nice.')],
          ),
        ),
      ],
    );
  }

  /// Four equal tiles, as in the design.
  Widget _buildGrid(BuildContext context) {
    final quizzes = _digest.quizzesThisWeek;
    final tasksDue = _digest.openTaskCount;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: HomeActionCard(
                title: 'Record',
                subtitle: 'Tap to record',
                illustration: 'assets/images/home_record.svg',
                background: AppColors.primary,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFF57049), Color(0xFFEC5A32)],
                ),
                foreground: AppColors.textOnPrimary,
                onTap: _startRecording,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: HomeActionCard(
                title: 'Subjects',
                subtitle: _digest.subjectCount == 1
                    ? '1 course'
                    : '${_digest.subjectCount} courses',
                illustration: 'assets/images/home_subjects.svg',
                background: AppColors.tintLavender,
                foreground: AppColors.inkLavender,
                onTap: () => context.go('/subjects'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: HomeActionCard(
                title: 'Tasks',
                subtitle: tasksDue == 0
                    ? 'All clear'
                    : '$tasksDue to do',
                illustration: 'assets/images/home_tasks.svg',
                background: AppColors.tintMint,
                foreground: AppColors.inkMint,
                onTap: () => context.go(AppRoutes.tasks),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: HomeActionCard(
                title: 'Quizzes',
                subtitle: quizzes == 0
                    ? 'None coming up'
                    : '$quizzes this week',
                illustration: 'assets/images/home_quizzes.svg',
                background: AppColors.tintSky,
                foreground: AppColors.inkSky,
                onTap: () => context.push(AppRoutes.quizzes).then((_) => _load()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAwaitingPill(BuildContext context) {
    final count = _digest.awaitingCount;

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
            const Icon(Icons.star_rounded, size: 18, color: AppColors.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                count == 1
                    ? '1 recording needs your AI'
                    : '$count recordings need your AI',
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

  Widget _buildToday(BuildContext context) {
    final tasks = _digest.todayTasks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Today',
          action: tasks.isEmpty ? null : 'View all',
          onAction: () => context.go(AppRoutes.tasks),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          )
        else if (tasks.isEmpty)
          _EmptyPanel(
            icon: _digest.recordingCount == 0
                ? Icons.mic_none_rounded
                : Icons.checklist_rounded,
            title: _digest.recordingCount == 0
                ? 'No lectures yet'
                : 'Nothing to do',
            body: _digest.recordingCount == 0
                ? 'Record a lecture, share it to your AI app, then paste the '
                    'reply back.'
                : 'Tasks appear here once your AI finds them in a lecture.',
          )
        else
          ...tasks.take(4).map(
                (task) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: HomeTaskRow(
                    task: task,
                    onTap: () => context
                        .push(
                          '/recording/${task.recordingId}'
                          '?title=${Uri.encodeComponent(task.recordingTitle)}',
                        )
                        .then((_) => _load()),
                    onToggle: () async {
                      await _builder.toggleTask(task);
                      await _load();
                    },
                  ),
                ),
              ),
      ],
    );
  }

  Widget _buildComingUp(BuildContext context) {
    final items = _digest.futureItems;
    if (_isLoading || items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Coming up',
          action: 'Calendar',
          onAction: () => context.go(AppRoutes.calendar),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, index) => UpcomingCard(
              item: items[index],
              onTap: () => context.push(
                '/recording/${items[index].recordingId}'
                '?title=${Uri.encodeComponent(items[index].recordingTitle)}',
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Ask which subject, then go straight into recording.
  ///
  /// If a recording is already running, this just returns to it.
  Future<void> _startRecording() async {
    if (context.read<RecordingBloc>().isActive) {
      await context.push(AppRoutes.record);
    } else {
      final subjectId = await RecordSubjectSheet.show(context);
      if (subjectId == null || !mounted) return;
      await context.push(
        '${AppRoutes.record}?subjectId=${Uri.encodeComponent(subjectId)}'
        '&start=1',
      );
    }
    if (mounted) _load();
  }

  /// There is no account, so the name is simply a preference.
  Future<void> _editName() async {
    final controller = TextEditingController(text: _name);

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('What should I call you?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Your name'),
          onSubmitted: (value) => Navigator.of(ctx).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (name == null) return;
    await UserProfile.setName(name);
    if (mounted) setState(() => _name = name.trim());
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;

  const _SectionHeader({required this.title, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        if (action != null)
          GestureDetector(
            onTap: onAction,
            child: Text(
              action!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
      ],
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _EmptyPanel({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
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
          Icon(icon, size: 34, color: AppColors.textMuted),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            body,
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
}
