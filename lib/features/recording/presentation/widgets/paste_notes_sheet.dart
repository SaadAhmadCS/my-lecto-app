import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../../core/services/notes_parser.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import 'structured_notes_view.dart';

/// Shows what is about to be saved, before it is saved.
///
/// Pasting used to commit straight from the clipboard, so a stray tap could
/// silently replace a lecture's notes with whatever happened to be copied.
/// This renders the parsed result with the same widget the Notes tab uses, so
/// what you review is exactly what you get.
///
/// Returns true when the student confirms.
class PasteNotesSheet extends StatelessWidget {
  final ParsedNotes notes;
  final MarkdownStyleSheet markdownStyle;

  /// Warn that saving replaces notes this recording already has.
  final bool replacesExisting;

  const PasteNotesSheet({
    super.key,
    required this.notes,
    required this.markdownStyle,
    this.replacesExisting = false,
  });

  static Future<bool> show(
    BuildContext context, {
    required ParsedNotes notes,
    required MarkdownStyleSheet markdownStyle,
    bool replacesExisting = false,
  }) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PasteNotesSheet(
        notes: notes,
        markdownStyle: markdownStyle,
        replacesExisting: replacesExisting,
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.darkBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.base,
              AppSpacing.xl,
              AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Review notes',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  _summaryLine(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiaryDark,
                      ),
                ),
              ],
            ),
          ),
          if (!notes.isStructured) _warning(context, _unstructuredWarning),
          if (replacesExisting)
            _warning(context, 'Saving replaces the notes already here.'),
          const Divider(height: AppSpacing.base),
          Expanded(
            child: StructuredNotesView(
              notes: notes,
              markdownStyle: markdownStyle,
              // Ticking a box before the notes are saved would be lost.
              onToggleTask: null,
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.sm,
                AppSpacing.xl,
                AppSpacing.base,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md,
                        ),
                      ),
                      child: const Text('Discard'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md,
                        ),
                      ),
                      child: const Text('Save notes'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _unstructuredWarning =
      'This does not look like lecture notes. It will be saved as plain text.';

  /// What the parser found, so problems are obvious before saving.
  String _summaryLine() {
    if (!notes.isStructured) {
      final words = notes.rawMarkdown.trim().split(RegExp(r'\s+')).length;
      return '$words words · no sections recognised';
    }

    final parts = <String>[
      if (notes.summary != null) 'summary',
      if (notes.concepts.isNotEmpty) _count(notes.concepts.length, 'concept'),
      if (notes.tasks.isNotEmpty) _count(notes.tasks.length, 'task'),
      if (notes.deadlines.isNotEmpty)
        _count(notes.deadlines.length, 'deadline'),
      if (notes.hasTranscript) 'transcript',
    ];
    return 'Found ${parts.join(' · ')}';
  }

  static String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

  Widget _warning(BuildContext context, String message) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: AppColors.warning,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.warning,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
