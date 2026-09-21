import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/class_slot.dart';
import '../../data/timetable_dao.dart';
import '../../services/class_reminder_service.dart';
import '../widgets/class_slot_sheet.dart';

/// Your weekly classes, and the reminders that come with them.
///
/// Each class with reminders on sends a "start recording" nudge a couple of
/// minutes before it begins, so a lecture is not lost to walking in late.
class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen>
    with WidgetsBindingObserver {
  late final TimetableDao _timetable = context.read<TimetableDao>();
  late final ClassReminderService _reminders = context
      .read<ClassReminderService>();

  List<ClassSlot> _slots = const [];
  int _day = DateTime.now().weekday;
  bool _remindersOn = true;
  bool _exact = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Coming back from a system permission screen (or the permission prompt
  /// itself, which pauses the app): re-check and reapply.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isLoading) {
      _load(reschedule: true);
    }
  }

  Future<void> _load({bool reschedule = false}) async {
    if (reschedule) await _reminders.reschedule();
    final slots = await _timetable.list();
    final on = await _reminders.isEnabled();
    final exact = await _reminders.canBeExact();
    final notify = await _reminders.canNotify();
    if (!mounted) return;
    setState(() {
      _slots = slots;
      _remindersOn = on;
      _exact = exact;
      _canNotify = notify;
      _isLoading = false;
    });

    // Reminders that cannot be shown are worse than none: ask the moment
    // there is something to remind about. Once per screen visit.
    if (on && slots.isNotEmpty && !notify && !_askedToNotify) {
      _askedToNotify = true;
      await _allowNotifications();
    }
  }

  bool _canNotify = true;
  bool _askedToNotify = false;

  /// Prompt for notifications. After a permanent refusal Android no longer
  /// shows the prompt, so a deliberate tap goes to the app's settings page.
  Future<void> _allowNotifications({bool fromTap = false}) async {
    final allowed = await _reminders.askToNotify();
    if (!allowed && fromTap) await openAppSettings();
    final notify = await _reminders.canNotify();
    if (mounted) setState(() => _canNotify = notify);
  }

  List<ClassSlot> get _today =>
      _slots.where((slot) => slot.weekday == _day).toList();

  Future<void> _edit(ClassSlot? slot) async {
    final saved = await ClassSlotSheet.show(
      context,
      existing: slot,
      weekday: slot?.weekday ?? _day,
    );
    if (saved) await _load(reschedule: true);
  }

  Future<void> _toggleReminders(bool on) async {
    setState(() => _remindersOn = on);
    await _reminders.setEnabled(on);
  }

  Future<void> _toggleSlot(ClassSlot slot) async {
    await _timetable.setRemind(slot.id, !slot.remind);
    await _load(reschedule: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(
          'Timetable',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      floatingActionButton: _isLoading
          ? null
          : FloatingActionButton.extended(
              heroTag: 'timetable_add_fab',
              onPressed: () => _edit(null),
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textOnPrimary,
              shape: const StadiumBorder(),
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Add class',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
              children: [
                _HeroCard(classCount: _slots.length),
                const SizedBox(height: 14),
                _RemindersCard(
                  on: _remindersOn,
                  exact: _exact,
                  canNotify: _canNotify,
                  hasClasses: _slots.isNotEmpty,
                  onChanged: _toggleReminders,
                  onAllowExact: _reminders.requestExact,
                  onAllowNotifications: () =>
                      _allowNotifications(fromTap: true),
                ),
                const SizedBox(height: 22),
                _DayStrip(
                  selected: _day,
                  counts: {
                    for (var day = 1; day <= 7; day++)
                      day: _slots.where((s) => s.weekday == day).length,
                  },
                  onSelected: (day) => setState(() => _day = day),
                ),
                const SizedBox(height: 18),
                Text(
                  _today.isEmpty
                      ? ClassSlot.weekdayLong[_day - 1]
                      : '${ClassSlot.weekdayLong[_day - 1]} · '
                            '${_today.length} class${_today.length == 1 ? '' : 'es'}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                if (_today.isEmpty)
                  _EmptyDay(day: _day, onAdd: () => _edit(null))
                else
                  for (final slot in _today)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ClassCard(
                        slot: slot,
                        remindersOn: _remindersOn,
                        onTap: () => _edit(slot),
                        onToggleRemind: () => _toggleSlot(slot),
                      ),
                    ),
              ],
            ),
    );
  }
}

