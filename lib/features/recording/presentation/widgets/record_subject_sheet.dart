import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../subjects/data/subject_dao.dart';
import '../../../subjects/presentation/widgets/create_subject_sheet.dart';
import '../../data/local/recording_database.dart';

/// "Which subject is this?" — asked once, right before recording starts.
///
/// Pre-selects the subject recorded most recently, since a student usually
/// walks into the same lecture again. Returns the chosen subject id, or null
/// when dismissed. Quick record returns the Unsorted subject straight away.
class RecordSubjectSheet extends StatefulWidget {
  const RecordSubjectSheet._();

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      backgroundColor: AppColors.surface,
      barrierColor: AppColors.textPrimary.withValues(alpha: 0.35),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const RecordSubjectSheet._(),
    );
  }

  @override
  State<RecordSubjectSheet> createState() => _RecordSubjectSheetState();
}

class _RecordSubjectSheetState extends State<RecordSubjectSheet> {
  late final SubjectDao _subjectDao = context.read<SubjectDao>();

  List<Map<String, dynamic>> _subjects = const [];
  String? _selectedId;

  /// The most recently recorded subject, which gets the "last recorded" line.
  String? _recentId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({String? select}) async {
    List<Map<String, dynamic>> subjects;
    try {
      subjects = (await _subjectDao.listSubjects())
          .where((s) => s['id'] != RecordingDatabase.unsortedSubjectId)
          .toList();
    } catch (_) {
      subjects = const [];
    }

    // Most recently recorded first; never-recorded ones keep name order.
    final byRecent = [...subjects]
      ..sort(
        (a, b) => (b['lastRecordedAt'] as String? ?? '').compareTo(
          a['lastRecordedAt'] as String? ?? '',
        ),
      );
    final recent =
        byRecent.isNotEmpty && byRecent.first['lastRecordedAt'] != null
        ? byRecent.first['id'] as String
        : null;

    if (!mounted) return;
    setState(() {
      _subjects = byRecent;
      _recentId = recent;
      _selectedId =
          select ??
          _selectedId ??
          recent ??
          (subjects.isEmpty ? null : subjects.first['id'] as String);
      _isLoading = false;
    });
  }

  Future<void> _createSubject() async {
    final created = await showCreateSubjectSheet(context);
    if (created == null) return;
    await _load(select: created['id'] as String);
  }

  void _start() {
    Navigator.of(
      context,
    ).pop(_selectedId ?? RecordingDatabase.unsortedSubjectId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
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
            _buildHeader(theme),
            const SizedBox(height: 16),
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
                        for (final subject in _subjects)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _SubjectOption(
                              subject: subject,
                              selected: subject['id'] == _selectedId,
                              isRecent: subject['id'] == _recentId,
                              onTap: () => setState(
                                () => _selectedId = subject['id'] as String,
                              ),
                            ),
                          ),
                        _QuickRecordOption(
                          onTap: () => Navigator.of(
                            context,
                          ).pop(RecordingDatabase.unsortedSubjectId),
                        ),
                        const SizedBox(height: 6),
                        Center(
                          child: TextButton.icon(
                            onPressed: _createSubject,
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              textStyle: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Create new subject'),
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 10),
            _StartButton(onPressed: _isLoading ? null : _start),
            const SizedBox(height: 10),
            Text(
              'Saves in ${AppConstants.defaultChunkDurationMinutes}-min chunks'
              '  ·  Works offline with no signal',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textMuted,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                  children: const [
                    TextSpan(text: 'Which '),
                    TextSpan(
                      text: 'subject',
                      style: TextStyle(color: AppColors.primary),
                    ),
                    TextSpan(text: ' is this?'),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'So the notes land in the right place. You can move it later.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Semantics(
          label: 'Close',
          button: true,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: AppColors.surfaceMuted,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SubjectOption extends StatelessWidget {
  final Map<String, dynamic> subject;
  final bool selected;
  final bool isRecent;
  final VoidCallback onTap;

  const _SubjectOption({
    required this.subject,
    required this.selected,
    required this.isRecent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(subject['color'] as String?);
    final count =
        (subject['_count'] as Map<String, dynamic>?)?['recordings'] as int? ??
        0;
    final lastRecorded = DateTime.tryParse(
      subject['lastRecordedAt'] as String? ?? '',
    );

    final subtitle = isRecent && lastRecorded != null
        ? 'Last recorded ${_relative(lastRecorded)}'
        : count == 0
        ? 'No recordings yet'
        : '$count recording${count == 1 ? '' : 's'}';

    return _OptionFrame(
      selected: selected,
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.folder_rounded,
          size: 20,
          color: selected ? AppColors.textOnPrimary : color,
        ),
      ),
      title: subject['name'] as String? ?? 'Untitled',
      subtitle: subtitle,
      trailing: _Radio(selected: selected),
    );
  }

  /// "today", "yesterday", "3 days ago", "2 weeks ago".
  static String _relative(DateTime when) {
    final now = DateTime.now();
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(when.year, when.month, when.day)).inDays;
    if (days <= 0) return 'today';
    if (days == 1) return 'yesterday';
    if (days < 14) return '$days days ago';
    return '${days ~/ 7} weeks ago';
  }

  static Color _parseColor(String? hex) {
    try {
      return Color(int.parse((hex ?? '').replaceFirst('#', '0xFF')));
    } catch (_) {
      return AppColors.primary;
    }
  }
}

class _QuickRecordOption extends StatelessWidget {
  final VoidCallback onTap;

  const _QuickRecordOption({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _OptionFrame(
      selected: false,
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.tintYellow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.bolt_rounded,
          size: 20,
          color: AppColors.warning,
        ),
      ),
      title: 'Quick record',
      subtitle: 'Sort it out afterwards',
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.textMuted,
      ),
    );
  }
}

/// The card every option sits in: coral outline and tint when selected.
class _OptionFrame extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final Widget leading;
  final String title;
  final String subtitle;
  final Widget trailing;

  const _OptionFrame({
    required this.selected,
    required this.onTap,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? AppColors.tintCoral : AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  final bool selected;

  const _Radio({required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: selected ? AppColors.primary : Colors.transparent,
        shape: BoxShape.circle,
        border: selected
            ? null
            : Border.all(color: AppColors.borderStrong, width: 2),
      ),
      child: selected
          ? const Icon(
              Icons.check_rounded,
              size: 16,
              color: AppColors.textOnPrimary,
            )
          : null,
    );
  }
}

class _StartButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const _StartButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    // The glow lives on an outer box: drawn by Ink it gets clipped to the
    // ink layer and shows as a pale rectangle.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(100),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.30),
            blurRadius: 24,
            spreadRadius: -6,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF57049), Color(0xFFEC5A32)],
            ),
            borderRadius: BorderRadius.circular(100),
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(100),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.mic_rounded,
                  color: AppColors.textOnPrimary,
                  size: 20,
                ),
                SizedBox(width: 8),
                Text(
                  'Start recording',
                  style: TextStyle(
                    color: AppColors.textOnPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
