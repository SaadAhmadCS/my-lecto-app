import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/errors/error_messages.dart';
import '../../core/services/pdf_export_service.dart';
import '../../core/theme/app_colors.dart';
import 'primary_pill_button.dart';

/// Download or share a lecture's notes as a PDF.
class ExportOptionsSheet extends StatefulWidget {
  final String title;
  final String? subjectName;
  final DateTime? recordingDate;
  final Duration? duration;
  final String summaryContent;
  final String? transcriptContent;

  const ExportOptionsSheet({
    super.key,
    required this.title,
    this.subjectName,
    this.recordingDate,
    this.duration,
    required this.summaryContent,
    this.transcriptContent,
  });

  @override
  State<ExportOptionsSheet> createState() => _ExportOptionsSheetState();
}

class _ExportOptionsSheetState extends State<ExportOptionsSheet> {
  bool _includeTranscript = false;
  bool _isWorking = false;

  bool get _hasTranscript =>
      widget.transcriptContent != null && widget.transcriptContent!.isNotEmpty;

  String get _filename => PdfExportService.generateFilename(
    subjectName: widget.subjectName,
    date: widget.recordingDate,
    title: widget.title,
  );

  Future<Uint8List?> _build() async {
    try {
      return await PdfExportService.generatePdf(
        title: widget.title,
        subjectName: widget.subjectName,
        recordingDate: widget.recordingDate,
        duration: widget.duration,
        summaryMarkdown: widget.summaryContent,
        transcriptMarkdown: widget.transcriptContent,
        includeTranscript: _includeTranscript,
      );
    } catch (e) {
      _snack(ErrorMessages.from(e, action: 'create the PDF'));
      return null;
    }
  }

  Future<void> _download() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isWorking = true);
    final bytes = await _build();
    if (bytes == null) return _done();

    final saved = await PdfExportService.saveToDownloads(bytes, _filename);
    if (saved) {
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Saved to Downloads · $_filename')),
      );
    } else {
      // Older Android: hand it to the share sheet, which can save it too.
      await PdfExportService.sharePdf(bytes, _filename);
      if (mounted) navigator.pop();
    }
  }

  Future<void> _share() async {
    setState(() => _isWorking = true);
    final bytes = await _build();
    if (bytes == null) return _done();
    await PdfExportService.sharePdf(bytes, _filename);
    if (mounted) Navigator.of(context).pop();
  }

  void _done() {
    if (mounted) setState(() => _isWorking = false);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
            'Save as PDF',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          // What is going into the file.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 54,
                  decoration: BoxDecoration(
                    color: AppColors.tintCoral,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.picture_as_pdf_rounded,
                    color: AppColors.primary,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _includeTranscript
                            ? 'Notes, assignments, quizzes + transcript'
                            : 'Notes, assignments, quizzes and dates',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            value: _includeTranscript && _hasTranscript,
            onChanged: _hasTranscript
                ? (v) => setState(() => _includeTranscript = v)
                : null,
            activeThumbColor: AppColors.textOnPrimary,
            activeTrackColor: AppColors.primary,
            title: const Text(
              'Include the full transcript',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            subtitle: Text(
              _hasTranscript
                  ? 'Added on its own pages at the end'
                  : 'This lecture has no transcript',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          PrimaryPillButton(
            label: _isWorking ? 'Making your PDF…' : 'Download PDF',
            icon: Icons.download_rounded,
            onPressed: _isWorking ? null : _download,
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: _isWorking ? null : _share,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              icon: const Icon(Icons.ios_share_rounded),
              label: const Text('Share'),
            ),
          ),
        ],
      ),
    );
  }
}
