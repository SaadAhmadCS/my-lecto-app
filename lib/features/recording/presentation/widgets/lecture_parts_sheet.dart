import 'package:flutter/material.dart';

import '../../../../core/services/ai_share_service.dart';
import '../../../../core/theme/app_colors.dart';

/// Send a long lecture to the AI in parts, and paste each reply back.
///
/// One reply covers about 45 minutes properly. Given more, the apps skim and
/// invent — a lab report and a midterm that were never announced. Each part
/// is shared on its own, and its notes are added to the lecture.
class LecturePartsSheet extends StatefulWidget {
  final List<LecturePart> parts;
  final Set<int> shared;
  final Set<int> pasted;

  /// Share this part's audio. Returns true when the share sheet opened.
  final Future<bool> Function(LecturePart part) onShare;

  /// Paste the reply for this part. Returns true when it was saved.
  final Future<bool> Function(LecturePart part) onPaste;

  const LecturePartsSheet({
    super.key,
    required this.parts,
    required this.shared,
    required this.pasted,
    required this.onShare,
    required this.onPaste,
  });

  static Future<void> show(
    BuildContext context, {
    required List<LecturePart> parts,
    required Set<int> shared,
    required Set<int> pasted,
    required Future<bool> Function(LecturePart part) onShare,
    required Future<bool> Function(LecturePart part) onPaste,
  }) => showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => LecturePartsSheet(
      parts: parts,
      shared: shared,
      pasted: pasted,
      onShare: onShare,
      onPaste: onPaste,
    ),
  );

  @override
  State<LecturePartsSheet> createState() => _LecturePartsSheetState();
}

class _LecturePartsSheetState extends State<LecturePartsSheet> {
  int? _busy;

  Future<void> _run(LecturePart part, Future<bool> Function(LecturePart) f) async {
    setState(() => _busy = part.index);
    try {
      await f(part);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = widget.pasted.length;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
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
          const Text(
            'Send it in parts',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'An AI app listens properly to about 45 minutes at a time. Given '
            'the whole lecture it skims and makes things up. Send each part '
            'in a NEW chat, wait for the upload to finish, then paste its '
            'reply here. The first part you paste starts this lecture\'s '
            'notes over; the rest are added to it.',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppColors.textSecondary.withValues(alpha: 0.95),
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: widget.parts.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final part = widget.parts[i];
                final pasted = widget.pasted.contains(part.index);
                final shared = widget.shared.contains(part.index);
                final busy = _busy == part.index;

                return Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: pasted ? AppColors.success : AppColors.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: pasted
                              ? AppColors.success
                              : AppColors.surfaceMuted,
                          shape: BoxShape.circle,
                        ),
                        child: pasted
                            ? const Icon(
                                Icons.check_rounded,
                                size: 19,
                                color: AppColors.textOnPrimary,
                              )
                            : Text(
                                '${part.index}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              part.range,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              pasted
                                  ? 'Added to your notes'
                                  : shared
                                  ? 'Sent — paste the reply'
                                  : 'Not sent yet',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: pasted
                                    ? AppColors.success
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (busy)
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.primary,
                          ),
                        )
                      else ...[
                        _PartButton(
                          icon: Icons.ios_share_rounded,
                          tooltip: 'Share this part',
                          filled: !shared,
                          onTap: () => _run(part, widget.onShare),
                        ),
                        const SizedBox(width: 6),
                        _PartButton(
                          icon: Icons.content_paste_rounded,
                          tooltip: 'Paste this part\'s reply',
                          filled: shared && !pasted,
                          onTap: () => _run(part, widget.onPaste),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          if (done > 0) ...[
            const SizedBox(height: 12),
            Text(
              '$done of ${widget.parts.length} parts added',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PartButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool filled;
  final VoidCallback onTap;

  const _PartButton({
    required this.icon,
    required this.tooltip,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? AppColors.primary : AppColors.surfaceMuted,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(
              icon,
              size: 18,
              color: filled ? AppColors.textOnPrimary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
