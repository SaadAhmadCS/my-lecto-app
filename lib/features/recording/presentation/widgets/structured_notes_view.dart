import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../../core/services/notes_parser.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// Renders notes as real UI rather than a wall of markdown.
///
/// Tasks become checkboxes the student can tick, and deadlines get their own
/// section. When the notes did not follow the expected shape — an AI app that
/// improvised, or older backend notes — it falls back to plain markdown so
/// nothing is ever hidden from the user.
class StructuredNotesView extends StatelessWidget {
  final ParsedNotes notes;
  final MarkdownStyleSheet markdownStyle;

  /// Called with the task that was tapped. The caller rewrites the markdown.
  final ValueChanged<NoteTask>? onToggleTask;

  const StructuredNotesView({
    super.key,
    required this.notes,
    required this.markdownStyle,
    this.onToggleTask,
  });

  @override
  Widget build(BuildContext context) {
    if (!notes.isStructured) {
      return Markdown(
        data: notes.rawMarkdown,
        padding: const EdgeInsets.all(AppSpacing.base),
        styleSheet: markdownStyle,
        selectable: true,
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.base),
      children: [
        if (notes.summary != null) ...[
          _SectionHeader(
            icon: Icons.subject_rounded,
            label: 'Summary',
          ),
          SelectableText(
            notes.summary!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.55,
                ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (notes.concepts.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.lightbulb_outline_rounded,
            label: 'Key concepts',
          ),
          ...notes.concepts.map(
            (concept) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: MarkdownBody(
                data: '• $concept',
                styleSheet: markdownStyle,
                selectable: true,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (notes.tasks.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.checklist_rounded,
            label: 'Tasks',
            trailing: '${notes.tasks.where((t) => t.done).length}'
                '/${notes.tasks.length}',
          ),
          ...notes.tasks.map(
            (task) => _TaskTile(
              task: task,
              onToggle: onToggleTask == null
                  ? null
                  : () => onToggleTask!(task),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (notes.deadlines.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.event_rounded,
            label: 'Deadlines',
          ),
          ...notes.deadlines.map((deadline) => _DeadlineTile(deadline: deadline)),
          const SizedBox(height: AppSpacing.lg),
        ],
        // Whatever the AI wrote under headings we don't know. Rendered last so
        // nothing the student received is ever hidden from them.
        for (final section in notes.extraSections) ...[
          if (section.title.isNotEmpty)
            _SectionHeader(
              icon: Icons.notes_rounded,
              label: section.title,
            ),
          if (section.body.isNotEmpty)
            MarkdownBody(
              data: section.body,
              styleSheet: markdownStyle,
              selectable: true,
            ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? trailing;

  const _SectionHeader({
    required this.icon,
    required this.label,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (trailing != null) ...[
            const Spacer(),
            Text(
              trailing!,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).hintColor,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  final NoteTask task;
  final VoidCallback? onToggle;

  const _TaskTile({required this.task, this.onToggle});

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          height: 1.4,
          decoration: task.done ? TextDecoration.lineThrough : null,
          color: task.done ? Theme.of(context).hintColor : null,
        );

    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              checked: task.done,
              child: Icon(
                task.done
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                size: 22,
                color: task.done
                    ? AppColors.primary
                    : Theme.of(context).hintColor,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(task.text, style: textStyle)),
          ],
        ),
      ),
    );
  }
}

class _DeadlineTile extends StatelessWidget {
  final NoteDeadline deadline;

  const _DeadlineTile({required this.deadline});

  @override
  Widget build(BuildContext context) {
    final date = deadline.date;
    final overdue = date != null && date.isBefore(DateTime.now());

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: overdue
                  ? AppColors.error.withValues(alpha: 0.15)
                  : AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _label(date, deadline.rawDate),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: overdue ? AppColors.error : AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              deadline.description,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.4,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  static String _label(DateTime? date, String rawDate) {
    if (date == null) return rawDate.isEmpty ? 'Date TBC' : rawDate;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }
}
