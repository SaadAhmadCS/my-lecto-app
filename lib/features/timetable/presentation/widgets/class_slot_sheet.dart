import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/error_messages.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/primary_pill_button.dart';
import '../../../recording/data/local/recording_database.dart';
import '../../../subjects/data/subject_dao.dart';
import '../../../subjects/presentation/widgets/create_subject_sheet.dart';
import '../../data/class_slot.dart';
import '../../data/timetable_dao.dart';

/// Add a class, or edit or delete one.
///
/// Adding takes several days at once, since most classes meet more than once
/// a week. Returns true when something was saved or deleted.
class ClassSlotSheet extends StatefulWidget {
  final ClassSlot? existing;
  final int initialWeekday;

  const ClassSlotSheet._({this.existing, required this.initialWeekday});

  static Future<bool> show(
    BuildContext context, {
    ClassSlot? existing,
    required int weekday,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      backgroundColor: AppColors.surface,
      barrierColor: AppColors.textPrimary.withValues(alpha: 0.35),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) =>
          ClassSlotSheet._(existing: existing, initialWeekday: weekday),
    );
    return saved ?? false;
  }

  @override
  State<ClassSlotSheet> createState() => _ClassSlotSheetState();
}

class _ClassSlotSheetState extends State<ClassSlotSheet> {
  late final SubjectDao _subjectDao = context.read<SubjectDao>();
  late final TimetableDao _timetable = context.read<TimetableDao>();

