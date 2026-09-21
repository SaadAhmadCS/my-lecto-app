import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_messages.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/routes/app_router.dart';
import '../../../recording/data/local/recording_feed.dart';
import '../../../recording/presentation/bloc/recording_bloc.dart';
import '../../data/subject_dao.dart';
import '../../../../shared/widgets/recording_card.dart';

/// Subject detail — all recordings in one subject (ORG-004).
class SubjectDetailScreen extends StatefulWidget {
  final String subjectId;

  const SubjectDetailScreen({super.key, required this.subjectId});

  @override
  State<SubjectDetailScreen> createState() => _SubjectDetailScreenState();
}

class _SubjectDetailScreenState extends State<SubjectDetailScreen> {
  late final SubjectDao _subjectDao = context.read<SubjectDao>();
  late final RecordingFeed _feed = context.read<RecordingFeed>();

  Map<String, dynamic>? _subject;
  List<Map<String, dynamic>> _recordings = [];
  int _totalRecordings = 0;
  RecordingSort _sort = RecordingSort.date;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final subject = await _subjectDao.getSubject(widget.subjectId);
      final recordings = await _feed.list(subjectId: widget.subjectId);

      if (!mounted) return;
      setState(() {
        _subject = subject;
        _recordings = _sort.apply(recordings);
        _totalRecordings = recordings.length;
        _isLoading = false;
        _error = subject == null ? 'This subject no longer exists.' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorMessages.from(e);
        _isLoading = false;
      });
    }
  }

  Color get _subjectColor {
    final hex = _subject?['color'] as String? ?? '#6366F1';
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return AppColors.primary;
    }
  }

  Duration get _totalDuration => Duration(
        milliseconds: _recordings.fold<int>(
          0,
          (sum, r) => sum + (r['totalDurationMs'] as int? ?? 0),
        ),
      );

  Future<void> _openRecording(Map<String, dynamic> recording) async {
    final id = recording['id'] as String;
    final title = recording['title'] as String? ?? 'Recording';
    await context.push('/recording/$id?title=${Uri.encodeComponent(title)}');
    // Recording may have been renamed, moved or deleted
    if (mounted) _load();
  }

  Future<void> _recordInSubject() async {
    // The subject is already known, so skip the picker and start recording —
    // unless one is running, in which case this returns to it.
    final active = context.read<RecordingBloc>().isActive;
    await context.push(
      active
          ? AppRoutes.record
          : '${AppRoutes.record}?subjectId=${widget.subjectId}&start=1',
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _subject?['name'] as String? ?? 'Subject',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_recordings.length > 1)
            RecordingSortButton(
              value: _sort,
              onChanged: (sort) => setState(() {
                _sort = sort;
                _recordings = sort.apply(_recordings);
              }),
            ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: _subject == null
          ? null
          : FloatingActionButton.extended(
              heroTag: 'subject_detail_record_fab',
              onPressed: _recordInSubject,
              backgroundColor: AppColors.recordingRed,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.mic_rounded),
              label: const Text('Record in this subject'),
            ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded,
                size: 48, color: AppColors.textTertiaryDark),
            const SizedBox(height: AppSpacing.base),
            Text('Could not load subject',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xl),
            OutlinedButton.icon(
              onPressed: () {
                setState(() => _isLoading = true);
                _load();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        // Leave room for the extended FAB
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.base,
          AppSpacing.base,
          AppSpacing.base,
          AppSpacing.huge * 2,
        ),
        children: [
          _buildHeader(),
          const SizedBox(height: AppSpacing.xl),
          if (_recordings.isEmpty)
            _buildEmptyState()
          else
            for (final recording in _recordings) ...[
              RecordingCard(
                recording: recording,
                showSubject: false,
                onTap: () => _openRecording(recording),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final countLabel =
        '$_totalRecordings recording${_totalRecordings == 1 ? '' : 's'}';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.darkBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Color bar
          Container(height: 4, color: _subjectColor),
          Padding(
            padding: AppSpacing.cardPadding,
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _subjectColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.folder_rounded, color: _subjectColor),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _subject?['name'] as String? ?? '',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _totalDuration.inSeconds > 0
                            ? '$countLabel · ${formatRecordingDuration(_totalDuration)} total'
                            : countLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textTertiaryDark,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxxl),
      child: Column(
        children: [
          Icon(Icons.mic_none_rounded,
              size: 56, color: AppColors.textTertiaryDark),
          const SizedBox(height: AppSpacing.base),
          Text(
            'No recordings yet — start your first one!',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.textSecondaryDark,
                ),
          ),
        ],
      ),
    );
  }
}
