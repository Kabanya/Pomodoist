import 'dart:async';
import 'package:pomodoist/ui/tasks/widgets/project_localizations.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show
        LucideIcons,
        ShadButton,
        ShadContextMenuItem,
        ShadDialog,
        ShadIconButton,
        ShadInput,
        ShadSwitch,
        ShadTab,
        ShadTabs;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pomodoist/routing/project_map_navigation.dart';

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/widgets/compact_shell_layout.dart';
import 'package:pomodoist/ui/core/widgets/app_context_menu_region.dart';
import 'package:pomodoist/ui/tasks/view_models/projects_view_model.dart';
import 'package:pomodoist/ui/tasks/view_models/browse_view_model.dart';
import 'package:pomodoist/ui/tasks/view_models/project_diagram_view_model.dart';
import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'package:pomodoist/ui/core/widgets/action_feedback.dart';
import 'project_diagram.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/collaboration/widgets/shared_project_badge.dart';
import 'package:pomodoist/domain/use_cases/tasks/project_list_data.dart';
import 'package:pomodoist/ui/tasks/widgets/create_project_dialog.dart';
import 'package:pomodoist/ui/tasks/widgets/project_context_menu.dart';
import 'package:pomodoist/ui/tasks/widgets/project_icon.dart';
import 'package:pomodoist/ui/tasks/widgets/project_tree_controls.dart';
import 'package:pomodoist/ui/tasks/widgets/label_icon.dart';
import 'package:pomodoist/ui/onboarding/widgets/learning_tour_overlay.dart';

