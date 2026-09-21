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
import '../widgets/deadline_tile.dart';

/// Quizzes, assignments and anything else dated, week by week.
///
/// Nothing is scheduled by hand: these are the deadlines your AI pulled out of
/// each lecture's notes.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
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
    _items = digest.futureItems;
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

  /// Items by week: this week, next week, later, and those with no date.
  List<(String, List<UpcomingItem>)> get _weeks {
    String label(UpcomingItem item) {
      final days = item.daysAway;
      if (days == null) return 'No date';
      // Weeks start on Monday, like the timetable.
      final weekdayToday = DateTime.now().weekday;
      final week = (days + weekdayToday - 1) ~/ 7;
      return switch (week) {
        0 => 'This week',
        1 => 'Next week',
        _ => 'Later',
      };
    }

    final groups = <String, List<UpcomingItem>>{};
    for (final item in _items) {
      groups.putIfAbsent(label(item), () => []).add(item);
    }
    return [
      for (final name in const ['This week', 'Next week', 'Later', 'No date'])
        if (groups[name] != null) (name, groups[name]!),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final weekItems = _items.where((i) => (i.daysAway ?? 99) <= 7);
    final quizzes = weekItems.where((i) => i.kind == UpcomingKind.quiz).length;
    final assignments = weekItems
        .where((i) => i.kind == UpcomingKind.assignment)
        .length;

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
                      title: 'Calendar',
                      subtitle: 'Everything dated in your notes',
                    ),
                    const SizedBox(height: 16),
                    if (_items.isEmpty)
                      const _EmptyCalendar()
                    else ...[
                      Row(
                        children: [
                          _Stat(
                            count: quizzes,
                            label: quizzes == 1 ? 'quiz' : 'quizzes',
                            color: AppColors.inkLavender,
                            background: AppColors.tintLavender,
                          ),
                          const SizedBox(width: 10),
                          _Stat(
                            count: assignments,
                            label: assignments == 1
                                ? 'assignment'
                                : 'assignments',
                            color: const Color(0xFF97245C),
                            background: AppColors.tintPink,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Text(
                          'in the next 7 days',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                      for (final (label, items) in _weeks) ...[
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 10),
                          child: Text(
                            '${label.toUpperCase()}  ·  ${items.length}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                        for (final item in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: DeadlineTile(
                              item: item,
                              onTap: () => _open(item),
                            ),
                          ),
                      ],
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final int count;
  final String label;
  final Color color;
  final Color background;

  const _Stat({
    required this.count,
    required this.label,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 30,
                height: 1,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCalendar extends StatelessWidget {
  const _EmptyCalendar();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          SvgPicture.asset('assets/images/timetable.svg', width: 120),
          const Text(
            'Nothing coming up',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Quizzes and deadlines a lecture mentions show up here, week by '
            'week.',
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
