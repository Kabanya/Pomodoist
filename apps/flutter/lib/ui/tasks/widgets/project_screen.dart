import 'package:pomodoist/ui/files/widgets/files_panel.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pomodoist/routing/project_map_navigation.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show
        ShadTabs,
        ShadTab,
        ShadPopover,
        ShadPopoverController,
        ShadAnchorAuto,
        ShadDecoration,
        LucideIcons;
import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/widgets/compact_shell_layout.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/action_feedback.dart';
import 'package:pomodoist/ui/tasks/view_models/project_view_model.dart';
import 'package:pomodoist/ui/tasks/view_models/project_diagram_view_model.dart';
import 'project_localizations.dart';
import 'project_context_menu.dart';
import 'project_diagram.dart';
import 'quick_add_bar.dart';
import 'task_list_view.dart';

class ProjectScreen extends StatelessWidget {
  const ProjectScreen({required this.projectId, super.key});
  final String projectId;
  @override
  Widget build(BuildContext context) =>
      _ProjectContent(key: ValueKey(projectId), projectId: projectId);
}

class _ProjectContent extends ConsumerStatefulWidget {
  const _ProjectContent({required this.projectId, super.key});
  final String projectId;
  @override
  ConsumerState<_ProjectContent> createState() => _ProjectContentState();
}

class _ProjectContentState extends ConsumerState<_ProjectContent> {
  final _visited = <ProjectViewMode>{};
  bool _files = false;
  bool _visitedFiles = false;
  final _views = ShadPopoverController();

  @override
  void dispose() {
    _views.dispose();
    super.dispose();
  }

  void _selectView(String value) {
    setState(() {
      _files = value == 'files';
      _visitedFiles = _visitedFiles || _files;
    });
    if (!_files) {
      unawaited(_setMode(ProjectViewMode.values.byName(value)));
    }
  }

