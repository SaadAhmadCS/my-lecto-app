import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_messages.dart';
import '../../../../core/routes/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/primary_pill_button.dart';
import '../../../../shared/widgets/recording_card.dart';
import '../../../recording/data/local/recording_database.dart';
import '../../../recording/data/local/recording_feed.dart';
import '../../../recording/presentation/bloc/recording_bloc.dart';
import '../../../timetable/data/class_slot.dart';
import '../../../timetable/data/timetable_dao.dart';
import '../../data/subject_dao.dart';
import '../subject_format.dart';

/// One course: its lectures, its weekly classes, and a button to record it.
///
/// Everything is in the subject's own colour, so each course feels like its
/// own space rather than a filtered list.
class SubjectDetailScreen extends StatefulWidget {
  final String subjectId;

  const SubjectDetailScreen({super.key, required this.subjectId});

  @override
  State<SubjectDetailScreen> createState() => _SubjectDetailScreenState();
}

class _SubjectDetailScreenState extends State<SubjectDetailScreen> {
  late final SubjectDao _subjectDao = context.read<SubjectDao>();
  late final RecordingFeed _feed = context.read<RecordingFeed>();
  late final TimetableDao _timetable = context.read<TimetableDao>();

  Map<String, dynamic>? _subject;
  List<Map<String, dynamic>> _recordings = [];
  List<ClassSlot> _classes = const [];
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
      final classes = (await _timetable.list())
          .where((slot) => slot.subjectId == widget.subjectId)
          .toList();

      if (!mounted) return;
      setState(() {
        _subject = subject;
        _recordings = _sort.apply(recordings);
        _classes = classes;
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

  bool get _isUnsorted =>
      widget.subjectId == RecordingDatabase.unsortedSubjectId;

  Color get _color => _isUnsorted
      ? AppColors.textSecondary
      : AppColors.fromHex(_subject?['color'] as String?);

  Future<void> _openRecording(Map<String, dynamic> recording) async {
    final id = recording['id'] as String;
    final title = recording['title'] as String? ?? 'Recording';
    await context.push('/recording/$id?title=${Uri.encodeComponent(title)}');
    // It may have been renamed, moved or deleted.
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
      backgroundColor: AppColors.background,
      body: _buildBody(),
      bottomNavigationBar: _subject == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: PrimaryPillButton(
                  label: 'Record ${_isUnsorted ? 'a lecture' : 'this subject'}',
                  icon: Icons.mic_rounded,
                  onPressed: _recordInSubject,
                ),
              ),
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
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _isLoading = true);
                  _load();
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    final awaiting = _recordings
        .where((r) => r['processingStatus'] == RecordingFeed.awaitingNotes)
        .length;

    return RefreshIndicator(
      color: _color,
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _Hero(
            name: _isUnsorted ? 'Unsorted' : _subject!['name'] as String? ?? '',
            color: _color,
            isUnsorted: _isUnsorted,
            lectures: _recordings.length,
            totalMs: _recordings.fold<int>(
              0,
              (sum, r) => sum + (r['totalDurationMs'] as int? ?? 0),
            ),
            awaiting: awaiting,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_classes.isNotEmpty) ...[
                  const _Label('Every week'),
                  SizedBox(
                    height: 74,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      itemCount: _classes.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, i) =>
                          _ClassChip(slot: _classes[i], color: _color),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                Row(
                  children: [
                    Expanded(
                      child: _Label(
                        _recordings.isEmpty
                            ? 'Lectures'
                            : 'Lectures · ${_recordings.length}',
                      ),
                    ),
                    if (_recordings.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: RecordingSortButton(
                          value: _sort,
                          onChanged: (sort) => setState(() {
                            _sort = sort;
                            _recordings = sort.apply(_recordings);
                          }),
                        ),
                      ),
                  ],
                ),
                if (_recordings.isEmpty)
                  _Empty(color: _color)
                else
                  for (final recording in _recordings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: RecordingCard(
                        recording: recording,
                        showSubject: false,
                        onTap: () => _openRecording(recording),
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

/// The subject's colour band: back button, big initials, name and stats.
class _Hero extends StatelessWidget {
  final String name;
  final Color color;
  final bool isUnsorted;
  final int lectures;
  final int totalMs;
  final int awaiting;

  const _Hero({
    required this.name,
    required this.color,
    required this.isUnsorted,
    required this.lectures,
    required this.totalMs,
    required this.awaiting,
  });

  @override
  Widget build(BuildContext context) {
    final ink = Color.lerp(color, Colors.black, 0.35)!;
    final top = MediaQuery.paddingOf(context).top;

    return Container(
      padding: EdgeInsets.fromLTRB(20, top + 10, 20, 22),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: AppColors.surface.withValues(alpha: 0.8),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).maybePop(),
              child: const SizedBox(
                width: 42,
                height: 42,
                child: Icon(
                  Icons.arrow_back_rounded,
                  size: 20,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: isUnsorted
                    ? const Icon(
                        Icons.inbox_rounded,
                        size: 30,
                        color: AppColors.textOnPrimary,
                      )
                    : Text(
                        subjectInitials(name),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textOnPrimary,
                        ),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  name,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 24,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _Stat(
                value: '$lectures',
                label: lectures == 1 ? 'lecture' : 'lectures',
                ink: ink,
              ),
              _Stat(value: formatHours(totalMs), label: 'recorded', ink: ink),
              _Stat(
                value: '$awaiting',
                label: 'need your AI',
                ink: awaiting > 0 ? AppColors.primary : ink,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final Color ink;

  const _Stat({required this.value, required this.label, required this.ink});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                height: 1.1,
                fontWeight: FontWeight.w900,
                color: ink,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One weekly class: lab flask or lecture book, day and time, room.
class _ClassChip extends StatelessWidget {
  final ClassSlot slot;
  final Color color;

  const _ClassChip({required this.slot, required this.color});

  @override
  Widget build(BuildContext context) {
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      slot.start,
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final ink = Color.lerp(color, Colors.black, 0.35)!;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: slot.isLab ? ink : color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              slot.kindIcon,
              size: 20,
              color: slot.isLab ? AppColors.textOnPrimary : ink,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${ClassSlot.weekdayShort[slot.weekday - 1]} · $time',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                [slot.isLab ? 'Lab' : 'Lecture', ?slot.room].join(' · '),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;

  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text.toUpperCase(),
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

class _Empty extends StatelessWidget {
  final Color color;

  const _Empty({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.mic_none_rounded, color: color, size: 28),
          ),
          const SizedBox(height: 12),
          const Text(
            'No lectures yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Record the next class and it lands here.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
