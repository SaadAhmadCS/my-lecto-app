import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
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
          _buildSection(
            context,
            title: 'Recording',
            children: [
              _SettingsTile(
                icon: Icons.timer_outlined,
                title: 'Chunk Duration',
                subtitle: '15 minutes',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Coming soon'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
              _SettingsTile(
                icon: Icons.audiotrack_rounded,
                title: 'Audio Quality',
                subtitle: 'Voice (HE-AAC '
                    '${AppConstants.audioBitRate ~/ 1000}kbps mono)',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Coming soon'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),

          _buildSection(
            context,
            title: 'Storage',
            children: [
              _SettingsTile(
                icon: Icons.storage_rounded,
                title: 'Auto-Delete Audio',
                subtitle: 'After transcript is confirmed',
                trailing: Switch(
                  value: true,
                  onChanged: (_) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Coming soon'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  activeThumbColor: AppColors.primary,
                ),
              ),
              _SettingsTile(
                icon: Icons.cleaning_services_rounded,
                title: 'Clear Cache',
                subtitle: 'Free up temporary files',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Coming soon'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),

          _buildSection(
            context,
            title: 'AI Processing',
            children: [
              const _TranscriptionLanguageTile(),
              _SettingsTile(
                icon: Icons.bolt_rounded,
                title: 'Auto-Process',
                subtitle: 'Generate notes when recording stops',
                trailing: Switch(
                  value: true,
                  onChanged: (_) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Coming soon'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  activeThumbColor: AppColors.primary,
                ),
              ),
            ],
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
  final Widget? trailing;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
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
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// Picks the language hint sent with new recordings (TRX-015).
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
        title: const Text('Transcription language'),
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
      title: 'Transcription Language',
      subtitle: '${_language.label} · applies to new recordings',
      onTap: _pickLanguage,
    );
  }
}

