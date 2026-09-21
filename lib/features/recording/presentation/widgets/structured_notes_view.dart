import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../../core/services/notes_parser.dart';
import '../../../../core/theme/app_colors.dart';

/// Renders notes as real UI rather than a wall of markdown.
///
/// Each part gets its own card in the Home palette: the summary on coral,
/// key concepts as numbered term cards on lavender, tasks as tickable rows on
/// mint, deadlines as calendar blocks on cream. When the notes did not follow
/// the expected shape — an AI app that improvised — it falls back to plain
/// markdown so nothing is ever hidden from the student.
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
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        styleSheet: markdownStyle,
        selectable: true,
      );
    }

    final done = notes.tasks.where((t) => t.done).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        if (notes.summary != null)
          _Card(
            tint: AppColors.tintCoral,
            ink: AppColors.inkCoral,
            icon: Icons.auto_awesome_rounded,
            label: 'Summary',
            child: SelectableText(
              notes.summary!,
              style: const TextStyle(
                fontSize: 15,
                height: 1.6,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        if (notes.concepts.isNotEmpty)
          _Card(
            tint: AppColors.tintLavender,
            ink: AppColors.inkLavender,
            icon: Icons.lightbulb_rounded,
            label: 'Key concepts',
            trailing: '${notes.concepts.length}',
            child: Column(
              children: [
                for (var i = 0; i < notes.concepts.length; i++)
                  _Concept(
                    number: i + 1,
                    text: notes.concepts[i],
                    markdownStyle: markdownStyle,
                  ),
              ],
            ),
          ),
        if (notes.tasks.isNotEmpty)
          _Card(
            tint: AppColors.tintMint,
            ink: AppColors.inkMint,
            icon: Icons.checklist_rounded,
            label: 'Tasks',
            trailing: '$done/${notes.tasks.length}',
            child: Column(
              children: [
                _Progress(value: done / notes.tasks.length),
                const SizedBox(height: 8),
                for (final task in notes.tasks)
                  _TaskTile(
                    task: task,
                    onToggle: onToggleTask == null
                        ? null
                        : () => onToggleTask!(task),
                  ),
              ],
            ),
          ),
        if (notes.deadlines.isNotEmpty)
          _Card(
            tint: AppColors.tintCream,
            ink: const Color(0xFFA66E0A),
            icon: Icons.event_rounded,
            label: 'Deadlines',
            child: Column(
              children: [
                for (final deadline in notes.deadlines)
                  _DeadlineTile(deadline: deadline),
              ],
            ),
          ),
        // Whatever the AI wrote under headings we don't know. Last, so
        // nothing the student received is ever hidden from them.
        for (final section in notes.extraSections)
          _Card(
            tint: AppColors.surface,
            ink: AppColors.textSecondary,
            icon: Icons.notes_rounded,
            label: section.title.isEmpty ? 'Also in the notes' : section.title,
            bordered: true,
            child: MarkdownBody(
              data: section.body,
              styleSheet: markdownStyle,
              selectable: true,
            ),
          ),
      ],
    );
  }
}

/// A tinted card with an icon, a label and optional count.
class _Card extends StatelessWidget {
  final Color tint;
  final Color ink;
  final IconData icon;
  final String label;
  final String? trailing;
  final bool bordered;
  final Widget child;

  const _Card({
    required this.tint,
    required this.ink,
    required this.icon,
    required this.label,
    required this.child,
    this.trailing,
    this.bordered = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(22),
        border: bordered ? Border.all(color: AppColors.border) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: ink),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    color: ink,
                  ),
                ),
              ),
              if (trailing != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    trailing!,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: ink,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// "1  **Eigenvector** — a vector A only scales", on a white card.
class _Concept extends StatelessWidget {
  final int number;
  final String text;
  final MarkdownStyleSheet markdownStyle;

  const _Concept({
    required this.number,
    required this.text,
    required this.markdownStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.inkLavender,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: AppColors.textOnPrimary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: MarkdownBody(
              data: text,
              selectable: true,
              styleSheet: markdownStyle.copyWith(
                p: const TextStyle(
                  fontSize: 14.5,
                  height: 1.5,
                  color: AppColors.textPrimary,
                ),
                strong: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppColors.inkLavender,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  final double value;

  const _Progress({required this.value});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(100),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: 6,
          backgroundColor: AppColors.surface.withValues(alpha: 0.7),
          color: AppColors.success,
        ),
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
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
            child: Row(
              children: [
                Semantics(
                  checked: task.done,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: task.done ? AppColors.success : Colors.white,
                      shape: BoxShape.circle,
                      border: task.done
                          ? null
                          : Border.all(color: AppColors.borderStrong, width: 2),
                    ),
                    child: task.done
                        ? const Icon(
                            Icons.check_rounded,
                            size: 15,
                            color: AppColors.textOnPrimary,
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    task.text,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                      color: task.done
                          ? const Color(0xFF958D84)
                          : AppColors.textPrimary,
                      decoration: task.done ? TextDecoration.lineThrough : null,
                    ),
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

class _DeadlineTile extends StatelessWidget {
  final NoteDeadline deadline;

  const _DeadlineTile({required this.deadline});

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
    final date = deadline.date;
    final now = DateTime.now();
    final days = date == null
        ? null
        : DateTime(
            date.year,
            date.month,
            date.day,
          ).difference(DateTime(now.year, now.month, now.day)).inDays;
    final passed = days != null && days < 0;
    const ink = Color(0xFFA66E0A);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 50,
            decoration: BoxDecoration(
              color: passed ? AppColors.surfaceMuted : AppColors.tintCream,
              borderRadius: BorderRadius.circular(12),
            ),
            child: date == null
                ? const Icon(Icons.help_outline_rounded, color: ink)
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${date.day}',
                        style: TextStyle(
                          fontSize: 19,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                          color: passed ? AppColors.textMuted : ink,
                        ),
                      ),
                      Text(
                        _months[date.month - 1],
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: passed ? AppColors.textMuted : ink,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              deadline.description,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.35,
                fontWeight: FontWeight.w700,
                color: passed ? AppColors.textMuted : AppColors.textPrimary,
              ),
            ),
          ),
          if (days != null) ...[
            const SizedBox(width: 8),
            Text(
              switch (days) {
                < 0 => 'Passed',
                0 => 'Today',
                1 => 'Tomorrow',
                _ => 'in $days d',
              },
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: days <= 1 && days >= 0
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
