import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

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
        sorted.sort((a, b) =>
            (b['createdAt'] as String? ?? '').compareTo(a['createdAt'] as String? ?? ''));
      case RecordingSort.title:
        sorted.sort((a, b) => (a['title'] as String? ?? '')
            .toLowerCase()
            .compareTo((b['title'] as String? ?? '').toLowerCase()));
      case RecordingSort.duration:
        sorted.sort((a, b) =>
            (b['totalDurationMs'] as int? ?? 0).compareTo(a['totalDurationMs'] as int? ?? 0));
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

// ─── Recording Card Widget ─────────────────────────────────────────

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
    final status = recording['processingStatus'] as String? ?? 'pending';
    final createdAt = recording['createdAt'] as String?;
    final durationMs = recording['totalDurationMs'] as int? ?? 0;
    final chunkCount = (recording['_count'] as Map<String, dynamic>?)?['chunks'] as int? ?? 0;
    final subject = recording['subject'] as Map<String, dynamic>?;

    final statusInfo = _getStatusInfo(status);
    final duration = Duration(milliseconds: durationMs);
    final timeAgo = _formatTimeAgo(createdAt);

    return Material(
      color: AppColors.darkSurface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Container(
          padding: AppSpacing.cardPadding,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.darkBorder),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _StatusBadge(
                    label: statusInfo.label,
                    color: statusInfo.color,
                    icon: statusInfo.icon,
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.sm),

              // Subject tag
              if (showSubject && subject != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Color(
                      int.parse(
                        (subject['color'] as String? ?? '#6366F1')
                            .replaceFirst('#', '0xFF'),
                      ),
                    ).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Text(
                    subject['name'] as String? ?? '',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Color(
                            int.parse(
                              (subject['color'] as String? ?? '#6366F1')
                                  .replaceFirst('#', '0xFF'),
                            ),
                          ),
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],

              // Meta row
              Row(
                children: [
                  Icon(Icons.schedule_rounded,
                      size: 14, color: AppColors.textTertiaryDark),
                  const SizedBox(width: 4),
                  Text(
                    timeAgo,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiaryDark,
                        ),
                  ),
                  const SizedBox(width: AppSpacing.base),
                  if (duration.inSeconds > 0) ...[
                    Icon(Icons.timer_outlined,
                        size: 14, color: AppColors.textTertiaryDark),
                    const SizedBox(width: 4),
                    Text(
                      formatRecordingDuration(duration),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiaryDark,
                          ),
                    ),
                    const SizedBox(width: AppSpacing.base),
                  ],
                  Icon(Icons.layers_outlined,
                      size: 14, color: AppColors.textTertiaryDark),
                  const SizedBox(width: 4),
                  Text(
                    '$chunkCount chunks',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiaryDark,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  _StatusInfo _getStatusInfo(String status) {
    switch (status) {
      case 'completed':
        return _StatusInfo('Ready', AppColors.success, Icons.check_circle_rounded);
      case 'transcribing':
      case 'transcribed':
      case 'assembling':
      case 'assembled':
      case 'summarizing':
        return _StatusInfo('Processing', AppColors.info, Icons.autorenew_rounded);
      case 'pending':
        return _StatusInfo('Queued', AppColors.warning, Icons.hourglass_empty_rounded);
      // Kept on this device, waiting for the student's own AI app.
      case 'awaiting_paste':
        return _StatusInfo(
          'Needs your AI',
          AppColors.primary,
          Icons.auto_awesome_rounded,
        );
      case 'failed_transcription':
      case 'failed_assembly':
      case 'failed_summary':
        return _StatusInfo('Failed', AppColors.error, Icons.error_outline_rounded);
      default:
        return _StatusInfo('New', AppColors.textTertiaryDark, Icons.fiber_new_rounded);
    }
  }

  String _formatTimeAgo(String? iso) {
    if (iso == null) return '';
    try {
      final date = DateTime.parse(iso);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inDays > 7) {
        return '${date.day}/${date.month}/${date.year}';
      }
      if (diff.inDays > 0) return '${diff.inDays}d ago';
      if (diff.inHours > 0) return '${diff.inHours}h ago';
      if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
      return 'Just now';
    } catch (_) {
      return '';
    }
  }
}

class _StatusInfo {
  final String label;
  final Color color;
  final IconData icon;
  const _StatusInfo(this.label, this.color, this.icon);
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _StatusBadge({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
