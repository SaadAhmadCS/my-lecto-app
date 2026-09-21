import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_messages.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../recording/data/local/recording_dao.dart';
import '../../../recording/data/local/recording_feed.dart';
import '../../../recording/data/services/recording_deletion_service.dart';
import '../../../../shared/widgets/recording_card.dart';

/// Every recording on this device, with sorting and a filter for the ones
/// still waiting to be sent to your AI app.
class TranscriptsScreen extends StatefulWidget {
  const TranscriptsScreen({super.key});

  @override
  State<TranscriptsScreen> createState() => _TranscriptsScreenState();
}

class _TranscriptsScreenState extends State<TranscriptsScreen> {
  late final RecordingFeed _feed = context.read<RecordingFeed>();
  late final RecordingDeletionService _deleter = RecordingDeletionService(
    dao: context.read<RecordingDao>(),
  );
  List<Map<String, dynamic>> _recordings = [];
  RecordingSort _sort = RecordingSort.date;
  bool _isLoading = true;
  String? _error;

  /// Show only recordings still waiting to be sent to the student's own AI.
  ///
  /// Once someone has a term's worth of lectures, the handful that still need
  /// them is what they actually came to the list for.
  bool _onlyAwaiting = false;

  static bool _isAwaiting(Map<String, dynamic> recording) =>
      recording['processingStatus'] == RecordingFeed.awaitingNotes;

  int get _awaitingCount => _recordings.where(_isAwaiting).length;

  List<Map<String, dynamic>> get _visibleRecordings =>
      _onlyAwaiting ? _recordings.where(_isAwaiting).toList() : _recordings;

  @override
  void initState() {
    super.initState();
    _loadRecordings();
  }

  Future<void> _loadRecordings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final recordings = await _feed.list();

      if (!mounted) return;
      setState(() {
        _recordings = _sort.apply(recordings);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorMessages.from(e);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Transcripts',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          RecordingSortButton(
            value: _sort,
            onChanged: (sort) => setState(() {
              _sort = sort;
              _recordings = sort.apply(_recordings);
            }),
          ),
        ],
      ),
      body: _buildBody(),
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

    if (_recordings.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      children: [
        if (_awaitingCount > 0) _buildFilterBar(),
        Expanded(child: _buildList()),
      ],
    );
  }

  /// Only shown when something is actually waiting, so the list stays plain
  /// for anyone not using their own AI app.
  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.sm,
        AppSpacing.base,
        0,
      ),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('All'),
            selected: !_onlyAwaiting,
            selectedColor: AppColors.primary,
            onSelected: (_) => setState(() => _onlyAwaiting = false),
          ),
          const SizedBox(width: AppSpacing.sm),
          ChoiceChip(
            // No avatar: a selected chip already draws a checkmark there, and
            // the two icons collide.
            label: Text('Needs your AI · $_awaitingCount'),
            selected: _onlyAwaiting,
            selectedColor: AppColors.primary,
            onSelected: (_) => setState(() => _onlyAwaiting = true),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final visible = _visibleRecordings;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadRecordings,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.base),
        itemCount: visible.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final recording = visible[index];
          final id = recording['id'] as String;
          return Dismissible(
            key: Key(id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: AppSpacing.xl),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.white,
              ),
            ),
            confirmDismiss: (direction) async {
              return await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: AppColors.darkSurface,
                  title: const Text('Delete Recording'),
                  // This device holds the only copy there is.
                  content: const Text(
                    'Delete this recording? The audio and notes are only on '
                    'this device, so this cannot be undone.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
            },
            onDismissed: (direction) async {
              try {
                // Removes the rows, the audio on disk and any merged copy.
                await _deleter.delete(id);
                setState(() {
                  // Remove by id: with a filter on, the visible index is not
                  // the index into _recordings.
                  _recordings.removeWhere((r) => r['id'] == id);
                });
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Recording deleted')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        ErrorMessages.from(e, action: 'delete the recording'),
                      ),
                    ),
                  );
                }
              }
            },
            child: RecordingCard(
              recording: recording,
              onTap: () => _navigateToDetail(recording),
            ),
          );
        },
      ),
    );
  }

  void _navigateToDetail(Map<String, dynamic> recording) {
    final id = recording['id'] as String;
    final title = recording['title'] as String? ?? 'Recording';
    context.push('/recording/$id?title=${Uri.encodeComponent(title)}');
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primaryDeep,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.description_outlined,
              size: 40,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'No transcripts yet',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
            child: Text(
              'Record a lecture to generate your first transcript.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondaryDark,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton.icon(
            onPressed: () => context.push('/record'),
            icon: const Icon(Icons.mic_rounded),
            label: const Text('Start Recording'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          ),
        ],
      ),
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
              'Could not load recordings',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error ?? ErrorMessages.generic,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondaryDark,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            OutlinedButton.icon(
              onPressed: _loadRecordings,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
