import 'package:flutter/material.dart';
import '../../core/errors/error_messages.dart';
import '../../core/services/pdf_export_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

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
  bool _isGenerating = false;

  Future<void> _handleExport() async {
    setState(() => _isGenerating = true);
    try {
      final pdfBytes = await PdfExportService.generatePdf(
        title: widget.title,
        subjectName: widget.subjectName,
        recordingDate: widget.recordingDate,
        duration: widget.duration,
        summaryMarkdown: widget.summaryContent,
        transcriptMarkdown: widget.transcriptContent,
        includeTranscript: _includeTranscript,
      );

      if (!mounted) return;
      await PdfExportService.sharePdf(pdfBytes, widget.title);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorMessages.from(e, action: 'create the PDF')),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.only(
        top: AppSpacing.sm,
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        bottom: AppSpacing.xxl,
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
                color: AppColors.darkBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Export Notes',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Preview Info:\nTitle: ${widget.title}'
            '${widget.recordingDate != null ? '\nDate: ${widget.recordingDate}' : ''}'
            '${widget.duration != null ? '\nDuration: ${widget.duration}' : ''}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Include full transcript'),
              Switch(
                value: _includeTranscript,
                onChanged: widget.transcriptContent != null
                    ? (val) => setState(() => _includeTranscript = val)
                    : null,
                activeThumbColor: AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            onPressed: _isGenerating ? null : _handleExport,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            ),
            child: _isGenerating
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Export PDF'),
          ),
        ],
      ),
    );
  }
}