/// "Never miss recording a class", with the calendar-and-clock illustration.
class _HeroCard extends StatelessWidget {
  final int classCount;

  const _HeroCard({required this.classCount});

  static const _ink = Color(0xFF7A5B0B);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 128,
      decoration: BoxDecoration(
        color: AppColors.tintYellow,
        borderRadius: BorderRadius.circular(21),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 4,
            bottom: 0,
            child: SvgPicture.asset(
              'assets/images/timetable.svg',
              width: 120,
              height: 120,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 130, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Never miss\nrecording a class',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 18,
                    height: 1.2,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  classCount == 0
                      ? 'Add your classes to get nudged'
                      : '$classCount class${classCount == 1 ? '' : 'es'} a week',
                  style: TextStyle(
                    color: _ink.withValues(alpha: 0.75),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
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

class _RemindersCard extends StatelessWidget {
  final bool on;
  final bool exact;
  final bool canNotify;
  final bool hasClasses;
  final ValueChanged<bool> onChanged;
  final VoidCallback onAllowExact;
  final VoidCallback onAllowNotifications;

  const _RemindersCard({
    required this.on,
    required this.exact,
    required this.canNotify,
    required this.hasClasses,
    required this.onChanged,
    required this.onAllowExact,
    required this.onAllowNotifications,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: on ? AppColors.tintCoral : AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  on
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_off_outlined,
                  size: 21,
                  color: on ? AppColors.primary : AppColors.textMuted,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Class reminders',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'A nudge 2 minutes before each class · tap it to '
                      'start recording',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: on,
                onChanged: onChanged,
                activeThumbColor: AppColors.textOnPrimary,
                activeTrackColor: AppColors.primary,
              ),
            ],
          ),
          // Reminders that cannot be shown come first: they fire on time and
          // are silently dropped, which looks exactly like the feature failing.
          // Without exact alarms Android batches a reminder into a window of
          // up to an hour (seen on a Pixel 7, Android 16) — by which time the
          // class is half over. Both are worth saying plainly.
          if (on && hasClasses && !canNotify) ...[
            const SizedBox(height: 10),
            _Fix(
              icon: Icons.notifications_off_rounded,
              text:
                  'Notifications are off, so no reminder can appear. '
                  'Tap to allow them.',
              color: AppColors.error,
              background: AppColors.errorBg,
              onTap: onAllowNotifications,
            ),
          ] else if (on && hasClasses && !exact) ...[
            const SizedBox(height: 10),
            _Fix(
              icon: Icons.schedule_rounded,
              text:
                  'Android may delay reminders by up to an hour. Tap and '
                  'turn on "Allow setting alarms" so they arrive on time.',
              color: AppColors.warning,
              background: AppColors.warningBg,
              onTap: onAllowExact,
            ),
          ],
        ],
      ),
    );
  }
}

