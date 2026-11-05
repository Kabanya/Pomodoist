import 'package:pomodoist/ui/files/widgets/files_panel.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pomodoist/routing/project_map_navigation.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadTabs, ShadTab, LucideIcons;
import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/widgets/compact_shell_layout.dart';
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
    return SafeArea(
      bottom: fullscreen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Visibility(
            visible: !fullscreen,
            maintainState: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showProjectMenu)
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
                  if (showTitle || showProjectMenu) const SizedBox(height: 12),
                  ShadTabs<String>(
                    value: files ? 'files' : mode.name,
                    onChanged: (value) {
                      setState(() {
                        _files = value == 'files';
                        _visitedFiles = _visitedFiles || _files;
                      });
                      if (!_files) {
                        unawaited(
                          _setMode(ProjectViewMode.values.byName(value)),
                        );
                      }
                    },
                    // ShadTabs owns scrolling and removes Expanded from its tabs.
                    scrollable: true,
                    gap: 0,
                    tabs: [
                      ShadTab(value: 'list', child: Text(l10n.projectViewList)),
                      ShadTab(value: 'map', child: Text(l10n.projectViewMap)),
                      ShadTab(value: 'files', child: Text(l10n.filesTitle)),
                    ],
                  ),
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
                  if (!files &&
                      project?.canEdit == true &&
                      project?.isArchived == false) ...[
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
}
