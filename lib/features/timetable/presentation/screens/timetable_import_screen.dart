import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/errors/error_messages.dart';
import '../../../../core/services/ai_share_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/primary_pill_button.dart';
import '../../../subjects/data/subject_dao.dart';
import '../../data/class_slot.dart';
import '../../data/timetable_dao.dart';
import '../../services/class_reminder_service.dart';
import '../../services/timetable_import.dart';

/// Fill the timetable from a screenshot, read by the student's own AI.
///
/// Three steps — choose the screenshot, share it with the instructions, paste
/// the reply — then a review of every class before anything is saved. Pops
/// with the number of classes imported.
class TimetableImportScreen extends StatefulWidget {
  const TimetableImportScreen({super.key});

  @override
  State<TimetableImportScreen> createState() => _TimetableImportScreenState();
}

class _TimetableImportScreenState extends State<TimetableImportScreen> {
  late final TimetableDao _timetable = context.read<TimetableDao>();
  late final SubjectDao _subjects = context.read<SubjectDao>();
  late final ClassReminderService _reminders = context
      .read<ClassReminderService>();

  XFile? _image;
  bool _shared = false;
  TimetableParse? _parse;

  /// Names of subjects that already exist, to tell new courses apart.
  List<String> _knownSubjects = const [];
  int _existingClasses = 0;
  bool _replace = true;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final subjects = await _subjects.listSubjects();
    final slots = await _timetable.list();
    if (!mounted) return;
    setState(() {
      _knownSubjects = [for (final s in subjects) s['name'] as String? ?? ''];
      _existingClasses = slots.length;
    });
  }

  Future<void> _pickImage() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image != null && mounted) setState(() => _image = image);
  }

  Future<void> _share() async {
    final image = _image;
    if (image == null) return;
    try {
      final prompt = await AiShareService.writePromptFile(
        TimetableImport.prompt,
      );
      await SharePlus.instance.share(
        ShareParams(
          // Instructions first: apps that trim to a file limit keep the
          // earliest.
          files: [
            XFile(prompt.path, mimeType: 'text/plain'),
            image,
          ],
          text: TimetableImport.prompt,
          subject: 'My timetable',
        ),
      );
      if (mounted) setState(() => _shared = true);
    } catch (e) {
      _snack(ErrorMessages.from(e, action: 'share the screenshot'));
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _snack('Copy your AI\'s reply first, then tap Paste reply.');
      return;
    }

    final parse = TimetableImport.parse(text);
    if (parse.isEmpty) {
      _snack(
        'No classes found in that. Copy the AI\'s whole reply — the lines '
        'that look like "Monday | 08:30 | 10:00 | …".',
      );
      return;
    }
    setState(() => _parse = parse);
  }

  Future<void> _import() async {
    final parse = _parse;
    if (parse == null || _isBusy) return;
    setState(() => _isBusy = true);
    final navigator = Navigator.of(context);

    try {
      await _timetable.importClasses(
        parse.classes,
        replace: _replace && _existingClasses > 0,
        palette: [
          for (final c in AppColors.subjectColors)
            '#${c.toARGB32().toRadixString(16).substring(2)}',
        ],
      );
      await _reminders.reschedule();
      navigator.pop(parse.classes.length);
    } catch (e) {
      setState(() => _isBusy = false);
      _snack(ErrorMessages.from(e, action: 'import the timetable'));
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parse = _parse;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(
          'Import timetable',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          const _Hero(),
          const SizedBox(height: 18),
          _Step(
            number: 1,
            done: _image != null,
            title: 'Choose your timetable',
            body: 'A screenshot or a clear photo of it.',
            action: _image == null
                ? _StepButton(
                    icon: Icons.image_outlined,
                    label: 'Choose screenshot',
                    onTap: _pickImage,
                  )
                : _PickedImage(image: _image!, onChange: _pickImage),
          ),
          const SizedBox(height: 10),
          _Step(
            number: 2,
            done: _shared,
            title: 'Send it to your AI',
            body:
                'Claude, Gemini, ChatGPT or Grok. The instructions go with '
                'it, so just press send.',
            action: _StepButton(
              icon: Icons.ios_share_rounded,
              label: _shared ? 'Share again' : 'Share to your AI',
              onTap: _image == null ? null : _share,
            ),
          ),
          const SizedBox(height: 10),
          _Step(
            number: 3,
            done: parse != null,
            title: 'Paste the reply',
            body: 'Copy the AI\'s whole answer, then come back here.',
            action: _StepButton(
              icon: Icons.content_paste_rounded,
              label: parse == null ? 'Paste reply' : 'Paste a new reply',
              onTap: _paste,
              filled: _shared && parse == null,
            ),
          ),
          if (parse != null) ...[
            const SizedBox(height: 26),
            _Review(
              parse: parse,
              newSubjects: [
                for (final name in parse.subjects)
                  if (!_knownSubjects.any(
                    (known) => TimetableImport.sameCourse(known, name),
                  ))
                    name,
              ],
            ),
            if (_existingClasses > 0) ...[
              const SizedBox(height: 14),
              _ReplaceToggle(
                existing: _existingClasses,
                value: _replace,
                onChanged: (v) => setState(() => _replace = v),
              ),
            ],
            const SizedBox(height: 18),
            PrimaryPillButton(
              label:
                  'Import ${parse.classes.length} '
                  'class${parse.classes.length == 1 ? '' : 'es'}',
              icon: Icons.download_done_rounded,
              onPressed: _isBusy ? null : _import,
            ),
          ],
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 132,
      decoration: BoxDecoration(
        color: AppColors.tintLavender,
        borderRadius: BorderRadius.circular(21),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 2,
            bottom: 0,
            child: SvgPicture.asset(
              'assets/images/timetable_import.svg',
              width: 128,
              height: 128,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 136, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Snap it, share it,\npaste it back',
                  style: TextStyle(
                    color: AppColors.inkLavender,
                    fontSize: 18,
                    height: 1.2,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your AI reads the screenshot. Your whole week, in a minute.',
                  style: TextStyle(
                    color: AppColors.inkLavender.withValues(alpha: 0.75),
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final bool done;
  final String title;
  final String body;
  final Widget action;

  const _Step({
    required this.number,
    required this.done,
    required this.title,
    required this.body,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: done ? AppColors.success : AppColors.tintCoral,
              shape: BoxShape.circle,
            ),
            child: done
                ? const Icon(
                    Icons.check_rounded,
                    size: 17,
                    color: AppColors.textOnPrimary,
                  )
                : Text(
                    '$number',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                action,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// The next thing to do gets the solid coral treatment.
  final bool filled;

  const _StepButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final background = filled ? AppColors.primary : AppColors.tintCoral;
    final foreground = filled ? AppColors.textOnPrimary : AppColors.primary;

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(100),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(100),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: foreground),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickedImage extends StatelessWidget {
  final XFile image;
  final VoidCallback onChange;

  const _PickedImage({required this.image, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            File(image.path),
            width: 64,
            height: 48,
            fit: BoxFit.cover,
            cacheWidth: 192,
          ),
        ),
        const SizedBox(width: 10),
        TextButton(
          onPressed: onChange,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
          child: const Text('Change'),
        ),
      ],
    );
  }
}

/// Everything the reply held, by day, for a last look before saving.
class _Review extends StatelessWidget {
  final TimetableParse parse;
  final List<String> newSubjects;

  const _Review({required this.parse, required this.newSubjects});

  @override
  Widget build(BuildContext context) {
    final classes = parse.classes;
    final courses = parse.subjects.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Found ${classes.length} class${classes.length == 1 ? '' : 'es'} · '
          '$courses course${courses == 1 ? '' : 's'}',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Check it against your timetable. You can edit any class after.',
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
        if (parse.skipped > 0) ...[
          const SizedBox(height: 10),
          _Notice(
            icon: Icons.warning_amber_rounded,
            color: AppColors.warning,
            background: AppColors.warningBg,
            text:
                '${parse.skipped} line${parse.skipped == 1 ? '' : 's'} '
                'could not be read. Add ${parse.skipped == 1 ? 'it' : 'them'} '
                'by hand if something is missing.',
          ),
        ],
        if (newSubjects.isNotEmpty) ...[
          const SizedBox(height: 10),
          _Notice(
            icon: Icons.create_new_folder_outlined,
            color: AppColors.inkLavender,
            background: AppColors.tintLavender,
            text: newSubjects.length == 1
                ? 'New subject: ${newSubjects.single}'
                : '${newSubjects.length} new subjects: '
                      '${newSubjects.join(', ')}',
          ),
        ],
        const SizedBox(height: 14),
        for (var day = 1; day <= 7; day++)
          if (classes.any((c) => c.weekday == day)) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 6),
              child: Text(
                ClassSlot.weekdayLong[day - 1].toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  for (final c in classes.where((c) => c.weekday == day))
                    _ReviewRow(item: c),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final ImportedClass item;

  const _ReviewRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    String time(int minutes) => localizations.formatTimeOfDay(
      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      alwaysUse24HourFormat: use24,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(
              time(item.startMinute),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  [
                    'until ${time(item.endMinute)}',
                    if (item.room != null) item.room!,
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (item.isLab)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.tintLavender,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'LAB',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: AppColors.inkLavender,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;
  final String text;

  const _Notice({
    required this.icon,
    required this.color,
    required this.background,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplaceToggle extends StatelessWidget {
  final int existing;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ReplaceToggle({
    required this.existing,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.swap_horiz_rounded,
            size: 22,
            color: AppColors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replace my current $existing '
                  'class${existing == 1 ? '' : 'es'}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  value
                      ? 'Your old timetable is cleared first'
                      : 'These are added alongside it',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.textOnPrimary,
            activeTrackColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}
