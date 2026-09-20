import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/error_messages.dart';
import '../../../../core/routes/app_router.dart';
import '../../../../core/services/ai_share_service.dart';
import '../../../../core/services/notes_parser.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/export_options_sheet.dart';
import '../../../subjects/data/subject_dao.dart';
import '../../data/local/recording_dao.dart';
import '../../data/local/recording_feed.dart';
import '../../data/services/recording_deletion_service.dart';
import '../widgets/paste_notes_sheet.dart';
import '../widgets/recording_audio_player.dart';
import '../widgets/structured_notes_view.dart';
import '../widgets/transcript_search.dart';

/// One recording: its notes, its transcript and its audio.
///
/// Notes arrive by pasting your AI app's reply back in.
class RecordingDetailScreen extends StatefulWidget {
  final String recordingId;
  final String title;

  const RecordingDetailScreen({
    super.key,
    required this.recordingId,
    required this.title,
  });

  @override
  State<RecordingDetailScreen> createState() => _RecordingDetailScreenState();
}

class _RecordingDetailScreenState extends State<RecordingDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final RecordingDao _dao = context.read<RecordingDao>();
  late final SubjectDao _subjectDao = context.read<SubjectDao>();
  late final RecordingDeletionService _deleter = RecordingDeletionService(
    dao: _dao,
  );
  ParsedNotes? _localNotes;
  bool _isSharing = false;

  // State
  String _processingStatus = 'pending';
  String? _transcriptContent;
  String? _summaryContent;
  final int _wordCount = 0;
  bool _isLoading = true;
  String? _error;
  late String _title = widget.title;
  Map<String, dynamic>? _subject;
  DateTime? _recordedAt;
  Duration? _duration;

  // In-transcript search (ORG-013)
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  TranscriptSearchIndex? _searchIndex;
  List<TranscriptMatch> _matches = const [];
  int _currentMatch = 0;
  List<GlobalKey> _paragraphKeys = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  /// Load everything this recording has. There is nowhere else to look.
  Future<void> _load() async {
    try {
      final row = await _dao.getRecording(widget.recordingId);
      final notes = await _dao.getNotes(widget.recordingId);
      final subject = row == null
          ? null
          : await _subjectDao.getSubject(row['subject_id'] as String);

      if (!mounted) return;
      setState(() {
        if (notes != null) {
          _localNotes = NotesParser.parse(notes.notesMarkdown);
          _summaryContent = notes.notesMarkdown;
          _transcriptContent ??= notes.transcriptMarkdown;
        }
        if (row != null) {
          _title = row['title'] as String? ?? _title;
          final durationMs = row['total_duration_ms'] as int?;
          if (durationMs != null && durationMs > 0) {
            _duration ??= Duration(milliseconds: durationMs);
          }
          _recordedAt ??= DateTime.tryParse(row['created_at'] as String? ?? '');
        }
        _subject = subject;
        _processingStatus = _localNotes == null
            ? RecordingFeed.awaitingNotes
            : RecordingFeed.ready;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('RecordingDetail: load failed: $e');
      if (!mounted) return;
      setState(() {
        _error = ErrorMessages.from(e, action: 'open this recording');
        _isLoading = false;
      });
    }
  }

  /// Send this recording's audio and the prompt to the student's AI app.
  Future<void> _shareToAiApp() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);

    try {
      final chunks = await _dao.getChunks(widget.recordingId);
      final paths = chunks
          .map((chunk) => chunk['file_path'] as String)
          .toList(growable: false);

      if (paths.isEmpty) {
        _showSnack('This recording has no audio left on the device.');
        return;
      }


      final prompt = AiShareService.buildPrompt(
        title: _title,
        subjectName: _subject?['name'] as String?,
        recordingDate: _recordedAt,
        duration: _duration,
        // A long lecture's transcript will not fit in one reply, and asking
        // for it costs the notes their detail.
        askForTranscript: AiShareService.shouldRequestTranscript(_duration),
      );

      final shared = await AiShareService.shareToAiApp(
        recordingId: widget.recordingId,
        audioPaths: paths,
        prompt: prompt,
        subjectLabel: _title,
      );

      if (!shared) {
        _showSnack('Couldn\'t find the audio files for this recording.');
      }
    } catch (e) {
      _showSnack(ErrorMessages.from(e, action: 'share this recording'));
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }


  /// Take the AI's reply off the clipboard and turn it into this recording's
  /// notes.
  Future<void> _pasteNotesFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';

    if (text.isEmpty) {
      _showSnack('Copy your AI\'s reply first, then tap Paste notes.');
      return;
    }
    if (text.length < 40) {
      _showSnack('That looks too short to be a set of notes.');
      return;
    }

    final parsed = NotesParser.parse(text);

    if (!mounted) return;
    // Show what is about to be saved first. A stray tap used to overwrite a
    // lecture's notes with whatever happened to be on the clipboard.
    final confirmed = await PasteNotesSheet.show(
      context,
      notes: parsed,
      markdownStyle: _markdownStyleSheet(context),
      replacesExisting: _localNotes != null,
    );
    if (!confirmed || !mounted) return;

    try {
      await _dao.saveNotes(
        id: widget.recordingId,
        notesMarkdown: text,
        transcriptMarkdown: parsed.transcript,
      );

      if (!mounted) return;
      setState(() {
        _localNotes = parsed;
        _summaryContent = text;
        if (parsed.hasTranscript) _transcriptContent = parsed.transcript;
        _processingStatus = RecordingFeed.ready;
        _error = null;
      });

      _showSnack(
        parsed.isStructured
            ? 'Notes saved.'
            : 'Notes saved, though they did not follow the expected format.',
      );
    } catch (e) {
      _showSnack(ErrorMessages.from(e, action: 'save these notes'));
    }
  }

  /// Tick or untick a task, rewriting the stored markdown so the change
  /// survives a restart and flows through to PDF export.
  Future<void> _toggleTask(NoteTask task) async {
    final current = _summaryContent;
    if (current == null) return;

    final updated = NotesParser.toggleTask(current, task);
    if (updated == current) return;

    setState(() {
      _summaryContent = updated;
      _localNotes = NotesParser.parse(updated);
    });

    try {
      await _dao.updateNotesMarkdown(
        id: widget.recordingId,
        notesMarkdown: updated,
      );
    } catch (e) {
      debugPrint('RecordingDetail: failed to persist task toggle: $e');
    }
  }


  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _openSearch() {
    final transcript = _transcriptContent;
    if (transcript == null) return;

    final index = _searchIndex ??= TranscriptSearchIndex(transcript);
    setState(() {
      _isSearching = true;
      _paragraphKeys = List.generate(
        index.paragraphs.length,
        (_) => GlobalKey(),
      );
    });
    _tabController.animateTo(1); // Transcript tab
  }

  void _closeSearch() {
    _searchController.clear();
    setState(() {
      _isSearching = false;
      _matches = const [];
      _currentMatch = 0;
    });
  }

  void _onSearchChanged(String query) {
    setState(() {
      _matches = _searchIndex?.findMatches(query) ?? const [];
      _currentMatch = 0;
    });
    _scrollToCurrentMatch();
  }

  /// Move to the next (+1) or previous (-1) match, wrapping around.
  void _jumpToMatch(int delta) {
    if (_matches.isEmpty) return;
    setState(() {
      _currentMatch = (_currentMatch + delta) % _matches.length;
    });
    _scrollToCurrentMatch();
  }

  void _scrollToCurrentMatch() {
    if (_matches.isEmpty) return;
    final key = _paragraphKeys[_matches[_currentMatch].paragraph];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.3,
        duration: const Duration(milliseconds: 250),
      );
    });
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      autofocus: true,
      textInputAction: TextInputAction.search,
      onChanged: _onSearchChanged,
      onSubmitted: (_) => _jumpToMatch(1),
      style: Theme.of(context).textTheme.bodyLarge,
      decoration: const InputDecoration(
        hintText: 'Search transcript',
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
      ),
    );
  }

  List<Widget> _buildSearchActions() {
    final hasQuery = _searchController.text.trim().isNotEmpty;
    return [
      if (hasQuery)
        Center(
          child: Text(
            _matches.isEmpty
                ? 'No matches'
                : '${_currentMatch + 1} of ${_matches.length}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondaryDark),
          ),
        ),
      IconButton(
        icon: const Icon(Icons.keyboard_arrow_up_rounded),
        tooltip: 'Previous match',
        onPressed: _matches.isEmpty ? null : () => _jumpToMatch(-1),
      ),
      IconButton(
        icon: const Icon(Icons.keyboard_arrow_down_rounded),
        tooltip: 'Next match',
        onPressed: _matches.isEmpty ? null : () => _jumpToMatch(1),
      ),
      IconButton(
        icon: const Icon(Icons.close_rounded),
        tooltip: 'Close search',
        onPressed: _closeSearch,
      ),
    ];
  }

  void _onMenuAction(_DetailAction action) {
    switch (action) {
      case _DetailAction.rename:
        _renameRecording();
      case _DetailAction.move:
        _moveRecording();
      case _DetailAction.copy:
        Clipboard.setData(
          ClipboardData(text: _summaryContent ?? _transcriptContent ?? ''),
        );
        _showSnack('Notes copied to clipboard');
      case _DetailAction.shareToAi:
        _shareToAiApp();
      case _DetailAction.pasteNotes:
        _pasteNotesFromClipboard();
      case _DetailAction.delete:
        _deleteRecording();
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _renameRecording() async {
    final newTitle = await showDialog<String>(
      context: context,
      builder: (_) => _RenameRecordingDialog(initialTitle: _title),
    );

    if (newTitle == null || newTitle.isEmpty || newTitle == _title) return;

    try {
      await _dao.updateRecordingDetails(
        id: widget.recordingId,
        title: newTitle,
      );
      if (!mounted) return;
      setState(() => _title = newTitle);
      _showSnack('Recording renamed');
    } catch (e) {
      _showSnack(ErrorMessages.from(e, action: 'rename the recording'));
    }
  }

  Future<void> _moveRecording() async {
    final currentSubjectId = _subject?['id'] as String?;

    final target = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _subjectDao.listSubjects(),
          builder: (ctx, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.xxl),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              );
            }
            if (snapshot.hasError) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.xxl),
                child: Text(
                  'Could not load subjects',
                  textAlign: TextAlign.center,
                ),
              );
            }

            final subjects = snapshot.data!;
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    0,
                    AppSpacing.xl,
                    AppSpacing.sm,
                  ),
                  child: Text(
                    'Move to…',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (final subject in subjects)
                  ListTile(
                    leading: Icon(
                      Icons.folder_rounded,
                      color: _parseColor(subject['color'] as String?),
                    ),
                    title: Text(subject['name'] as String? ?? 'Untitled'),
                    trailing: subject['id'] == currentSubjectId
                        ? const Icon(
                            Icons.check_rounded,
                            color: AppColors.primary,
                          )
                        : null,
                    enabled: subject['id'] != currentSubjectId,
                    onTap: () => Navigator.of(ctx).pop(subject),
                  ),
              ],
            );
          },
        ),
      ),
    );

    if (target == null) return;

    try {
      await _dao.updateRecordingDetails(
        id: widget.recordingId,
        subjectId: target['id'] as String,
      );
      if (!mounted) return;
      setState(() => _subject = target);
      _showSnack('Moved to ${target['name']}');
    } catch (e) {
      _showSnack(ErrorMessages.from(e, action: 'move the recording'));
    }
  }

  Future<void> _deleteRecording() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: const Text('Delete Recording'),
        // This device holds the only copy there is.
        content: const Text(
          'Delete this recording? The audio and notes are only on this '
          'device, so this cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _deleter.delete(widget.recordingId);
      if (!mounted) return;
      Navigator.of(context).pop();
      _showSnack('Recording deleted');
    } catch (e) {
      _showSnack(ErrorMessages.from(e, action: 'delete the recording'));
    }
  }

  static Color _parseColor(String? hex) {
    try {
      return Color(int.parse((hex ?? '#6366F1').replaceFirst('#', '0xFF')));
    } catch (_) {
      return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        // Always offer a way out. Arriving from a notification tap on a cold
        // start leaves nothing to pop, which previously stranded the user here.
        leading: _isSearching
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Back',
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(AppRoutes.home);
                  }
                },
              ),
        title: _isSearching
            ? _buildSearchField()
            : GestureDetector(
                onTap: _renameRecording,
                child: Text(
                  _title,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
        actions: _isSearching
            ? _buildSearchActions()
            : [
                if (_processingStatus == RecordingFeed.ready &&
                    _transcriptContent != null)
                  IconButton(
                    icon: const Icon(Icons.search_rounded),
                    tooltip: 'Search transcript',
                    onPressed: _openSearch,
                  ),
                if (_processingStatus == RecordingFeed.ready && _summaryContent != null)
                  IconButton(
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    tooltip: 'Export PDF',
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (context) => ExportOptionsSheet(
                          title: _title,
                          subjectName: _subject?['name'] as String?,
                          recordingDate: _recordedAt,
                          duration: _duration,
                          summaryContent: _summaryContent!,
                          transcriptContent: _transcriptContent,
                        ),
                      );
                    },
                  ),
                PopupMenuButton<_DetailAction>(
                  tooltip: 'More',
                  onSelected: _onMenuAction,
                  itemBuilder: (context) => [
                                        const PopupMenuItem(
                      value: _DetailAction.rename,
                      child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Rename'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: _DetailAction.move,
                      child: ListTile(
                        leading: Icon(Icons.drive_file_move_outline),
                        title: Text('Move to…'),
                      ),
                    ),
                    if (_processingStatus == RecordingFeed.ready &&
                        (_summaryContent != null || _transcriptContent != null))
                      const PopupMenuItem(
                        value: _DetailAction.copy,
                        child: ListTile(
                          leading: Icon(Icons.copy_rounded),
                          title: Text('Copy notes'),
                        ),
                      ),
                                        const PopupMenuItem(
                      value: _DetailAction.shareToAi,
                      child: ListTile(
                        leading: Icon(Icons.ios_share_rounded),
                        title: Text('Share audio to your AI'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: _DetailAction.pasteNotes,
                      child: ListTile(
                        leading: Icon(Icons.content_paste_rounded),
                        title: Text('Paste notes'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: _DetailAction.delete,
                      child: ListTile(
                        leading: Icon(
                          Icons.delete_outline_rounded,
                          color: AppColors.error,
                        ),
                        title: Text(
                          'Delete',
                          style: TextStyle(color: AppColors.error),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
        bottom: _processingStatus == RecordingFeed.ready
            ? TabBar(
                controller: _tabController,
                indicatorColor: AppColors.primary,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondaryDark,
                tabs: const [
                  Tab(icon: Icon(Icons.notes_rounded), text: 'Notes'),
                  Tab(
                    icon: Icon(Icons.description_outlined),
                    text: 'Transcript',
                  ),
                ],
              )
            : null,
      ),
      body: _buildBody(),
      // Plays the audio kept on this device, on every tab and state
      bottomNavigationBar: RecordingAudioPlayerBar(
        recordingId: widget.recordingId,
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_error != null) {
      return _buildErrorState();
    }

    if (_processingStatus == RecordingFeed.ready) {
      return TabBarView(
        controller: _tabController,
        children: [_buildSummaryView(), _buildTranscriptView()],
      );
    }

    return _buildAwaitingPasteView();
  }

  /// Shown for a recording with no notes yet. Walks through the round trip in
  /// the order you actually do it.
  Widget _buildAwaitingPasteView() {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const SizedBox(height: AppSpacing.xxl),
        Icon(
          Icons.auto_awesome_rounded,
          size: 56,
          color: AppColors.primary.withValues(alpha: 0.8),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Make notes with your AI',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'This recording stayed on your device. Send it to your own AI app, '
          'then bring the reply back here.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textTertiaryDark,
                height: 1.5,
              ),
        ),
        const SizedBox(height: AppSpacing.xl),
        const _StepRow(
          number: '1',
          text: 'Share the audio — the prompt goes with it as a file.',
        ),
        _StepRow(
          number: '2',
          text: 'Pick ${AiShareService.audioCapableApps.join(', ')}, wait for '
              'the upload, then send.',
        ),
        const _StepRow(
          number: '3',
          text: 'Copy the whole reply and tap Paste notes below.',
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton.icon(
          onPressed: _isSharing ? null : _shareToAiApp,
          icon: _isSharing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.ios_share_rounded),
          label: const Text('Share audio to your AI'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: _pasteNotesFromClipboard,
          icon: const Icon(Icons.content_paste_rounded),
          label: const Text('Paste notes'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'ChatGPT can\'t receive audio, so it won\'t appear in the share sheet '
          'for this.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textTertiaryDark,
              ),
        ),
      ],
    );
  }

  Widget _buildSummaryView() {
    if (_summaryContent == null || _summaryContent!.isEmpty) {
      return const Center(child: Text('Summary not available'));
    }

    // Notes that follow the expected shape get real UI — tickable tasks and a
    // deadlines section. Anything else falls back to plain markdown inside
    // StructuredNotesView, so nothing is ever hidden.
    final parsed = _localNotes ?? NotesParser.parse(_summaryContent!);

    return StructuredNotesView(
      notes: parsed,
      markdownStyle: _markdownStyleSheet(context),
      onToggleTask: parsed.tasks.isEmpty ? null : _toggleTask,
    );
  }

  Widget _buildTranscriptView() {
    if (_transcriptContent == null || _transcriptContent!.isEmpty) {
      // Explain rather than dead-end: in own-AI mode a long lecture is asked
      // for notes only, because its transcript would not fit in one reply.
      final skippedForLength = true &&
          !AiShareService.shouldRequestTranscript(_duration);

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                skippedForLength
                    ? Icons.speaker_notes_off_rounded
                    : Icons.description_outlined,
                size: 40,
                color: AppColors.textTertiaryDark,
              ),
              const SizedBox(height: AppSpacing.base),
              Text(
                skippedForLength
                    ? 'No transcript for long lectures'
                    : 'Transcript not available',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (skippedForLength) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'A lecture this long will not fit in one AI reply, so Lecto '
                  'asked for fuller notes instead. The audio is still on this '
                  'device and can be played below.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiaryDark,
                        height: 1.45,
                      ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Stats bar
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base,
            vertical: AppSpacing.sm,
          ),
          color: AppColors.darkSurface,
          child: Row(
            children: [
              Icon(
                Icons.text_snippet_outlined,
                size: 16,
                color: AppColors.textTertiaryDark,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '$_wordCount words',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiaryDark,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isSearching && _searchController.text.trim().isNotEmpty
              ? SearchableTranscriptView(
                  index: _searchIndex!,
                  matches: _matches,
                  currentMatch: _currentMatch,
                  paragraphKeys: _paragraphKeys,
                )
              : Markdown(
                  data: _transcriptContent!,
                  padding: const EdgeInsets.all(AppSpacing.base),
                  styleSheet: _markdownStyleSheet(context),
                  selectable: true,
                ),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: 48,
              color: AppColors.textTertiaryDark,
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              'Connection Error',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error ?? ErrorMessages.generic,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondaryDark,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _load();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────

  MarkdownStyleSheet _markdownStyleSheet(BuildContext context) {
    return MarkdownStyleSheet(
      h1: Theme.of(context).textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimaryDark,
      ),
      h2: Theme.of(context).textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.primary,
      ),
      h3: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimaryDark,
      ),
      p: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: AppColors.textPrimaryDark,
        height: 1.6,
      ),
      listBullet: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondaryDark),
      code: Theme.of(context).textTheme.bodySmall?.copyWith(
        fontFamily: 'monospace',
        backgroundColor: AppColors.darkSurfaceLight,
        color: AppColors.accent,
      ),
      blockquote: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: AppColors.textSecondaryDark,
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.5),
            width: 3,
          ),
        ),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.darkBorder, width: 1)),
      ),
    );
  }

}

enum _DetailAction { rename, move, copy, shareToAi, pasteNotes, delete }

/// Owns its controller so it's disposed only after the dialog's close
/// animation finishes, not while the TextField is still on screen.
class _RenameRecordingDialog extends StatefulWidget {
  final String initialTitle;

  const _RenameRecordingDialog({required this.initialTitle});

  @override
  State<_RenameRecordingDialog> createState() => _RenameRecordingDialogState();
}

class _RenameRecordingDialogState extends State<_RenameRecordingDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialTitle);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.darkSurface,
      title: const Text('Rename recording'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: AppConstants.maxRecordingTitleLength,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Recording title'),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// One numbered step in the "make notes with your AI" walkthrough.
class _StepRow extends StatelessWidget {
  final String number;
  final String text;

  const _StepRow({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.45,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