  List<Map<String, dynamic>> _subjects = const [];
  String? _subjectId;
  late final Set<int> _weekdays;
  late TimeOfDay _start;
  late TimeOfDay _end;
  late final TextEditingController _room;
  late bool _isLab;
  late bool _remind;
  bool _isSaving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final slot = widget.existing;
    _subjectId = slot?.subjectId;
    _weekdays = {slot?.weekday ?? widget.initialWeekday};
    _start = slot?.start ?? const TimeOfDay(hour: 8, minute: 30);
    _end = slot?.end ?? const TimeOfDay(hour: 10, minute: 0);
    _room = TextEditingController(text: slot?.room ?? '');
    _isLab = slot?.isLab ?? false;
    _remind = slot?.remind ?? true;
    _loadSubjects();
  }

  @override
  void dispose() {
    _room.dispose();
    super.dispose();
  }

  Future<void> _loadSubjects({String? select}) async {
    final all = (await _subjectDao.listSubjects())
        .where((s) => s['id'] != RecordingDatabase.unsortedSubjectId)
        .toList();
    // Only courses are offered; the Lab switch picks the lab folder. A lab
    // being edited shows as its course with the switch on.
    final subjects = all.where((s) => s['labOf'] == null).toList();
    var selected = select ?? _subjectId;
    for (final s in all) {
      if (s['id'] == selected && s['labOf'] != null) {
        selected = s['labOf'] as String;
      }
    }
    if (!mounted) return;
    setState(() {
      _subjects = subjects;
      _subjectId = selected;
    });
  }

  Future<void> _newSubject() async {
    final created = await showCreateSubjectSheet(context);
    if (created != null) await _loadSubjects(select: created['id'] as String);
  }

  static int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

  String? get _problem {
    if (_subjectId == null) return 'Pick a subject';
    if (_weekdays.isEmpty) return 'Pick at least one day';
    if (_minutes(_end) <= _minutes(_start)) {
      return 'It has to end after it starts';
    }
    return null;
  }

  Future<void> _pickTime({required bool start}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? _start : _end,
      helpText: start ? 'Class starts' : 'Class ends',
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        // Keep the class length when moving its start.
        final length = _minutes(_end) - _minutes(_start);
        _start = picked;
        final end = (_minutes(picked) + (length > 0 ? length : 90)).clamp(
          0,
          23 * 60 + 59,
        );
        _end = TimeOfDay(hour: end ~/ 60, minute: end % 60);
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _save() async {
    if (_problem != null || _isSaving) return;
    setState(() => _isSaving = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final existing = widget.existing;
      if (existing == null) {
        await _timetable.add(
          subjectId: _subjectId!,
          weekdays: _weekdays.toList()..sort(),
          startMinute: _minutes(_start),
          endMinute: _minutes(_end),
          room: _room.text,
          isLab: _isLab,
          remind: _remind,
        );
      } else {
        await _timetable.update(
          id: existing.id,
          subjectId: _subjectId!,
          weekday: _weekdays.first,
          startMinute: _minutes(_start),
          endMinute: _minutes(_end),
          room: _room.text,
          isLab: _isLab,
          remind: _remind,
        );
      }
      navigator.pop(true);
    } catch (e) {
      setState(() => _isSaving = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(ErrorMessages.from(e, action: 'save the class')),
        ),
      );
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    await _timetable.delete(existing.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final problem = _problem;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _isEditing ? 'Edit class' : 'Add a class',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  _CloseButton(onTap: () => Navigator.of(context).pop(false)),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    const _Label('Subject'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final subject in _subjects)
                          _SubjectChip(
                            name: subject['name'] as String? ?? 'Untitled',
                            color: _parseColor(subject['color'] as String?),
                            selected: subject['id'] == _subjectId,
                            onTap: () => setState(
                              () => _subjectId = subject['id'] as String,
                            ),
                          ),
                        _NewSubjectChip(onTap: _newSubject),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _Label(_isEditing ? 'Day' : 'Days'),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (var day = 1; day <= 7; day++)
                          _DayToggle(
                            letter: ClassSlot.weekdayShort[day - 1][0],
                            label: ClassSlot.weekdayLong[day - 1],
                            selected: _weekdays.contains(day),
                            onTap: () => setState(() {
                              if (_isEditing) {
                                // One class, one day: move it.
                                _weekdays
                                  ..clear()
                                  ..add(day);
                              } else if (!_weekdays.remove(day)) {
                                _weekdays.add(day);
                              }
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const _Label('Time'),
                    Row(
                      children: [
                        Expanded(
                          child: _TimeBox(
                            caption: 'Starts',
                            time: _start,
                            onTap: () => _pickTime(start: true),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                            color: AppColors.textMuted,
                          ),
                        ),
                        Expanded(
                          child: _TimeBox(
                            caption: 'Ends',
                            time: _end,
                            onTap: () => _pickTime(start: false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const _Label('Room'),
                    TextField(
                      controller: _room,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        hintText: 'e.g. G-09 (optional)',
                        prefixIcon: Icon(Icons.place_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SwitchRow(
                      icon: Icons.science_outlined,
                      title: 'It\'s a lab',
                      subtitle:
                          'Its lectures go in the course\'s own lab folder',
                      value: _isLab,
                      onChanged: (v) => setState(() => _isLab = v),
                    ),
                    _SwitchRow(
                      icon: Icons.notifications_active_outlined,
                      title: 'Remind me to record',
                      subtitle: 'A nudge 2 minutes before it starts',
                      value: _remind,
                      onChanged: (v) => setState(() => _remind = v),
                    ),
                    if (_isEditing)
                      Center(
                        child: TextButton.icon(
                          onPressed: _delete,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.error,
                          ),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('Delete this class'),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              PrimaryPillButton(
                label: _isEditing
                    ? 'Save changes'
                    : _weekdays.length > 1
                    ? 'Add ${_weekdays.length} classes'
                    : 'Add class',
                icon: Icons.check_rounded,
                onPressed: problem == null && !_isSaving ? _save : null,
              ),
              if (problem != null && _subjects.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  problem,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Color _parseColor(String? hex) {
    try {
      return Color(int.parse((hex ?? '').replaceFirst('#', '0xFF')));
    } catch (_) {
      return AppColors.primary;
    }
  }
}

class _Label extends StatelessWidget {
  final String text;

  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Close',
      button: true,
      child: GestureDetector(
        onTap: onTap,
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
    );
  }
}

class _SubjectChip extends StatelessWidget {
  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _SubjectChip({
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : AppColors.surface,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: selected ? color : AppColors.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Text(
              name,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewSubjectChip extends StatelessWidget {
  final VoidCallback onTap;

  const _NewSubjectChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.tintCoral,
          borderRadius: BorderRadius.circular(100),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 16, color: AppColors.primary),
            SizedBox(width: 4),
            Text(
              'New subject',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayToggle extends StatelessWidget {
  final String letter;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DayToggle({
    required this.letter,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    begin: Alignment.bottomLeft,
                    end: Alignment.topRight,
                    colors: [AppColors.primary, Color(0xFFFF7B54)],
                  )
                : null,
            color: selected ? null : AppColors.surfaceMuted,
            shape: BoxShape.circle,
          ),
          child: Text(
            letter,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: selected
                  ? AppColors.textOnPrimary
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeBox extends StatelessWidget {
  final String caption;
  final TimeOfDay time;
  final VoidCallback onTap;

  const _TimeBox({
    required this.caption,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final formatted = MaterialLocalizations.of(context).formatTimeOfDay(
      time,
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

    return Material(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                caption,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                formatted,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.textOnPrimary,
            activeTrackColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}
