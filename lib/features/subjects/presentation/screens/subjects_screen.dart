import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/errors/error_messages.dart';
import '../../data/subject_dao.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// Subjects screen — organize lectures by subject/course.
///
/// Shows a grid of user-created subjects with color-coded cards.
/// Supports creating new subjects and viewing recordings per subject.
class SubjectsScreen extends StatefulWidget {
  const SubjectsScreen({super.key});

  @override
  State<SubjectsScreen> createState() => _SubjectsScreenState();
}

class _SubjectsScreenState extends State<SubjectsScreen> {
  late final SubjectDao _subjectDao = context.read<SubjectDao>();
  List<Map<String, dynamic>> _subjects = [];
  bool _isLoading = true;
  bool _hasError = false;
  bool _isGridView = true;

  static const _viewModePrefKey = 'subjectsGridView';

  @override
  void initState() {
    super.initState();
    _loadViewMode();
    _loadSubjects();
  }

  Future<void> _loadViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    final isGrid = prefs.getBool(_viewModePrefKey);
    if (isGrid != null && mounted) setState(() => _isGridView = isGrid);
  }

  Future<void> _toggleViewMode() async {
    setState(() => _isGridView = !_isGridView);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_viewModePrefKey, _isGridView);
  }

  Future<void> _loadSubjects() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

        try {
      final subjects = await _subjectDao.listSubjects();

      if (mounted) {
        setState(() {
          _subjects = subjects;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  void _showCreateDialog() {
    final nameController = TextEditingController();
    int selectedColorIndex = 0;

    showModalBottomSheet(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: AppSpacing.xl,
                right: AppSpacing.xl,
                top: AppSpacing.xl,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.xl,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
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
                    'New Subject',
                    style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Name input
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Subject name (e.g. Calculus)',
                      prefixIcon: Icon(Icons.book_outlined),
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Color picker
                  Text(
                    'Color',
                    style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                      color: AppColors.textSecondaryDark,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: List.generate(
                      AppColors.subjectColors.length,
                      (i) => GestureDetector(
                        onTap: () =>
                            setSheetState(() => selectedColorIndex = i),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.subjectColors[i],
                            borderRadius: BorderRadius.circular(10),
                            border: selectedColorIndex == i
                                ? Border.all(color: Colors.white, width: 2.5)
                                : null,
                          ),
                          child: selectedColorIndex == i
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 20,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  // Create button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final name = nameController.text.trim();
                        if (name.isEmpty) return;

                        Navigator.of(ctx).pop();
                        final colorHex =
                            '#${AppColors.subjectColors[selectedColorIndex].toARGB32().toRadixString(16).substring(2)}';

                        try {
                          await _subjectDao.createSubject(name: name, color: colorHex);
                          _loadSubjects();
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(ErrorMessages.from(e, action: 'create the subject')),
                                backgroundColor: AppColors.error,
                              ),
                            );
                          }
                        }
                      },
                      child: const Text('Create Subject'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showEditDialog(Map<String, dynamic> subject) {
    final id = subject['id'] as String;
    final currentName = subject['name'] as String? ?? '';
    final colorStr = subject['color'] as String? ?? '#6366F1';

    final nameController = TextEditingController(text: currentName);

    int selectedColorIndex = 0;
    try {
      final cardColor = Color(int.parse(colorStr.replaceFirst('#', '0xFF')));
      final index = AppColors.subjectColors.indexWhere(
        (c) => c.toARGB32() == cardColor.toARGB32(),
      );
      if (index != -1) {
        selectedColorIndex = index;
      }
    } catch (_) {}

    showModalBottomSheet(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: AppSpacing.xl,
                right: AppSpacing.xl,
                top: AppSpacing.xl,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.xl,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
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
                    'Edit Subject',
                    style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Name input
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Subject name (e.g. Calculus)',
                      prefixIcon: Icon(Icons.book_outlined),
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Color picker
                  Text(
                    'Color',
                    style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                      color: AppColors.textSecondaryDark,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: List.generate(
                      AppColors.subjectColors.length,
                      (i) => GestureDetector(
                        onTap: () =>
                            setSheetState(() => selectedColorIndex = i),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.subjectColors[i],
                            borderRadius: BorderRadius.circular(10),
                            border: selectedColorIndex == i
                                ? Border.all(color: Colors.white, width: 2.5)
                                : null,
                          ),
                          child: selectedColorIndex == i
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 20,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final name = nameController.text.trim();
                        if (name.isEmpty) return;

                        Navigator.of(ctx).pop();
                        final colorHex =
                            '#${AppColors.subjectColors[selectedColorIndex].toARGB32().toRadixString(16).substring(2)}';

                        try {
                          await _subjectDao.updateSubject(
                            id,
                            name: name,
                            color: colorHex,
                          );
                          _loadSubjects();
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(ErrorMessages.from(e, action: 'update the subject')),
                                backgroundColor: AppColors.error,
                              ),
                            );
                          }
                        }
                      },
                      child: const Text('Save Changes'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Subjects',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: _toggleViewMode,
            tooltip: _isGridView ? 'List view' : 'Grid view',
            icon: Icon(
              _isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
            ),
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        heroTag: 'subjects_add_fab',
        onPressed: _showCreateDialog,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_hasError) {
      return Center(
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
              'Could not load subjects',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
            OutlinedButton.icon(
              onPressed: _loadSubjects,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_subjects.isEmpty) {
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
                Icons.folder_outlined,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'No subjects yet',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
              child: Text(
                'Create your first subject to organize your lectures.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondaryDark,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadSubjects,
      child: _isGridView ? _buildGrid() : _buildList(),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.base),
      itemCount: _subjects.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) => _SubjectListRow(
        subject: _subjects[index],
        onTap: () => _openSubject(_subjects[index]),
        onMore: () => _showSubjectMenu(_subjects[index]),
      ),
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.base),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
        childAspectRatio: 1.4,
      ),
      itemCount: _subjects.length,
      itemBuilder: (context, index) => _SubjectCard(
        subject: _subjects[index],
        onTap: () => _openSubject(_subjects[index]),
        onMore: () => _showSubjectMenu(_subjects[index]),
      ),
    );
  }

  Future<void> _openSubject(Map<String, dynamic> subject) async {
    await context.push('/subjects/${subject['id']}');
    // Recording counts may have changed
    if (mounted) _loadSubjects();
  }

  void _showSubjectMenu(Map<String, dynamic> subject) {
    showModalBottomSheet(
      useRootNavigator: true,
      context: context,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit subject'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showEditDialog(subject);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.error,
              ),
              title: const Text(
                'Delete subject',
                style: TextStyle(color: AppColors.error),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _deleteSubject(subject['id'] as String);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSubject(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: const Text('Delete Subject?'),
        content: const Text('Its recordings will be moved to Unsorted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _subjectDao.deleteSubject(id);
        _loadSubjects();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(ErrorMessages.from(e, action: 'delete the subject')),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }
}

// ─── Subject Card ──────────────────────────────────────────────────

class _SubjectCard extends StatelessWidget {
  final Map<String, dynamic> subject;
  final VoidCallback onTap;
  final VoidCallback onMore;

  const _SubjectCard({
    required this.subject,
    required this.onTap,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final name = subject['name'] as String? ?? 'Untitled';
    final colorStr = subject['color'] as String? ?? '#6366F1';
    final recordingCount =
        (subject['_count'] as Map<String, dynamic>?)?['recordings'] as int? ??
        0;

    Color cardColor;
    try {
      cardColor = Color(int.parse(colorStr.replaceFirst('#', '0xFF')));
    } catch (_) {
      cardColor = AppColors.primary;
    }

    return Material(
      color: AppColors.darkSurface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InkWell(
        onTap: onTap,
        onLongPress: onMore,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Container(
          padding: AppSpacing.cardPadding,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.darkBorder),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Color dot + menu
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: cardColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.folder_rounded,
                      color: cardColor,
                      size: 20,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: onMore,
                    tooltip: 'Subject options',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.more_vert_rounded,
                      size: 18,
                      color: AppColors.textTertiaryDark,
                    ),
                  ),
                ],
              ),
              const Spacer(),

              // Name
              Text(
                name,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '$recordingCount recording${recordingCount == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiaryDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Subject List Row ──────────────────────────────────────────────

/// Compact row for the list view: color dot, name, recording count.
class _SubjectListRow extends StatelessWidget {
  final Map<String, dynamic> subject;
  final VoidCallback onTap;
  final VoidCallback onMore;

  const _SubjectListRow({
    required this.subject,
    required this.onTap,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final name = subject['name'] as String? ?? 'Untitled';
    final recordingCount =
        (subject['_count'] as Map<String, dynamic>?)?['recordings'] as int? ??
        0;

    Color color;
    try {
      color = Color(
        int.parse(
          (subject['color'] as String? ?? '#6366F1').replaceFirst('#', '0xFF'),
        ),
      );
    } catch (_) {
      color = AppColors.primary;
    }

    return Material(
      color: AppColors.darkSurface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: ListTile(
        onTap: onTap,
        onLongPress: onMore,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          side: const BorderSide(color: AppColors.darkBorder),
        ),
        leading: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '$recordingCount recording${recordingCount == 1 ? '' : 's'}',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiaryDark),
        ),
        trailing: IconButton(
          onPressed: onMore,
          tooltip: 'Subject options',
          icon: Icon(
            Icons.more_vert_rounded,
            color: AppColors.textTertiaryDark,
          ),
        ),
      ),
    );
  }
}
