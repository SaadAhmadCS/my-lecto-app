import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/dev/sample_data.dart';
import '../../../../core/routes/app_router.dart';
import '../../../timetable/data/timetable_dao.dart';
import '../../../timetable/services/class_reminder_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/error_messages.dart';
import '../../../../core/services/audio_merge_service.dart';
import '../../../../core/services/feedback_service.dart';
import '../../../recording/data/local/recording_feed.dart';
import '../../../../core/constants/transcription_language.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// The app's version, shown in Settings and attached to feedback.
const String appVersion = '1.0.0';

/// Settings screen — app configuration and info.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Settings',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        // Bottom room for the floating nav dock.
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.base,
          AppSpacing.base,
          AppSpacing.base,
          AppSpacing.huge * 2.2,
        ),
        children: [
          const _TimetableCard(),
          const SizedBox(height: AppSpacing.xl),

          // Read-only facts rather than taps that do nothing. Both are
          // compile-time settings; tapping them used to say "Coming soon".
          _buildSection(
            context,
            title: 'Recording',
            children: [
              _SettingsTile(
                icon: Icons.timer_outlined,
                title: 'Split every',
                subtitle:
                    '${AppConstants.defaultChunkDurationMinutes} minutes · '
                    'limits what a crash can cost',
              ),
              _SettingsTile(
                icon: Icons.audiotrack_rounded,
                title: 'Audio quality',
                subtitle:
                    'Voice — HE-AAC '
                    '${AppConstants.audioBitRate ~/ 1000}kbps mono, about '
                    '${(AppConstants.audioBitRate / 8 * 3600 / 1000000).round()}MB an hour',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),

          _buildSection(
            context,
            title: 'Storage',
            children: const [_ClearCacheTile()],
          ),
          const SizedBox(height: AppSpacing.xl),

          _buildSection(
            context,
            title: 'Notes',
            children: const [_TranscriptionLanguageTile()],
          ),
          const SizedBox(height: AppSpacing.xl),

          // Dummy lectures for testing the UI; never in a release build.
          if (kDebugMode) ...[
            _buildSection(
              context,
              title: 'Developer',
              children: const [_SampleDataTile()],
            ),
            const SizedBox(height: AppSpacing.xl),
          ],

          _buildSection(
            context,
            title: 'About',
            children: const [
              _SendFeedbackTile(),
              _SettingsTile(
                icon: Icons.info_outline_rounded,
                title: 'Version',
                subtitle: appVersion,
              ),
              _SettingsTile(
                icon: Icons.lock_outline_rounded,
                title: 'Private by design',
                subtitle:
                    'No account, no internet permission, nothing leaves this '
                    'phone',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: AppColors.textTertiaryDark,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: AppColors.darkSurface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  const Divider(
                    height: 1,
                    indent: AppSpacing.huge,
                    color: AppColors.darkBorder,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppColors.primary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiaryDark,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tells your AI what language the lecture is in, and what to write back in.
class _TranscriptionLanguageTile extends StatefulWidget {
  const _TranscriptionLanguageTile();

  @override
  State<_TranscriptionLanguageTile> createState() =>
      _TranscriptionLanguageTileState();
}

class _TranscriptionLanguageTileState
    extends State<_TranscriptionLanguageTile> {
  TranscriptionLanguage _language = TranscriptionLanguage.auto;

  @override
  void initState() {
    super.initState();
    TranscriptionLanguage.load().then((language) {
      if (mounted) setState(() => _language = language);
    });
  }

  Future<void> _pickLanguage() async {
    final picked = await showDialog<TranscriptionLanguage>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AppColors.darkSurface,
        title: const Text('Lecture language'),
        children: [
          RadioGroup<TranscriptionLanguage>(
            groupValue: _language,
            onChanged: (value) => Navigator.of(ctx).pop(value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final language in TranscriptionLanguage.values)
                  RadioListTile<TranscriptionLanguage>(
                    value: language,
                    title: Text(language.label),
                    subtitle: Text(language.description),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    if (picked == null || picked == _language) return;
    await picked.save();
    if (mounted) setState(() => _language = picked);
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsTile(
      icon: Icons.translate_rounded,
      title: 'Lecture language',
      subtitle: '${_language.label} · told to your AI when you share',
      onTap: _pickLanguage,
    );
  }
}

/// Frees the merged copies made when sharing a lecture.
///
/// Merging a long lecture writes a second copy of its audio, so this can grow
/// to a real size. The copies are rebuilt on the next share, so clearing them
/// costs nothing but a moment.
class _ClearCacheTile extends StatefulWidget {
  const _ClearCacheTile();

  @override
  State<_ClearCacheTile> createState() => _ClearCacheTileState();
}

class _ClearCacheTileState extends State<_ClearCacheTile> {
  int _bytes = 0;
  bool _isWorking = false;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    final bytes = await AudioMergeService.cacheSize();
    if (mounted) setState(() => _bytes = bytes);
  }

  Future<void> _clear() async {
    if (_isWorking) return;
    if (_bytes == 0) {
      _showSnack('Nothing to clear.');
      return;
    }

    setState(() => _isWorking = true);
    final freed = await AudioMergeService.clearAllCaches();
    if (!mounted) return;

    setState(() {
      _bytes = 0;
      _isWorking = false;
    });
    _showSnack('Freed ${_format(freed)}.');
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  static String _format(int bytes) {
    if (bytes >= 1000000) return '${(bytes / 1000000).toStringAsFixed(1)} MB';
    if (bytes >= 1000) return '${(bytes / 1000).round()} KB';
    return '$bytes bytes';
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsTile(
      icon: Icons.cleaning_services_rounded,
      title: 'Clear share cache',
      subtitle: _bytes == 0
          ? 'Nothing cached — your recordings are not affected'
          : '${_format(_bytes)} of merged copies · recordings are kept',
      onTap: _isWorking ? null : _clear,
    );
  }
}

/// The way into the timetable, with a one-line summary of it.
class _TimetableCard extends StatefulWidget {
  const _TimetableCard();

  @override
  State<_TimetableCard> createState() => _TimetableCardState();
}

class _TimetableCardState extends State<_TimetableCard> {
  static const _ink = Color(0xFF7A5B0B);

  String _summary = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final timetable = context.read<TimetableDao>();
    final reminders = context.read<ClassReminderService>();
    final slots = await timetable.list();
    final on = await reminders.isEnabled();
    if (!mounted) return;
    setState(() {
      _summary = slots.isEmpty
          ? 'Get a nudge to record when class starts'
          : '${slots.length} class${slots.length == 1 ? '' : 'es'} a week · '
                'reminders ${on ? 'on' : 'off'}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.tintYellow,
      borderRadius: BorderRadius.circular(21),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await context.push(AppRoutes.timetable);
          if (mounted) _load();
        },
        child: SizedBox(
          height: 96,
          child: Row(
            children: [
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Timetable',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _summary,
                      maxLines: 2,
                      style: TextStyle(
                        color: _ink.withValues(alpha: 0.75),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              SvgPicture.asset(
                'assets/images/timetable.svg',
                width: 88,
                height: 88,
              ),
              const Icon(Icons.chevron_right_rounded, color: _ink),
              const SizedBox(width: 10),
            ],
          ),
        ),
      ),
    );
  }
}

/// Loads or removes the dummy lectures in [SampleData].
class _SampleDataTile extends StatefulWidget {
  const _SampleDataTile();

  @override
  State<_SampleDataTile> createState() => _SampleDataTileState();
}

class _SampleDataTileState extends State<_SampleDataTile> {
  bool _loaded = false;
  bool _isWorking = false;

  @override
  void initState() {
    super.initState();
    SampleData.isLoaded().then((loaded) {
      if (mounted) setState(() => _loaded = loaded);
    });
  }

  Future<void> _toggle() async {
    if (_isWorking) return;
    setState(() => _isWorking = true);

    final loading = !_loaded;
    final reminders = context.read<ClassReminderService>();
    await (loading ? SampleData.seed() : SampleData.clear());
    // The sample timetable comes and goes with it.
    await reminders.reschedule();
    if (!mounted) return;

    setState(() {
      _loaded = loading;
      _isWorking = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(loading ? 'Sample data loaded.' : 'Sample data removed.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsTile(
      icon: _loaded ? Icons.delete_sweep_outlined : Icons.science_outlined,
      title: _loaded ? 'Remove sample data' : 'Load sample data',
      subtitle: _loaded
          ? 'Deletes the dummy lectures · your own are kept'
          : 'BCS-6A: 6 courses, the weekly timetable and 8 lectures',
      onTap: _isWorking ? null : _toggle,
    );
  }
}

/// Opens the share sheet with a feedback note already written.
///
/// There is no server to post to, so feedback travels by whatever messaging
/// app the tester already uses. The prompts and the device details are filled
/// in, because "it didn't work" is not a reportable bug.
class _SendFeedbackTile extends StatelessWidget {
  const _SendFeedbackTile();

  Future<void> _send(BuildContext context) async {
    final feed = context.read<RecordingFeed>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      await FeedbackService.send(
        appVersion: appVersion,
        recordingCount: await feed.total(),
        awaitingCount: await feed.awaitingCount(),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(ErrorMessages.from(e, action: 'send feedback'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsTile(
      icon: Icons.feedback_outlined,
      title: 'Send feedback',
      subtitle: 'Tell me what broke or what is missing',
      onTap: () => _send(context),
    );
  }
}
