import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/error_messages.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/subject_dao.dart';

/// Ask for a name, teacher and colour and create a subject.
///
/// Returns the new subject, or null if the sheet was dismissed or saving
/// failed (a snack bar says why).
Future<Map<String, dynamic>?> showCreateSubjectSheet(BuildContext context) =>
    showSubjectSheet(context);

/// Create a subject, or edit [existing]: name, teacher and colour.
///
/// Returns the saved subject, or null if nothing was saved.
Future<Map<String, dynamic>?> showSubjectSheet(
  BuildContext context, {
  Map<String, dynamic>? existing,
}) {
  final subjectDao = context.read<SubjectDao>();

  return showModalBottomSheet<Map<String, dynamic>>(
    useRootNavigator: true,
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) =>
        _CreateSubjectSheet(subjectDao: subjectDao, existing: existing),
  );
}

class _CreateSubjectSheet extends StatefulWidget {
  final SubjectDao subjectDao;
  final Map<String, dynamic>? existing;

  const _CreateSubjectSheet({required this.subjectDao, this.existing});

  @override
  State<_CreateSubjectSheet> createState() => _CreateSubjectSheetState();
}

class _CreateSubjectSheetState extends State<_CreateSubjectSheet> {
  late final _nameController = TextEditingController(
    text: widget.existing?['name'] as String? ?? '',
  );
  late final _teacherController = TextEditingController(
    text: widget.existing?['teacher'] as String? ?? '',
  );
  int _colorIndex = 0;
  bool _isSaving = false;

  bool get _isEditing => widget.existing != null;
  bool get _isLab => widget.existing?['isLab'] == true;

  @override
  void initState() {
    super.initState();
    final color = widget.existing?['color'] as String?;
    if (color != null) {
      final index = AppColors.subjectColors.indexWhere(
        (c) => c.toARGB32() == AppColors.fromHex(color).toARGB32(),
      );
      if (index != -1) _colorIndex = index;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _teacherController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _isSaving) return;
    setState(() => _isSaving = true);

    final colorHex =
        '#${AppColors.subjectColors[_colorIndex].toARGB32().toRadixString(16).substring(2)}';
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final teacher = _teacherController.text.trim();

    try {
      final existing = widget.existing;
      if (existing == null) {
        navigator.pop(
          await widget.subjectDao.createSubject(
            name: name,
            color: colorHex,
            teacher: teacher,
          ),
        );
      } else {
        final id = existing['id'] as String;
        await widget.subjectDao.updateSubject(
          id,
          name: name,
          color: colorHex,
          // Empty clears it.
          teacher: teacher,
        );
        navigator.pop(await widget.subjectDao.getSubject(id));
      }
    } catch (e) {
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            ErrorMessages.from(
              e,
              action: _isEditing ? 'save the subject' : 'create the subject',
            ),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.xl,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            _isEditing ? (_isLab ? 'Edit lab' : 'Edit subject') : 'New subject',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xl),
          TextField(
            controller: _nameController,
            autofocus: !_isEditing,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              hintText: 'Subject name (e.g. Calculus)',
              prefixIcon: Icon(
                _isLab ? Icons.science_outlined : Icons.book_outlined,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _teacherController,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => _create(),
            decoration: InputDecoration(
              hintText: _isLab
                  ? 'Lab teacher (optional)'
                  : 'Teacher (optional)',
              prefixIcon: const Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Color',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (var i = 0; i < AppColors.subjectColors.length; i++)
                GestureDetector(
                  onTap: () => setState(() => _colorIndex = i),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.subjectColors[i],
                      borderRadius: BorderRadius.circular(10),
                      border: _colorIndex == i
                          ? Border.all(color: Colors.white, width: 2.5)
                          : null,
                    ),
                    child: _colorIndex == i
                        ? const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 20,
                          )
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _create,
              child: Text(_isEditing ? 'Save changes' : 'Create subject'),
            ),
          ),
        ],
      ),
    );
  }
}
