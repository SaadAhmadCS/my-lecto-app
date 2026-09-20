import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../recording/data/local/recording_feed.dart';

/// Home screen — the main landing tab.
///
/// Shows a hero section, quick stats, and recent recordings
/// with their processing status.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final RecordingFeed _feed = context.read<RecordingFeed>();
  List<Map<String, dynamic>> _recentRecordings = [];
  int _totalRecordings = 0;
  bool _isLoading = true;
  bool _hasError = false;

  /// Recordings that still need to be sent to your AI app.
  int _awaitingCount = 0;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    try {
      final recent = await _feed.list(limit: 5);
      final total = await _feed.total();
      final awaiting = await _feed.awaitingCount();

      if (!mounted) return;
      setState(() {
        _recentRecordings = recent;
        _totalRecordings = total;
        _awaitingCount = awaiting;
        _isLoading = false;
        _hasError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.accent],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.mic_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Lecto',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _loadDashboard,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.base),
          children: [
            _buildHeroCard(context),
            const SizedBox(height: AppSpacing.xl),

            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.huge),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            else if (_hasError)
              _buildOfflineHint()
            else if (_recentRecordings.isEmpty)
              _buildEmptyHint()
            else ...[
              if (_awaitingCount > 0) ...[
                _buildAwaitingCard(context),
                const SizedBox(height: AppSpacing.xl),
              ],
              _buildStatsRow(context),
              const SizedBox(height: AppSpacing.xl),
              _buildSectionHeader(context, 'Recent Recordings'),
              const SizedBox(height: AppSpacing.sm),
              ..._recentRecordings.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _RecentRecordingTile(
                    recording: r,
                    onTap: () {
                      final id = r['id'] as String;
                      final title = r['title'] as String? ?? 'Recording';
                      context.push(
                        '/recording/$id?title=${Uri.encodeComponent(title)}',
                      );
                    },
                  ),
                ),
              ),
              if (_totalRecordings > 5) ...[
                const SizedBox(height: AppSpacing.sm),
                Center(
                  child: TextButton(
                    onPressed: () => context.go('/transcripts'),
                    child: Text(
                      'View all $_totalRecordings recordings →',
                      style: TextStyle(color: AppColors.primary),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// Nudge for recordings sitting on this device with no notes yet.
  ///
  /// Nothing else will surface them — no upload, no processing, no
  /// notification — so without this they quietly pile up unnoticed.
  Widget _buildAwaitingCard(BuildContext context) {
    final label = _awaitingCount == 1
        ? '1 recording needs your AI'
        : '$_awaitingCount recordings need your AI';

    return InkWell(
      onTap: () => context.go('/transcripts'),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              color: AppColors.primary,
              size: 22,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Share the audio to your AI app, then paste the reply back',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondaryDark,
                        ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiaryDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryDeep,
            Color(0xFF1E1B3A),
          ],
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: AppColors.accent,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notes from your own AI',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Record → Share → Paste',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondaryDark,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.base),
          // Nothing happens on its own, so the three steps are spelled out.
          // Promising automatic notes would leave a new user waiting for
          // something that never arrives.
          const _HeroStep(
            number: '1',
            text: 'Tap the mic to record your lecture.',
          ),
          const _HeroStep(
            number: '2',
            text: 'Open it and share the audio to Claude, Gemini or Grok.',
          ),
          const _HeroStep(
            number: '3',
            text: 'Copy their reply and paste it back — it becomes your notes.',
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Everything stays on this phone. Nothing is uploaded.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiaryDark,
                  fontStyle: FontStyle.italic,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(BuildContext context) {
    final completedCount = _recentRecordings
        .where((r) => r['processingStatus'] == 'completed')
        .length;
    final processingCount = _recentRecordings
        .where((r) {
          final s = r['processingStatus'] as String? ?? '';
          return s == 'transcribing' || s == 'summarizing' || s == 'assembling';
        })
        .length;

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Total',
            value: '$_totalRecordings',
            icon: Icons.mic_rounded,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StatCard(
            label: 'Ready',
            value: '$completedCount',
            icon: Icons.check_circle_outline_rounded,
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StatCard(
            label: 'Processing',
            value: '$processingCount',
            icon: Icons.autorenew_rounded,
            color: AppColors.info,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
    );
  }

  Widget _buildEmptyHint() {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxxl),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.mic_none_rounded,
              size: 56,
              color: AppColors.textTertiaryDark,
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              'No recordings yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.textSecondaryDark,
                  ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Tap the mic button to start',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiaryDark,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineHint() {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxxl),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: AppColors.textTertiaryDark,
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              'Offline Mode',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.textSecondaryDark,
                  ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'You can still record — data will sync later.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiaryDark,
                  ),
            ),
            const SizedBox(height: AppSpacing.xl),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _hasError = false;
                });
                _loadDashboard();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Stat Card ─────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textTertiaryDark,
                ),
          ),
        ],
      ),
    );
  }
}

// ─── Recent Recording Tile ─────────────────────────────────────────

class _RecentRecordingTile extends StatelessWidget {
  final Map<String, dynamic> recording;
  final VoidCallback onTap;

  const _RecentRecordingTile({
    required this.recording,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = recording['title'] as String? ?? 'Untitled';
    final status = recording['processingStatus'] as String? ?? 'pending';
    final createdAt = recording['createdAt'] as String?;
    final subject = recording['subject'] as Map<String, dynamic>?;
    final subjectName = subject?['name'] as String?;

    return Material(
      color: AppColors.darkSurface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.darkBorder),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Row(
            children: [
              // Status icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _statusColor(status).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _statusIcon(status),
                  color: _statusColor(status),
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (subjectName != null) subjectName,
                        if (createdAt != null) _timeAgo(createdAt),
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiaryDark,
                          ),
                    ),
                  ],
                ),
              ),

              // Arrow
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiaryDark,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(String s) {
    if (s == 'completed') return AppColors.success;
    if (s == 'awaiting_paste') return AppColors.primary;
    if (s.startsWith('failed')) return AppColors.error;
    if (s == 'transcribing' || s == 'summarizing' || s == 'assembling') {
      return AppColors.info;
    }
    return AppColors.warning;
  }

  IconData _statusIcon(String s) {
    if (s == 'completed') return Icons.check_circle_rounded;
    if (s == 'awaiting_paste') return Icons.auto_awesome_rounded;
    if (s.startsWith('failed')) return Icons.error_outline_rounded;
    if (s == 'transcribing' || s == 'summarizing' || s == 'assembling') {
      return Icons.autorenew_rounded;
    }
    return Icons.hourglass_empty_rounded;
  }

  String _timeAgo(String iso) {
    try {
      final d = DateTime.parse(iso);
      final diff = DateTime.now().difference(d);
      if (diff.inDays > 7) return '${d.day}/${d.month}/${d.year}';
      if (diff.inDays > 0) return '${diff.inDays}d ago';
      if (diff.inHours > 0) return '${diff.inHours}h ago';
      if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
      return 'Just now';
    } catch (_) {
      return '';
    }
  }
}

/// One numbered step in the "how this works" card on Home.
class _HeroStep extends StatelessWidget {
  final String number;
  final String text;

  const _HeroStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiaryDark,
                    height: 1.45,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
