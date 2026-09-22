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

  /// Opens the study guide, which lives on its own tab so these notes stay
  /// short enough to take in at a glance.
  final VoidCallback? onOpenStudyGuide;

  const StructuredNotesView({
    super.key,
    required this.notes,
    required this.markdownStyle,
    this.onToggleTask,
    this.onOpenStudyGuide,
  });

  /// The study guide's type: roomy body text and bold topic headings.
  static MarkdownStyleSheet studyGuideStyle(MarkdownStyleSheet base) =>
      base.copyWith(
        p: base.p?.copyWith(fontSize: 15.5, height: 1.65),
        listBullet: base.listBullet?.copyWith(fontSize: 15.5),
        h3: const TextStyle(
          fontSize: 19,
          height: 1.3,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.3,
          color: AppColors.textPrimary,
        ),
        h3Padding: const EdgeInsets.only(top: 22, bottom: 4),
      );

  /// "12 min read", at an unhurried 200 words a minute.
  static String readingTime(String markdown) {
    final words = markdown.trim().split(RegExp(r'\s+')).length;
    return '${(words / 200).ceil()} min read';
  }

  /// Topic headings in the study guide.
  static int topicCount(String markdown) =>
      RegExp(r'^###\s', multiLine: true).allMatches(markdown).length;

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

    final tasksDone = notes.tasks.where((t) => t.done).length;
    final assignmentsDone = notes.assignments.where((t) => t.done).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        // First, so it cannot be scrolled past: what the lecturer stressed.
        if (notes.important.isNotEmpty)
          _CalloutCard.dontMiss(items: notes.important),
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
        if (notes.studyGuide != null)
          _StudyGuideCard(guide: notes.studyGuide!, onOpen: onOpenStudyGuide),
        if (notes.assignments.isNotEmpty)
          _Card(
            tint: AppColors.tintPink,
            ink: _assignmentInk,
            icon: Icons.assignment_rounded,
            label: 'Assignments',
            trailing: '$assignmentsDone/${notes.assignments.length}',
            child: Column(
              children: [
                for (final assignment in notes.assignments)
                  _TaskTile(
                    task: assignment,
                    accent: _assignmentInk,
                    onToggle: onToggleTask == null
                        ? null
                        : () => onToggleTask!(assignment),
                  ),
              ],
            ),
          ),
        if (notes.quizzes.isNotEmpty)
          _Card(
            tint: AppColors.tintSky,
            ink: AppColors.inkSky,
            icon: Icons.quiz_rounded,
            label: 'Quizzes & exams',
            trailing: '${notes.quizzes.length}',
            child: Column(
              children: [
                for (final quiz in notes.quizzes)
                  _DatedTile(
                    date: quiz.date,
                    title: quiz.title,
                    details: quiz.details,
                    ink: AppColors.inkSky,
                    tint: AppColors.tintSky,
                  ),
              ],
            ),
          ),
        // Beside the quizzes they help with.
        if (notes.examHints.isNotEmpty)
          _CalloutCard.examHints(items: notes.examHints),
        if (notes.tasks.isNotEmpty)
          _Card(
            tint: AppColors.tintMint,
            ink: AppColors.inkMint,
            icon: Icons.checklist_rounded,
            label: 'Tasks',
            trailing: '$tasksDone/${notes.tasks.length}',
            child: Column(
              children: [
                _Progress(value: tasksDone / notes.tasks.length),
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
        if (notes.deadlines.isNotEmpty)
          _Card(
            tint: AppColors.tintCream,
            ink: const Color(0xFFA66E0A),
            icon: Icons.event_rounded,
            label: 'Other dates',
            child: Column(
              children: [
                for (final deadline in notes.deadlines)
                  _DatedTile(
                    date: deadline.date,
                    title: deadline.description,
                    ink: const Color(0xFFA66E0A),
                    tint: AppColors.tintCream,
                  ),
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

  static const _assignmentInk = Color(0xFF97245C);
}

/// The way into the study guide: how long it is and how many topics.
class _StudyGuideCard extends StatelessWidget {
  final String guide;
  final VoidCallback? onOpen;

  const _StudyGuideCard({required this.guide, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final topics = StructuredNotesView.topicCount(guide);
    final details = [
      if (topics > 0) '$topics topic${topics == 1 ? '' : 's'}',
      StructuredNotesView.readingTime(guide),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: AppColors.navBar,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.menu_book_rounded,
                    color: AppColors.textOnPrimary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Study guide',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textOnPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Everything taught, in full · $details',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textOnPrimary.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                if (onOpen != null)
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: AppColors.textOnPrimary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A list that must stand out from the tinted cards around it.
///
/// "Don't miss" is the lecturer's announcements, in coral. "Exam hints" is
/// what they let slip about exams, on the dark ink of the nav bar with an
/// amber label — the part a student revisits before every quiz.
class _CalloutCard extends StatelessWidget {
  final List<String> items;
  final String label;
  final IconData icon;
  final List<Color> gradient;
  final Color labelColor;
  final Color shadow;

  const _CalloutCard.dontMiss({required this.items})
    : label = "DON'T MISS",
      icon = Icons.priority_high_rounded,
      gradient = const [Color(0xFFF57049), Color(0xFFEC5A32)],
      labelColor = AppColors.textOnPrimary,
      shadow = AppColors.primary;

  const _CalloutCard.examHints({required this.items})
    : label = 'EXAM HINTS',
      icon = Icons.tips_and_updates_rounded,
      gradient = const [Color(0xFF2A2320), Color(0xFF1C1715)],
      labelColor = const Color(0xFFFFC857),
      shadow = const Color(0xFF1C1715);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: shadow.withValues(alpha: 0.25),
            blurRadius: 18,
            spreadRadius: -6,
            offset: const Offset(0, 8),
          ),
        ],
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
                  color: AppColors.textOnPrimary.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: labelColor),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                  color: labelColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 7, right: 10),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: labelColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      item.replaceAll('**', ''),
                      style: const TextStyle(
                        fontSize: 14.5,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textOnPrimary,
                      ),
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

/// "Today", "Tomorrow", "in 5 d", "Passed" — or null with no date.
String? _countdown(DateTime? date) {
  if (date == null) return null;
  final now = DateTime.now();
  final days = DateTime(
    date.year,
    date.month,
    date.day,
  ).difference(DateTime(now.year, now.month, now.day)).inDays;
  return switch (days) {
    < 0 => 'Passed',
    0 => 'Today',
    1 => 'Tomorrow',
    _ => 'in $days d',
  };
}

/// A tickable task or assignment. Assignments add their due date and the
/// details the lecture gave (how to submit, marks).
class _TaskTile extends StatelessWidget {
  final NoteTask task;
  final VoidCallback? onToggle;

  /// Colour for the due line; an assignment's pink ink.
  final Color accent;

  const _TaskTile({
    required this.task,
    this.onToggle,
    this.accent = AppColors.textSecondary,
  });

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final due = task.due;
    final countdown = _countdown(due);
    final soon = countdown == 'Today' || countdown == 'Tomorrow';

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
              crossAxisAlignment: CrossAxisAlignment.start,
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.text,
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                          color: task.done
                              ? const Color(0xFF958D84)
                              : AppColors.textPrimary,
                          decoration: task.done
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (due != null && !task.done) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(
                              Icons.event_rounded,
                              size: 13,
                              color: soon ? AppColors.primary : accent,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Due ${due.day} ${_months[due.month - 1]}'
                              ' · $countdown',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: soon ? AppColors.primary : accent,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (task.details != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          task.details!,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
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

/// A dated item — a quiz or another date — with a calendar block, its
/// details underneath and how far off it is.
class _DatedTile extends StatelessWidget {
  final DateTime? date;
  final String title;
  final String? details;
  final Color ink;
  final Color tint;

  const _DatedTile({
    required this.date,
    required this.title,
    required this.ink,
    required this.tint,
    this.details,
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
    final date = this.date;
    final countdown = _countdown(date);
    final passed = countdown == 'Passed';
    final soon = countdown == 'Today' || countdown == 'Tomorrow';

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
              color: passed ? AppColors.surfaceMuted : tint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: date == null
                ? Icon(Icons.event_busy_rounded, color: ink, size: 20)
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: passed ? AppColors.textMuted : AppColors.textPrimary,
                  ),
                ),
                if (details != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    details!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                if (date == null)
                  const Text(
                    'Date not given yet',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          if (countdown != null) ...[
            const SizedBox(width: 8),
            Text(
              countdown,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: soon ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