class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({this.showLabels = false, super.key});

  final bool showLabels;

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  final _searchController = TextEditingController();
  _ProjectsMode _mode = _ProjectsMode.projects;
  final _identity = Object();
  final _visitedViews = <ProjectViewMode>{ProjectViewMode.list};
  ProjectDiagramViewModel get _diagramModel =>
      ref.read(projectDiagramViewModelProvider(null).notifier);
  ProjectsViewModel get _viewModel =>
      ref.read(projectsViewModelProvider(_identity).notifier);
  final _projectTree = ProjectTreeController();
  void _treeChanged() => setState(() {});

  @override
  void initState() {
    super.initState();
    _projectTree.addListener(_treeChanged);
    if (widget.showLabels) _mode = _ProjectsMode.labels;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _projectTree.dispose();
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final viewState = ref.watch(projectsViewModelProvider(_identity));
    final projects = viewState.projects;
    final labels = viewState.labels;
    final taskCounts = viewState.taskCounts;
    final archivedOnly = viewState.archivedOnly;
    final fullscreen = isProjectMapFullscreen(GoRouterState.of(context).uri);
    final projectMode = fullscreen || _mode == _ProjectsMode.projects;
    final savedMode = ref.watch(projectCatalogViewModeProvider);
    final catalogMode = fullscreen ? ProjectViewMode.map : savedMode;
    final diagram = ref.watch(projectDiagramViewModelProvider(null));
    final compactHeader = CompactShellHeading.menuActionOf(context) != null;
    if (projectMode) _visitedViews.add(catalogMode);

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            if (compactHeader && !fullscreen) _compactHeader(catalogMode),
            Visibility(
              visible: !fullscreen,
              maintainState: true,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * .55,
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      compactHeader ? 12 : 22,
                      20,
                      10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!compactHeader)
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                l10n.navProjects,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                              _modeTabs(),
                              _addButton(projectMode),
                            ],
                          ),
                        if (projectMode) ...[
                          if (!compactHeader) ...[
                            const SizedBox(height: 12),
                            _viewTabs(catalogMode),
                          ],
                          if (catalogMode != ProjectViewMode.list)
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 12,
                              children: [
                                TextButton.icon(
                                  onPressed: () => _diagramModel.showCompleted(
                                    !diagram.showCompleted,
                                  ),
                                  icon: Icon(
                                    diagram.showCompleted
                                        ? LucideIcons.circleCheck
                                        : LucideIcons.circle,
                                    size: 16,
                                  ),
                                  label: Text(l10n.projectShowCompleted),
                                ),
                                if (!diagram.loading &&
                                    !diagram.hasError &&
                                    diagram.tree.nodes[diagram.tree.rootKey] !=
                                        null)
                                  Text(
                                    diagram
                                        .tree
                                        .nodes[diagram.tree.rootKey]!
                                        .progress
                                        .label,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                              ],
                            ),
                        ],
                        if (!compactHeader ||
                            (projectMode &&
                                catalogMode != ProjectViewMode.list))
                          const SizedBox(height: 18),
                        ShadInput(
                          key: const Key('projects-search-field'),
                          controller: _searchController,
                          placeholder: Text(
                            projectMode
                                ? (catalogMode == ProjectViewMode.list
                                      ? l10n.searchProjects
                                      : l10n.projectCatalogSearch)
                                : l10n.searchLabels,
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
                                value: archivedOnly,
                                onChanged: (value) {
                                  _viewModel.setArchivedOnly(value);
                                  _diagramModel.setCatalogFilter(
                                    archivedOnly: value,
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: projectMode ? catalogMode.index : 0,
                children: [
                  CustomScrollView(
                    slivers: [
                      if (projectMode)
                        projects.when(
                          data: (items) {
                            final filteredProjects = items;
                            final rows = projectRows(
                              filteredProjects,
                              collapsedIds:
                                  _searchController.text.trim().isEmpty
                                  ? _projectTree.collapsedIds
                                  : const {},
                            );
                            if (rows.isEmpty) {
                              return SliverFillRemaining(
                                hasScrollBody: false,
                                child: Center(
                                  child: Text(
                                    l10n.noProjects,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ),
                              );
                            }
                            return ProjectTreeScope(
                              controller: _projectTree,
                              child: SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  12,
                                  20,
                                  24,
                                ),
                                sliver: SliverList.separated(
                                  itemCount: rows.length + 1,
                                  itemBuilder: (context, index) {
                                    if (index == 0) {
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          _ProjectCountHeader(
                                            count: filteredProjects.length,
                                          ),
                                          if (!archivedOnly &&
                                              _searchController.text
                                                  .trim()
                                                  .isEmpty)
                                            const ProjectTreeRootTarget(),
                                        ],
                                      );
                                    }
                                    final row = rows[index - 1];
                                    return ProjectTreeRow(
                                      key: ValueKey(
                                        'project-tree-${row.project.id}',
                                      ),
                                      row: row,
                                      dragEnabled:
                                          !archivedOnly &&
                                          _searchController.text.trim().isEmpty,
                                      child: _ProjectListTile(
                                        project: row.project,
                                        count: taskCounts[row.project.id] ?? 0,
                                        onTap: () => context.go(
                                          '/project/${row.project.id}',
                                        ),
                                        onColor: () => changeProjectColor(
                                          context,
                                          ref,
                                          row.project,
                                        ),
                                        onFavorite: () => toggleProjectFavorite(
                                          context,
                                          ref,
                                          row.project,
                                        ),
                                      ),
                                    );
                                  },
                                  separatorBuilder: (context, index) => Divider(
                                    height: 1,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outlineVariant,
                                  ),
                                ),
                              ),
                            );
                          },
                          loading: () => const SliverFillRemaining(
                            child: Center(child: CircularProgressIndicator()),
                          ),
                          error: (error, stackTrace) => SliverFillRemaining(
                            child: Center(
                              child: Text(l10n.projectsUnavailable(error)),
                            ),
                          ),
                        )
                      else
                        labels.when(
                          data: (items) {
                            final filteredLabels = items;
                            if (filteredLabels.isEmpty) {
                              return SliverFillRemaining(
                                hasScrollBody: false,
                                child: Center(
                                  child: Text(
                                    l10n.noLabels,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ),
                              );
                            }
                            return SliverPadding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                12,
                                20,
                                24,
                              ),
                              sliver: SliverList.separated(
                                itemCount: filteredLabels.length + 1,
                                itemBuilder: (context, index) {
                                  if (index == 0) {
                                    return _LabelCountHeader(
                                      count: filteredLabels.length,
                                    );
                                  }
                                  final label = filteredLabels[index - 1];
                                  return _LabelListTile(
                                    label: label,
                                    onDelete: () => _confirmDeleteLabel(label),
                                  );
                                },
                                separatorBuilder: (context, index) => Divider(
                                  height: 1,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outlineVariant,
                                ),
                              ),
                            );
                          },
                          loading: () => const SliverFillRemaining(
                            child: Center(child: CircularProgressIndicator()),
                          ),
                          error: (error, stackTrace) => SliverFillRemaining(
                            child: Center(
                              child: Text(l10n.failedToLoadLabels(error)),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (_visitedViews.contains(ProjectViewMode.map))
                    ProjectDiagram(
                      key: const ValueKey('catalog:map'),
                      isActive:
                          projectMode && catalogMode == ProjectViewMode.map,
                    )
                  else
                    const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeTabs({bool iconOnly = false}) => SizedBox(
    width: iconOnly ? 88 : null,
    child: IntrinsicWidth(
      child: ShadTabs<_ProjectsMode>(
        key: const Key('projects-mode-segmented-button'),
        value: _mode,
        gap: 0,
        onChanged: (mode) => setState(() => _mode = mode),
        tabs: [
          _tab(
            _ProjectsMode.projects,
            LucideIcons.folder,
            context.l10n.navProjects,
            iconOnly: iconOnly,
            selected: _mode == _ProjectsMode.projects,
          ),
          _tab(
            _ProjectsMode.labels,
            LucideIcons.tag,
            context.l10n.labelsTitle,
            iconOnly: iconOnly,
            selected: _mode == _ProjectsMode.labels,
          ),
        ],
      ),
    ),
  );

  Widget _viewTabs(ProjectViewMode mode, {bool iconOnly = false}) => SizedBox(
    width: iconOnly ? 88 : null,
    child: ShadTabs<ProjectViewMode>(
      key: const Key('projects-view-segmented-button'),
      value: mode,
      scrollable: !iconOnly,
      gap: 0,
      onChanged: (value) => unawaited(_setViewMode(value)),
      tabs: [
        _tab(
          ProjectViewMode.list,
          LucideIcons.list,
          context.l10n.projectViewList,
          iconOnly: iconOnly,
          selected: mode == ProjectViewMode.list,
        ),
        _tab(
          ProjectViewMode.map,
          LucideIcons.map,
          context.l10n.projectViewMap,
          iconOnly: iconOnly,
          selected: mode == ProjectViewMode.map,
        ),
      ],
    ),
  );

  ShadTab<T> _tab<T>(
    T value,
    IconData icon,
    String label, {
    required bool iconOnly,
    required bool selected,
  }) => ShadTab<T>(
    value: value,
    height: iconOnly
        ? 44
        : value is _ProjectsMode
        ? null
        : (MediaQuery.textScalerOf(context).scale(16) + 16).clamp(
            44.0,
            double.infinity,
          ),
    padding: iconOnly ? EdgeInsets.zero : null,
    child: iconOnly
        ? Semantics(
            label: label,
            selected: selected,
            child: Tooltip(
              message: label,
              excludeFromSemantics: true,
              child: Icon(icon, size: 20),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (value is _ProjectsMode) ...[
                Icon(icon),
                const SizedBox(width: 8),
              ],
              Text(label),
            ],
          ),
  );

  Widget _addButton(bool projectMode) => LearningTourAnchor(
    id: LearningTourAnchorId.projectsAdd,
    child: Tooltip(
      message: projectMode ? context.l10n.addProject : context.l10n.addLabel,
      child: ShadIconButton(
        key: Key(projectMode ? 'projects-add-button' : 'labels-add-button'),
        onPressed: projectMode
            ? () => showCreateProjectDialog(context)
            : () => showCreateLabelDialog(context),
        icon: const Icon(LucideIcons.plus, size: 20),
        foregroundColor: context.appColors.accent,
        backgroundColor: context.appColors.accentTint,
        height: 44,
        width: 44,
      ),
    ),
  );

  Widget _compactHeader(ProjectViewMode mode) {
    final l10n = context.l10n;
    final projectMode = _mode == _ProjectsMode.projects;
    final menu = SizedBox.square(
      dimension: 48,
      child: IconButton(
        key: const Key('shell-menu-button'),
        tooltip: l10n.menuTooltip,
        onPressed: CompactShellHeading.menuActionOf(context),
        icon: const Icon(LucideIcons.panelLeft, size: 20),
      ),
    );
    final title = Semantics(
      header: true,
      label: l10n.navProjects,
      excludeSemantics: true,
      child: Text(
        l10n.navProjects,
        key: const Key('shell-page-title'),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    return DecoratedBox(
      key: const Key('projects-compact-header'),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.appColors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 390 ||
              MediaQuery.textScalerOf(context).scale(20) > 22;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: stacked ? 48 : 144,
                      child: Row(
                        children: [
                          menu,
                          if (!stacked) ...[
                            const SizedBox(width: 8),
                            _modeTabs(iconOnly: true),
                          ],
                        ],
                      ),
                    ),
                    Expanded(child: title),
                    SizedBox(
                      width: stacked ? 48 : 144,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (!stacked && projectMode) ...[
                            _viewTabs(mode, iconOnly: true),
                            const SizedBox(width: 8),
                          ],
                          _addButton(projectMode),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                  ],
                ),
                if (stacked)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _modeTabs(iconOnly: true),
                        if (projectMode) _viewTabs(mode, iconOnly: true),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    projectMode
                        ? '${l10n.navProjects} · ${mode == ProjectViewMode.list ? l10n.projectViewList : l10n.projectViewMap}'
                        : l10n.labelsTitle,
                    key: const Key('projects-header-context'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _setViewMode(ProjectViewMode mode) async {
    try {
      await _diagramModel.setMode(mode);
    } catch (_) {
      if (mounted) {
        showActionFeedback(
          context,
          message: context.l10n.settingsSaveError,
          icon: LucideIcons.circleAlert,
          sound: ActionFeedbackSound.none,
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
      await _viewModel.deleteLabel(label.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.couldNotDeleteLabel(error))),
        );
      }
    }
  }

  void _onSearchChanged() {
    _viewModel.search(_searchController.text);
    _diagramModel.setCatalogFilter(search: _searchController.text);
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
    required this.count,
    required this.onTap,
    required this.onColor,
    required this.onFavorite,
  });

  final ProjectItem project;
  final int count;
  final VoidCallback onTap;
  final VoidCallback onColor;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      color: colors.primaryText,
      fontWeight: FontWeight.w500,
    );
    return ProjectContextMenu(
      key: ValueKey('projects-screen-project-${project.id}'),
      project: project,
      showMenuButton: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Tooltip(
                  message: context.l10n.projectColor,
                  child: ShadIconButton.ghost(
                    key: ValueKey('project-color-${project.id}'),
                    onPressed: onColor,
                    icon: ProjectIconView(project: project),
                    width: 36,
                    height: 36,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          project.displayName(context.l10n),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      SharedProjectBadge(project: project),
                    ],
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
                const SizedBox(width: 4),
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
                      width: 36,
                      height: 36,
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

class _LabelListTile extends ConsumerWidget {
  const _LabelListTile({required this.label, required this.onDelete});

  final LabelItem label;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final count = ref.watch(labelTaskCountsViewModelProvider)[label.id] ?? 0;
    return AppContextMenuRegion(
      key: ValueKey('projects-screen-label-${label.id}'),
      items: [
        ShadContextMenuItem(
          leading: Icon(labelIconData(label.icon), size: 16),
          onPressed: () => editLabelIcon(context, ref, label),
          child: Text(context.l10n.labelIcon),
        ),
        ShadContextMenuItem(
          leading: const Icon(LucideIcons.pencil, size: 16),
          onPressed: () => showEditLabelDialog(context, label),
          child: Text(context.l10n.editLabel),
        ),
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
          onTap: () => context.push('/label/${label.id}'),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                LabelIconView(label: label),
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
                const SizedBox(width: 8),
                Text('$count', style: Theme.of(context).textTheme.bodySmall),
                IconButton(
                  tooltip: context.l10n.labelIcon,
                  onPressed: () => editLabelIcon(context, ref, label),
                  icon: const Icon(LucideIcons.pencil, size: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
