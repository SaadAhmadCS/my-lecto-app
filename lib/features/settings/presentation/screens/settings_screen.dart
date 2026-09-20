import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/audio_merge_service.dart';
import '../../../../core/constants/transcription_language.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// Settings screen — app configuration and info.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Settings',
          style: Theme.of(context)
              .textTheme
              .headlineMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
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
                subtitle: 'Voice — HE-AAC '
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

          _buildSection(
            context,
            title: 'About',
            children: [
              _SettingsTile(
                icon: Icons.info_outline_rounded,
                title: 'Version',
                subtitle: '1.0.0-alpha',
              ),
              _SettingsTile(
                icon: Icons.code_rounded,
                title: 'Made with',
                subtitle: 'Flutter — everything stays on this device',
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
