import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../recording/data/local/recording_dao.dart';
import '../../../recording/data/local/recording_feed.dart';
import '../../../subjects/data/subject_dao.dart';
import '../../data/home_digest.dart';
import '../widgets/upcoming_card.dart';

/// Quizzes, assignments and anything else dated, grouped by day.
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
    _load();
  }

  Future<void> _load() async {
    final digest = await _builder.build();
    if (!mounted) return;
    setState(() {
      _items = digest.futureItems;
      _isLoading = false;
    });
  }

  /// Items grouped under a day heading, in date order; undated ones last.
  List<(String, List<UpcomingItem>)> get _groups {
    final groups = <String, List<UpcomingItem>>{};
    for (final item in _items) {
      groups.putIfAbsent(_dayLabel(item), () => []).add(item);
    }
    return [for (final entry in groups.entries) (entry.key, entry.value)];
  }

  static String _dayLabel(UpcomingItem item) {
    final date = item.date;
    if (date == null) return 'No date given';
    switch (item.daysAway) {
      case 0:
        return 'Today';
      case 1:
        return 'Tomorrow';
    }
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${days[date.weekday - 1]}, ${date.day} ${months[date.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(
          'Calendar',
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
                  if (_items.isEmpty)
                    _buildEmpty(context)
                  else
                    for (final (label, items) in _groups) ...[
                      Padding(
                        padding: const EdgeInsets.only(
                          top: AppSpacing.sm,
                          bottom: AppSpacing.md,
                        ),
                        child: Text(
                          label,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      for (final item in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: SizedBox(
                            height: 120,
                            child: UpcomingCard(
                              item: item,
                              fullWidth: true,
                              onTap: () => context
                                  .push(
                                    '/recording/${item.recordingId}'
                                    '?title=${Uri.encodeComponent(item.recordingTitle)}',
                                  )
                                  .then((_) => _load()),
                            ),
                          ),
                        ),
                    ],
                ],
              ),
            ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.huge),
      child: Column(
        children: [
          const Icon(Icons.event_note_rounded,
              size: 44, color: AppColors.textMuted),
          const SizedBox(height: AppSpacing.base),
          Text(
            'Nothing coming up',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Quizzes and deadlines a lecture mentions show up here, by day.',
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