  Future<void> _setMode(ProjectViewMode mode) async {
    try {
      await ref
          .read(projectDiagramViewModelProvider(widget.projectId).notifier)
          .setMode(mode);
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

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectViewModelProvider(widget.projectId));
    final fullscreen = isProjectMapFullscreen(GoRouterState.of(context).uri);
    final files = _files && !fullscreen;
    final savedMode = ref.watch(projectViewModeProvider);
    final mode = fullscreen ? ProjectViewMode.map : savedMode;
    _visited.add(mode);
    final l10n = context.l10n;
    final title = project?.displayName(l10n) ?? l10n.projectFallbackTitle;
    final showTitle = !CompactShellHeading.isShown(context);
    final showProjectMenu = project != null && project.id != inboxProjectId;
    final diagram = files || mode == ProjectViewMode.list
        ? null
        : ref.watch(projectDiagramViewModelProvider(widget.projectId));
    final onMenu = CompactShellHeading.menuActionOf(context);
    final value = files ? 'files' : mode.name;
    final showComposer =
        !usesCompactMobileLayout(context) &&
        !files &&
        project?.canEdit == true &&
        project?.isArchived == false;
    final viewTabs = ShadTabs<String>(
      value: value,
      onChanged: _selectView,
      // ShadTabs owns scrolling and removes Expanded from its tabs.
      scrollable: true,
      gap: 0,
      tabs: [
        ShadTab(
          height: onMenu == null ? null : 44,
          onPressed: onMenu == null ? null : _views.hide,
          value: 'list',
          child: Text(l10n.projectViewList),
        ),
        ShadTab(
          height: onMenu == null ? null : 44,
          onPressed: onMenu == null ? null : _views.hide,
          value: 'map',
          child: Text(l10n.projectViewMap),
        ),
        ShadTab(
          height: onMenu == null ? null : 44,
          onPressed: onMenu == null ? null : _views.hide,
          value: 'files',
          child: Text(l10n.filesTitle),
        ),
      ],
    );
    return SafeArea(
      bottom: fullscreen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onMenu != null && !fullscreen)
            _compactHeader(
              context,
              title,
              onMenu,
              showProjectMenu ? project : null,
              value,
              viewTabs,
            ),
          Visibility(
            visible: !fullscreen,
            maintainState: true,
            child: Padding(
              padding: onMenu != null && diagram == null && !showComposer
                  ? EdgeInsets.zero
                  : const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (onMenu == null && showProjectMenu)
                    ProjectContextMenu(
                      project: project,
                      showMenuButton: true,
                      child: showTitle
                          ? Text(
                              title,
                              style: Theme.of(context).textTheme.headlineMedium,
                            )
                          : const SizedBox.shrink(),
                    )
                  else if (showTitle)
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  if (onMenu == null && (showTitle || showProjectMenu))
                    const SizedBox(height: 12),
                  if (onMenu == null) viewTabs,
                  if (diagram != null)
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      children: [
                        TextButton.icon(
                          onPressed: () => ref
                              .read(
                                projectDiagramViewModelProvider(
                                  widget.projectId,
                                ).notifier,
                              )
                              .showCompleted(!diagram.showCompleted),
                          icon: Icon(
                            diagram.showCompleted
                                ? LucideIcons.circleCheck
                                : LucideIcons.circle,
                            size: 16,
                          ),
                          label: Text(l10n.projectShowCompleted),
                        ),
                        if (diagram.tree.nodes[diagram.tree.rootKey]
                            case final root?)
                          if (!diagram.loading && !diagram.hasError)
                            Text(
                              '${root.progress.completed}/${root.progress.total}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                      ],
                    ),
                  if (showComposer) ...[
                    if (onMenu == null || diagram != null)
                      const SizedBox(height: 12),
                    // This composer stays mounted across view changes.
                    QuickAddBar(projectId: widget.projectId),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: files ? ProjectViewMode.values.length : mode.index,
              children: [
                for (final view in ProjectViewMode.values)
                  if (!_visited.contains(view))
                    const SizedBox.shrink()
                  else if (view == ProjectViewMode.list)
                    TaskListView(
                      key: PageStorageKey('project-list:${widget.projectId}'),
                      title: title,
                      query: TaskQuery(
                        kind: TaskQueryKind.project,
                        projectId: widget.projectId,
                      ),
                      showHeader: false,
                      isActive: !files && mode == ProjectViewMode.list,
                      showQuickAdd: false,
                      quickAddProjectId: widget.projectId,
                    )
                  else
                    ProjectDiagram(
                      key: ValueKey('${widget.projectId}:${view.name}'),
                      projectId: widget.projectId,
                      isActive: !files && mode == view,
                    ),
                if (_visitedFiles)
                  FilesPanel(projectId: widget.projectId)
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactHeader(
    BuildContext context,
    String title,
    VoidCallback onMenu,
    ProjectItem? project,
    String value,
    Widget tabs,
  ) {
    final colors = context.appColors;
    final l = context.l10n;
    final (icon, label) = switch (value) {
      'files' => (LucideIcons.files, l.filesTitle),
      'map' => (LucideIcons.map, l.projectViewMap),
      _ => (LucideIcons.list, l.projectViewList),
    };
    final actionsWidth = project == null ? 56.0 : 100.0;
    final endOffset = (project == null ? 0.0 : 44.0) - 8;
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: actionsWidth,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: IconButton(
                key: const Key('shell-menu-button'),
                tooltip: l.menuTooltip,
                icon: Icon(LucideIcons.panelLeft, color: colors.secondaryText),
                onPressed: onMenu,
              ),
            ),
          ),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                key: const Key('shell-page-title'),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          ShadPopover(
            controller: _views,
            anchor: ShadAnchorAuto(
              targetAnchor: AlignmentDirectional.bottomEnd,
              followerAnchor: AlignmentDirectional.bottomStart,
              offset: Offset(
                Directionality.of(context) == TextDirection.rtl
                    ? -endOffset
                    : endOffset,
                4,
              ),
            ),
            padding: EdgeInsets.zero,
            decoration: ShadDecoration.none,
            shadows: const [],
            popover: (context) => ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width - 24,
              ),
              child: Stack(
                children: [
                  PositionedDirectional(
                    end: endOffset + 23,
                    top: 2,
                    child: Transform.rotate(
                      angle: math.pi / 4,
                      child: ColoredBox(
                        color: colors.surfaceTint,
                        child: const SizedBox.square(dimension: 10),
                      ),
                    ),
                  ),
                  Padding(padding: const EdgeInsets.only(top: 7), child: tabs),
                ],
              ),
            ),
            child: SizedBox(
              width: 56,
              height: 44,
              child: IconButton(
                key: const Key('project-view-picker'),
                tooltip: label,
                color: colors.primaryText,
                padding: EdgeInsets.zero,
                onPressed: _views.toggle,
                icon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 20),
                    const SizedBox(width: 3),
                    const Icon(LucideIcons.chevronDown, size: 14),
                  ],
                ),
              ),
            ),
          ),
          if (project != null)
            SizedBox(
              width: 44,
              child: ProjectContextMenu(
                project: project,
                showMenuButton: true,
                child: const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }
}