/// A tappable one-line problem with its fix, inside the reminders card.
class _Fix extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final Color background;
  final VoidCallback onTap;

  const _Fix({
    required this.icon,
    required this.text,
    required this.color,
    required this.background,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayStrip extends StatelessWidget {
  final int selected;
  final Map<int, int> counts;
  final ValueChanged<int> onSelected;

  const _DayStrip({
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().weekday;

    return Row(
      children: [
        for (var day = 1; day <= 7; day++) ...[
          if (day > 1) const SizedBox(width: 6),
          Expanded(
            child: Semantics(
              button: true,
              selected: day == selected,
              label:
                  '${ClassSlot.weekdayLong[day - 1]}, '
                  '${counts[day]} classes',
              child: GestureDetector(
                onTap: () => onSelected(day),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 62,
                  decoration: BoxDecoration(
                    gradient: day == selected
                        ? const LinearGradient(
                            begin: Alignment.bottomLeft,
                            end: Alignment.topRight,
                            colors: [AppColors.primary, Color(0xFFFF7B54)],
                          )
                        : null,
                    color: day == selected ? null : AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: day == selected
                        ? null
                        : Border.all(
                            color: day == today
                                ? AppColors.primary.withValues(alpha: 0.45)
                                : AppColors.border,
                          ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        ClassSlot.weekdayShort[day - 1],
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: day == selected
                              ? AppColors.textOnPrimary
                              : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 5),
                      // One dot per class, up to four.
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (
                            var i = 0;
                            i < (counts[day] ?? 0).clamp(0, 4);
                            i++
                          )
                            Container(
                              width: 4,
                              height: 4,
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(
                                color: day == selected
                                    ? AppColors.textOnPrimary
                                    : AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          if ((counts[day] ?? 0) == 0)
                            const SizedBox(height: 4),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ClassCard extends StatelessWidget {
  final ClassSlot slot;
  final bool remindersOn;
  final VoidCallback onTap;
  final VoidCallback onToggleRemind;

  const _ClassCard({
    required this.slot,
    required this.remindersOn,
    required this.onTap,
    required this.onToggleRemind,
  });

  @override
  Widget build(BuildContext context) {
    final color = slot.color;
    final localizations = MaterialLocalizations.of(context);
    final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    String format(TimeOfDay t) =>
        localizations.formatTimeOfDay(t, alwaysUse24HourFormat: use24);
    final isNow = slot.isOnAt(DateTime.now(), earlyBy: Duration.zero);
    final nudging = remindersOn && slot.remind;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Time rail
        SizedBox(
          width: 62,
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  format(slot.start),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  format(slot.end),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Material(
            color: color.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: color, width: 4)),
                ),
                padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  slot.subjectName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              if (slot.isLab) ...[
                                const SizedBox(width: 6),
                                _Chip(label: 'LAB', color: color),
                              ],
                              if (isNow) ...[
                                const SizedBox(width: 6),
                                const _Chip(
                                  label: 'NOW',
                                  color: AppColors.primary,
                                  filled: true,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.schedule_rounded,
                                size: 13,
                                color: AppColors.textSecondary.withValues(
                                  alpha: 0.8,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _length(slot.length),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              if (slot.room != null) ...[
                                const SizedBox(width: 10),
                                Icon(
                                  Icons.place_outlined,
                                  size: 13,
                                  color: AppColors.textSecondary.withValues(
                                    alpha: 0.8,
                                  ),
                                ),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    slot.room!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: remindersOn ? onToggleRemind : null,
                      tooltip: slot.remind
                          ? 'Turn off this reminder'
                          : 'Remind me for this class',
                      icon: Icon(
                        nudging
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_off_outlined,
                        size: 20,
                        color: nudging ? color : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _length(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours == 0) return '$minutes min';
    if (minutes == 0) return '$hours hr';
    return '$hours hr $minutes min';
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final bool filled;

  const _Chip({required this.label, required this.color, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: filled ? color : AppColors.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: filled ? AppColors.textOnPrimary : color,
        ),
      ),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  final int day;
  final VoidCallback onAdd;

  const _EmptyDay({required this.day, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          SvgPicture.asset(
            'assets/images/day_off.svg',
            width: 110,
            height: 110,
          ),
          Text(
            'No classes on ${ClassSlot.weekdayLong[day - 1]}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Enjoy the day off, or add a class for it.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onAdd,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add a class'),
          ),
        ],
      ),
    );
  }
}
