import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show
        LucideIcons,
        ShadButton,
        ShadContextMenuItem,
        ShadContextMenuRegion,
        ShadDialog,
        ShadIconButton,
        ShadInput,
        ShadSwitch,
        ShadTab,
        ShadTabs;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_l10n.dart';
import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/db/app_database.dart';
import '../domain/project_colors.dart';
import '../domain/task_models.dart';
import 'widgets/create_project_dialog.dart';
import 'widgets/project_color_picker.dart';

class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  final _searchController = TextEditingController();
  _ProjectsMode _mode = _ProjectsMode.projects;
  bool _archivedOnly = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final projects = ref.watch(projectsProvider);
    final labels = ref.watch(labelsProvider);
    final tasks = ref.watch(tasksByQueryProvider(const TaskQuery.all()));
    final taskCounts = _projectTaskCounts(tasks.value ?? const <TaskItem>[]);
    final projectMode = _mode == _ProjectsMode.projects;

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        l10n.navProjects,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      IntrinsicWidth(
                        child: ShadTabs<_ProjectsMode>(
                          key: const Key('projects-mode-segmented-button'),
                          value: _mode,
                          tabs: [
                            ShadTab(
                              value: _ProjectsMode.projects,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(LucideIcons.folder),
                                  const SizedBox(width: 8),
                                  Text(l10n.navProjects),
                                ],
                              ),
                            ),
                            ShadTab(
                              value: _ProjectsMode.labels,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(LucideIcons.tag),
                                  const SizedBox(width: 8),
                                  Text(l10n.labelsTitle),
                                ],
                              ),
                            ),
                          ],
                          onChanged: (mode) => setState(() => _mode = mode),
                          gap: 0,
                        ),
                      ),
                      Tooltip(
                        message: projectMode ? l10n.addProject : l10n.addLabel,
                        child: ShadIconButton(
                          key: Key(
                            projectMode
                                ? 'projects-add-button'
                                : 'labels-add-button',
                          ),
                          onPressed: projectMode
                              ? () => showCreateProjectDialog(context)
                              : () => showCreateLabelDialog(context),
                          icon: const Icon(LucideIcons.plus),
                          foregroundColor: colors.accent,
                          backgroundColor: colors.accentTint,
                          height: 42,
                          width: 42,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ShadInput(
                    key: const Key('projects-search-field'),
                    controller: _searchController,
                    placeholder: Text(
                      projectMode ? l10n.searchProjects : l10n.searchLabels,
                    ),
                    leading: const Icon(LucideIcons.search),
                  ),
                  if (projectMode) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.archivedProjectsOnly,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: colors.secondaryText,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ),
                        ShadSwitch(
                          key: const Key('projects-archived-switch'),
                          value: _archivedOnly,
                          onChanged: (value) =>
                              setState(() => _archivedOnly = value),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (projectMode)
            projects.when(
              data: (items) {
                final filteredProjects = _filteredProjects(items);
                final rows = _projectRows(filteredProjects);
                if (rows.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        l10n.noProjects,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  sliver: SliverList.separated(
                    itemCount: rows.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _ProjectCountHeader(
                          count: filteredProjects.length,
                        );
                      }
                      final row = rows[index - 1];
                      return _ProjectListTile(
                        project: row.project,
                        depth: row.depth,
                        count: taskCounts[row.project.id] ?? 0,
                        onTap: () => context.go('/project/${row.project.id}'),
                        onRename: () => showRenameProjectDialog(
                          context,
                          projectId: row.project.id,
                          projectName: row.project.name,
                        ),
                        onColor: () => _changeProjectColor(row.project),
                        onFavorite: () => _toggleProjectFavorite(row.project),
                        onDelete: () => _confirmDeleteProject(row.project),
                      );
                    },
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                );
              },
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stackTrace) => SliverFillRemaining(
                child: Center(child: Text(l10n.projectsUnavailable(error))),
              ),
            )
          else
            labels.when(
              data: (items) {
                final filteredLabels = _filteredLabels(items);
                if (filteredLabels.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        l10n.noLabels,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  sliver: SliverList.separated(
                    itemCount: filteredLabels.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _LabelCountHeader(count: filteredLabels.length);
                      }
                      final label = filteredLabels[index - 1];
                      return _LabelListTile(
                        label: label,
                        onDelete: () => _confirmDeleteLabel(label),
                      );
                    },
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                );
              },
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stackTrace) => SliverFillRemaining(
                child: Center(child: Text(l10n.failedToLoadLabels(error))),
              ),
            ),
        ],
      ),
    );
  }

  List<ProjectItem> _filteredProjects(List<ProjectItem> projects) {
    final search = _searchController.text.trim().toLowerCase();
    return projects.where((project) {
      if (project.id == inboxProjectId || project.isArchived != _archivedOnly) {
        return false;
      }
      return search.isEmpty || project.name.toLowerCase().contains(search);
    }).toList();
  }

  List<LabelItem> _filteredLabels(List<LabelItem> labels) {
    final search = _searchController.text.trim().toLowerCase();
    return labels
        .where(
          (label) =>
              search.isEmpty || label.name.toLowerCase().contains(search),
        )
        .toList();
  }

  Future<void> _confirmDeleteProject(ProjectItem project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ShadDialog(
        title: Text(context.l10n.deleteProject),
        actions: [
          ShadButton.ghost(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          ShadButton.destructive(
            key: const Key('confirm-delete-project-button'),
            onPressed: () => Navigator.of(context).pop(true),
            leading: const Icon(LucideIcons.trash2),
            child: Text(context.l10n.commonDelete),
          ),
        ],
        child: Text(context.l10n.deleteProjectConfirmation(project.name)),
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await ref.read(projectRepositoryProvider).deleteProject(project.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.couldNotDeleteProject(error))),
        );
      }
    }
  }

  Future<void> _changeProjectColor(ProjectItem project) async {
    final color = await showProjectColorPicker(
      context,
      selectedColor: effectiveProjectColor(project),
    );
    if (color == null || !mounted) {
      return;
    }
    await _updateProject(project.id, UpdateProjectPatch(color: color));
  }

  Future<void> _toggleProjectFavorite(ProjectItem project) {
    return _updateProject(
      project.id,
      UpdateProjectPatch(isFavorite: !project.isFavorite),
    );
  }

  Future<void> _updateProject(String id, UpdateProjectPatch patch) async {
    try {
      await ref.read(projectRepositoryProvider).updateProject(id, patch);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.couldNotUpdateProject(error))),
        );
      }
    }
  }

  Future<void> _confirmDeleteLabel(LabelItem label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ShadDialog(
        title: Text(context.l10n.deleteLabel),
        actions: [
          ShadButton.ghost(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          ShadButton.destructive(
            key: const Key('confirm-delete-label-button'),
            onPressed: () => Navigator.of(context).pop(true),
            leading: const Icon(LucideIcons.trash2),
            child: Text(context.l10n.commonDelete),
          ),
        ],
        child: Text(context.l10n.deleteLabelConfirmation(label.name)),
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await ref.read(labelRepositoryProvider).deleteLabel(label.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.couldNotDeleteLabel(error))),
        );
      }
    }
  }

  void _onSearchChanged() {
    setState(() {});
  }
}

