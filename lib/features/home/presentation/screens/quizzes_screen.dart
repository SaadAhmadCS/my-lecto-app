import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/ui/motion.dart';
import '../../../../shared/widgets/page_title.dart';
import '../../../recording/data/local/recording_dao.dart';
import '../../../recording/data/local/recording_feed.dart';
import '../../../subjects/data/subject_dao.dart';
import '../../data/home_digest.dart';
import '../widgets/deadline_tile.dart';

/// Quizzes and exams your lectures mentioned.
///
/// Nothing is scheduled by hand: these are the dated items from your notes
/// whose wording reads like a quiz rather than an assignment. The next one
/// gets the spotlight; the rest follow as a timeline.
class QuizzesScreen extends StatefulWidget {
  const QuizzesScreen({super.key});

  @override
  State<QuizzesScreen> createState() => _QuizzesScreenState();
}

class _QuizzesScreenState extends State<QuizzesScreen> {
  late final HomeDigestBuilder _builder = HomeDigestBuilder(
    dao: context.read<RecordingDao>(),
    feed: context.read<RecordingFeed>(),
    subjects: context.read<SubjectDao>(),
  );

  List<UpcomingItem> _items = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
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
    _items = digest.futureItems
        .where((item) => item.kind == UpcomingKind.quiz)
        .toList();
    _isLoading = false;
  }

  void _open(UpcomingItem item) {
    context
        .push(
          '/recording/${item.recordingId}'
          '?title=${Uri.encodeComponent(item.recordingTitle)}',
        )
        .then((_) => _load());
  }

  void _prepare([UpcomingItem? item]) {
    context
        .push(
          AppRoutes.examPrepFor(
            subjectId: item?.subjectId,
            exam: item?.title,
            date: item?.date,
          ),
        )
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final next = _items.isEmpty ? null : _items.first;
    final rest = _items.skip(1).toList();
    final thisWeek = rest.where((i) => (i.daysAway ?? 99) <= 7).toList();
    final later = rest.where((i) => (i.daysAway ?? 99) > 7).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: _isLoading
            ? ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                children: const [
                  Skeleton(width: 160, height: 34, radius: 12),
                  SizedBox(height: 10),
                  Skeleton(width: 250, height: 16),
                  SizedBox(height: 22),
                  Skeleton(height: 176, radius: 24),
                  SizedBox(height: 12),
                  Skeleton(height: 72, radius: 20),
                ],
              )
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                  children: [
                    const PageTitle(
                      title: 'Quizzes',
                      subtitle: 'Tests and exams your lectures mentioned',
                      showBack: true,
                    ),
                    const SizedBox(height: 18),
                    _NextQuizHero(
                      next: next,
                      onTap: next == null ? null : () => _open(next),
                    ),
                    const SizedBox(height: 12),
                    _PrepCard(
                      title: next == null
                          ? 'Prepare for an exam'
                          : 'Prepare for ${next.title}',
                      onTap: () => _prepare(next),
                    ),
                    if (thisWeek.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _Section('This week', thisWeek.length),
                      for (final item in thisWeek) _tile(item),
                    ],
                    if (later.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _Section('Later', later.length),
                      for (final item in later) _tile(item),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _tile(UpcomingItem item) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: DeadlineTile(item: item, onTap: () => _open(item)),
  );
}

/// The next quiz, big — or a calm "nothing coming up".
class _NextQuizHero extends StatelessWidget {
  final UpcomingItem? next;
  final VoidCallback? onTap;

  const _NextQuizHero({required this.next, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final quiz = next;

    return Material(
      color: AppColors.tintSky,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 176,
          child: Stack(
            children: [
              Positioned(
                right: -6,
                bottom: -8,
                child: SvgPicture.asset(
                  'assets/images/home_quizzes.svg',
                  width: 132,
                  height: 132,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 124, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        quiz == null ? 'ALL CLEAR' : 'NEXT UP',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                          color: AppColors.inkSky,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      quiz?.title ?? 'No quizzes coming up',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        height: 1.2,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                        color: AppColors.inkSky,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      quiz == null
                          ? 'When a lecture mentions a quiz or exam with a '
                                'date, it shows up here.'
                          : quiz.subjectName ?? quiz.recordingTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkSky.withValues(alpha: 0.75),
                      ),
                    ),
                    const Spacer(),
                    if (quiz != null) _BigCountdown(daysAway: quiz.daysAway),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The way into exam prep: every lecture, hint and warning, sent to the
/// student's AI to prepare them.
class _PrepCard extends StatelessWidget {
  final String title;
  final VoidCallback onTap;

  const _PrepCard({required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.navBar,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC857).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.tips_and_updates_rounded,
                  size: 20,
                  color: Color(0xFFFFC857),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textOnPrimary,
                      ),
                    ),
                    Text(
                      "Built from every lecture and the teacher's hints",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textOnPrimary.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                color: AppColors.textOnPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "in 3 days", as a solid pill that turns coral when it is close.
class _BigCountdown extends StatelessWidget {
  final int? daysAway;

  const _BigCountdown({required this.daysAway});

  @override
  Widget build(BuildContext context) {
    final days = daysAway;
    final label = switch (days) {
      null => 'No date given',
      0 => 'Today',
      1 => 'Tomorrow',
      _ => 'in $days days',
    };
    final urgent = days != null && days <= 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: urgent ? AppColors.primary : AppColors.inkSky,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.timer_outlined,
            size: 15,
            color: AppColors.textOnPrimary,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.textOnPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String label;
  final int count;

  const _Section(this.label, this.count);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        '${label.toUpperCase()}  ·  $count',
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
