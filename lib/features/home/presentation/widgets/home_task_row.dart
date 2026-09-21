import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/home_digest.dart';

/// One task, as in the design: a cream card, a tick, the subject's dot and
/// how long is left.
///
/// Tapping the row opens the lecture it came from; tapping the circle ticks
/// the task when [onToggle] is given.
class HomeTaskRow extends StatelessWidget {
  final HomeTask task;
  final VoidCallback onTap;
  final VoidCallback? onToggle;

  const HomeTaskRow({
    super.key,
    required this.task,
    required this.onTap,
    this.onToggle,
  });

  static const _cream = Color(0xFFFDFBF7);

  @override
  Widget build(BuildContext context) {
    final badge = _badge();
    final done = task.done;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: done ? 0.72 : 1,
      child: Material(
        color: _cream,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                _Tick(done: done, onTap: onToggle),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.3,
                          fontWeight: FontWeight.w800,
                          color: done
                              ? const Color(0xFF958D84)
                              : AppColors.textPrimary,
                          decoration: done ? TextDecoration.lineThrough : null,
                          decorationColor: const Color(0xFF958D84),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          // Graded work wears a tag, so it reads apart from
                          // reading and practice at a glance.
                          if (task.isAssignment) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.tintPink,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: const Text(
                                'ASSIGNMENT',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.6,
                                  color: Color(0xFF97245C),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: done
                                  ? AppColors.success
                                  : AppColors.fromHex(task.subjectColor),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              task.subjectName ?? task.recordingTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (badge != null) ...[const SizedBox(width: 8), badge],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// How long is left, when the lecture's notes gave a date to work from.
  Widget? _badge() {
    if (task.done) return null;
    final due = task.dueAt;
    if (due == null) return null;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = DateTime(
      due.year,
      due.month,
      due.day,
    ).difference(today).inDays;

    final (label, background, ink) = switch (days) {
      < 0 => ('Overdue', AppColors.errorBg, AppColors.error),
      0 => ('Today', const Color(0xFFFDEEE7), const Color(0xFFBF4922)),
      1 => ('Tomorrow', const Color(0xFFFEF4DC), const Color(0xFFA66E0A)),
      < 7 => ('${days}d left', AppColors.surfaceMuted, AppColors.textSecondary),
      _ => ('', Colors.transparent, Colors.transparent),
    };
    if (label.isEmpty) return null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.1,
          color: ink,
        ),
      ),
    );
  }
}

/// The round tick. Tappable (with a roomier target) when [onTap] is set.
class _Tick extends StatelessWidget {
  final bool done;
  final VoidCallback? onTap;

  const _Tick({required this.done, this.onTap});

  @override
  Widget build(BuildContext context) {
    final circle = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutBack,
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: done ? AppColors.success : Colors.white,
        shape: BoxShape.circle,
        border: done
            ? null
            : Border.all(color: AppColors.borderStrong, width: 2),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) =>
            ScaleTransition(scale: animation, child: child),
        child: done
            ? const Icon(
                Icons.check_rounded,
                key: ValueKey('done'),
                size: 15,
                color: AppColors.textOnPrimary,
              )
            : const SizedBox.shrink(key: ValueKey('open')),
      ),
    );

    final padded = Padding(padding: const EdgeInsets.all(6), child: circle);
    if (onTap == null) return padded;

    return Semantics(
      label: done ? 'Mark as not done' : 'Mark as done',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: padded,
      ),
    );
  }
}