enum _ProjectsMode { projects, labels }

class _ProjectCountHeader extends StatelessWidget {
  const _ProjectCountHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        context.l10n.projectsCount(count),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: colors.primaryText,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ProjectListTile extends StatelessWidget {
  const _ProjectListTile({
    required this.project,
    required this.depth,
    required this.count,
    required this.onTap,
    required this.onRename,
    required this.onColor,
    required this.onFavorite,
    required this.onDelete,
  });

  final ProjectItem project;
  final int depth;
  final int count;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onColor;
  final VoidCallback onFavorite;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      color: colors.primaryText,
      fontWeight: FontWeight.w500,
    );
    return ShadContextMenuRegion(
      key: ValueKey('projects-screen-project-${project.id}'),
      tapEnabled: false,
      longPressEnabled: true,
      items: [
        ShadContextMenuItem(
          leading: const Icon(LucideIcons.pencil, size: 16),
          onPressed: onRename,
          child: Text(context.l10n.renameProject),
        ),
        ShadContextMenuItem(
          leading: Icon(
            LucideIcons.trash2,
            size: 16,
            color: Theme.of(context).colorScheme.error,
          ),
          onPressed: onDelete,
          child: Text(context.l10n.deleteProject),
        ),
      ],
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.only(
              left: 10.0 + depth * 28.0,
              right: 12,
              top: 14,
              bottom: 14,
            ),
            child: Row(
              children: [
                ProjectColorSwatch(
                  key: ValueKey('project-color-${project.id}'),
                  color: effectiveProjectColor(project),
                  onPressed: onColor,
                  size: 20,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                ),
                if (count > 0)
                  Text(
                    '$count',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colors.mutedText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                const SizedBox(width: 6),
                Tooltip(
                  message: project.isFavorite
                      ? context.l10n.removeProjectFromFavorites
                      : context.l10n.addProjectToFavorites,
                  child: Semantics(
                    toggled: project.isFavorite,
                    child: ShadIconButton.ghost(
                      key: ValueKey('project-favorite-${project.id}'),
                      onPressed: onFavorite,
                      icon: Icon(
                        LucideIcons.star,
                        color: project.isFavorite
                            ? colors.accent
                            : colors.mutedText,
                      ),
                      width: 40,
                      height: 40,
                    ),
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

class _LabelCountHeader extends StatelessWidget {
  const _LabelCountHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        context.l10n.labelsCount(count),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: colors.primaryText,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _LabelListTile extends StatelessWidget {
  const _LabelListTile({required this.label, required this.onDelete});

  final LabelItem label;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ShadContextMenuRegion(
      key: ValueKey('projects-screen-label-${label.id}'),
      tapEnabled: false,
      longPressEnabled: true,
      items: [
        ShadContextMenuItem(
          leading: Icon(
            LucideIcons.trash2,
            size: 16,
            color: Theme.of(context).colorScheme.error,
          ),
          onPressed: onDelete,
          child: Text(context.l10n.deleteLabel),
        ),
      ],
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Icon(LucideIcons.tag, color: colors.mutedText),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    '@${label.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colors.primaryText,
                      fontWeight: FontWeight.w500,
                    ),
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

class _ProjectListRow {
  const _ProjectListRow({required this.project, required this.depth});

  final ProjectItem project;
  final int depth;
}

class _ProjectTreeNode {
  _ProjectTreeNode(this.project);

  final ProjectItem project;
  final List<_ProjectTreeNode> children = [];
}

List<_ProjectListRow> _projectRows(List<ProjectItem> projects) {
  final nodes = {
    for (final project in projects) project.id: _ProjectTreeNode(project),
  };
  final roots = <_ProjectTreeNode>[];

  for (final project in projects) {
    final node = nodes[project.id]!;
    final parentId = project.parentId;
    if (parentId != null && nodes.containsKey(parentId)) {
      nodes[parentId]!.children.add(node);
    } else {
      roots.add(node);
    }
  }

  final rows = <_ProjectListRow>[];
  void visit(_ProjectTreeNode node, int depth) {
    rows.add(_ProjectListRow(project: node.project, depth: depth));
    for (final child in node.children) {
      visit(child, depth + 1);
    }
  }

  for (final root in roots) {
    visit(root, 0);
  }
  return rows;
}

Map<String, int> _projectTaskCounts(List<TaskItem> tasks) {
  final counts = <String, int>{};
  for (final task in tasks) {
    if (task.projectId == inboxProjectId || task.isCompleted) {
      continue;
    }
    counts.update(task.projectId, (count) => count + 1, ifAbsent: () => 1);
  }
  return counts;
}
