import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/motion.dart';

/// Sort orders for recording lists (ORG-005).
enum RecordingSort {
  date('Date (newest)', Icons.schedule_rounded),
  title('Title (A–Z)', Icons.sort_by_alpha_rounded),
  duration('Duration (longest)', Icons.timer_outlined);

  const RecordingSort(this.label, this.icon);

  final String label;
  final IconData icon;

  /// Returns a new list of API recording maps sorted by this order.
  List<Map<String, dynamic>> apply(List<Map<String, dynamic>> recordings) {
    final sorted = [...recordings];
    switch (this) {
      case RecordingSort.date:
        sorted.sort(
          (a, b) => (b['createdAt'] as String? ?? '').compareTo(
            a['createdAt'] as String? ?? '',
          ),
        );
      case RecordingSort.title:
        sorted.sort(
          (a, b) => (a['title'] as String? ?? '').toLowerCase().compareTo(
            (b['title'] as String? ?? '').toLowerCase(),
          ),
        );
      case RecordingSort.duration:
        sorted.sort(
          (a, b) => (b['totalDurationMs'] as int? ?? 0).compareTo(
            a['totalDurationMs'] as int? ?? 0,
          ),
        );
    }
    return sorted;
  }
}

/// App-bar button that picks a [RecordingSort].
class RecordingSortButton extends StatelessWidget {
  final RecordingSort value;
  final ValueChanged<RecordingSort> onChanged;

  const RecordingSortButton({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<RecordingSort>(
      icon: const Icon(Icons.sort_rounded),
      tooltip: 'Sort',
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final sort in RecordingSort.values)
          CheckedPopupMenuItem(
            value: sort,
            checked: sort == value,
            child: Text(sort.label),
          ),
      ],
    );
  }
}

/// Formats a duration as `1h 5m`, `12m 30s` or `45s`.
String formatRecordingDuration(Duration d) {
  if (d.inHours > 0) {
    return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  }
  if (d.inMinutes > 0) {
    return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
  }
  return '${d.inSeconds}s';
}

// ─── Recording Card ────────────────────────────────────────────────

/// The date square in a lecture's subject colour.
///
/// Shared so the card and the lecture's own header draw exactly the same
/// thing — which is what lets one fly into the other.
class RecordingDateBlock extends StatelessWidget {
  final DateTime? date;
  final Color color;
  final double width;
  final double height;

  const RecordingDateBlock({
    super.key,
    required this.date,
    required this.color,
    this.width = 56,
    this.height = 60,
  });

  static const _months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];

  @override
  Widget build(BuildContext context) {
    final ink = Color.lerp(color, Colors.black, 0.35)!;
    final big = height > 62;
    final day = date;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(big ? 18 : 14),
      ),
      child: day == null
          ? Icon(Icons.mic_rounded, color: ink)
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: big ? 26 : 22,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    color: ink,
                  ),
                ),
                Text(
                  _months[day.month - 1],
                  style: TextStyle(
                    fontSize: big ? 11 : 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: ink.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
    );
  }
}

/// One lecture in a list: a date block in its subject's colour, the title,
/// when and how long, and whether it still needs the student's AI.
class RecordingCard extends StatelessWidget {
  final Map<String, dynamic> recording;
  final VoidCallback onTap;
  final bool showSubject;

  const RecordingCard({
    super.key,
    required this.recording,
    required this.onTap,
    this.showSubject = true,
  });

  @override
  Widget build(BuildContext context) {
    final title = recording['title'] as String? ?? 'Untitled';
    final awaiting = recording['processingStatus'] == 'awaiting_paste';
    final created = DateTime.tryParse(recording['createdAt'] as String? ?? '');
    final duration = Duration(
      milliseconds: recording['totalDurationMs'] as int? ?? 0,
    );
    final subject = recording['subject'] as Map<String, dynamic>?;
    final color = AppColors.fromHex(subject?['color'] as String?);
    final meta = [
      if (created != null) _when(created),
      if (duration.inSeconds > 0) formatRecordingDuration(duration),
    ].join(' · ');

    return Pressable(
      scale: 0.98,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () {
            Feel.tap();
            onTap();
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Hero(
                  // Flies up into the lecture's own screen.
                  tag: 'lecture-date-${recording['id']}',
                  child: RecordingDateBlock(date: created, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (showSubject && subject != null) ...[
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                          ],
                          Expanded(
                            child: Text(
                              [
                                if (showSubject && subject != null)
                                  subject['name'] as String? ?? '',
                                meta,
                              ].where((s) => s.isNotEmpty).join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                awaiting
                    ? const _Pill(
                        icon: Icons.auto_awesome_rounded,
                        label: 'Needs AI',
                        background: AppColors.primary,
                        foreground: AppColors.textOnPrimary,
                      )
                    : const _Pill(
                        icon: Icons.check_rounded,
                        label: 'Notes',
                        background: AppColors.successBg,
                        foreground: AppColors.success,
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// "Today 9:10", "Yesterday", "Mon", then the date.
  static String _when(DateTime date) {
    final now = DateTime.now();
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(date.year, date.month, date.day)).inDays;
    final time = '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    if (days == 0) return 'Today $time';
    if (days == 1) return 'Yesterday $time';
    if (days < 7) {
      return '${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][date.weekday - 1]} $time';
    }
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  const _Pill({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}
