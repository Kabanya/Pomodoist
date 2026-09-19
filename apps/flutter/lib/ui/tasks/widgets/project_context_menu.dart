import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show
        LucideIcons,
        ShadButton,
        ShadContextMenuController,
        ShadContextMenuItem,
        ShadDialog,
        ShadIconButton;

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/widgets/app_context_menu_region.dart';
import 'package:pomodoist/ui/tasks/view_models/projects_view_model.dart';
import 'package:pomodoist/domain/models/tasks/project_colors.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/widgets/project_localizations.dart';
import 'package:pomodoist/ui/tasks/widgets/create_project_dialog.dart';
import 'package:pomodoist/ui/collaboration/widgets/share_project_dialog.dart';
import 'package:pomodoist/ui/tasks/widgets/project_color_picker.dart';
import 'package:pomodoist/ui/tasks/widgets/project_icon.dart';
import 'package:pomodoist/ui/tasks/widgets/project_tree_controls.dart';
import 'package:pomodoist/domain/models/tasks/project_hierarchy.dart';

class ProjectContextMenu extends ConsumerStatefulWidget {
  const ProjectContextMenu({
    required this.project,
    required this.child,
    this.showMenuButton = false,
    super.key,
  });

  final ProjectItem project;
  final Widget child;
  final bool showMenuButton;

  @override
  ConsumerState<ProjectContextMenu> createState() => _ProjectContextMenuState();
}

class _ProjectContextMenuState extends ConsumerState<ProjectContextMenu> {
  final _controller = ShadContextMenuController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    final l10n = context.l10n;
    final viewState = ref.watch(projectContextViewModelProvider(project.id));
    final parents = viewState.parents;
    final siblings = viewState.siblings;
    final index = viewState.index;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.contextMenu): _controller.show,
        const SingleActivator(LogicalKeyboardKey.f10, shift: true):
            _controller.show,
      },
      child: AppContextMenuRegion(
        controller: _controller,
        items: [
          if (!project.isArchived && project.id != inboxProjectId) ...[
            ShadContextMenuItem(
              leading: const Icon(LucideIcons.folderPlus, size: 16),
              onPressed: () =>
                  showCreateProjectDialog(context, parentId: project.id),
              child: Text(l10n.addSubproject),
            ),
            ShadContextMenuItem(
              leading: const Icon(LucideIcons.folderInput, size: 16),
              onPressed: () => showMoveProjectDialog(context, ref, project),
              child: Text(l10n.moveProject),
            ),
            if (index > 0)
              ShadContextMenuItem(
                leading: const Icon(LucideIcons.arrowUp, size: 16),
                onPressed: () => moveProjectInTree(
                  context,
                  ref,
                  project.id,
                  ProjectMoveTarget(
                    parents[project.id],
                    siblings[index - 1].id,
                  ),
                ),
                child: Text(l10n.projectMoveUp),
              ),
            if (index >= 0 && index + 1 < siblings.length)
              ShadContextMenuItem(
                leading: const Icon(LucideIcons.arrowDown, size: 16),
                onPressed: () => moveProjectInTree(
                  context,
                  ref,
                  project.id,
                  ProjectMoveTarget(
                    parents[project.id],
                    index + 2 < siblings.length ? siblings[index + 2].id : null,
                  ),
                ),
                child: Text(l10n.projectMoveDown),
              ),
          ],
          if (!project.isArchived && project.id != inboxProjectId)
            ShadContextMenuItem(
              leading: const Icon(LucideIcons.users, size: 16),
              onPressed: () => showShareProjectDialog(context, project),
              child: Text(l10n.collaborationShareProject),
            ),
          ShadContextMenuItem(
            leading: const Icon(LucideIcons.pencil, size: 16),
            onPressed: () => showRenameProjectDialog(
              context,
              projectId: project.id,
              projectName: project.name,
            ),
            child: Text(l10n.renameProject),
          ),
          ShadContextMenuItem(
            leading: const Icon(LucideIcons.shapes, size: 16),
            onPressed: () => _changeProjectIcon(context, ref, project),
            child: Text(l10n.projectIcon),
          ),
          ShadContextMenuItem(
            leading: const Icon(LucideIcons.palette, size: 16),
            onPressed: () => changeProjectColor(context, ref, project),
            child: Text(l10n.projectColor),
          ),
          ShadContextMenuItem(
            leading: const Icon(LucideIcons.star, size: 16),
            onPressed: () => toggleProjectFavorite(context, ref, project),
            child: Text(
              project.isFavorite
                  ? l10n.removeProjectFromFavorites
                  : l10n.addProjectToFavorites,
            ),
          ),
          ShadContextMenuItem(
            leading: Icon(
              LucideIcons.trash2,
              size: 16,
              color: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => _confirmDeleteProject(context, ref, project),
            child: Text(l10n.deleteProject),
          ),
        ],
        child: widget.showMenuButton
            ? Row(
                children: [
                  Expanded(child: widget.child),
                  Tooltip(
                    message: '${l10n.taskMore}: ${project.displayName(l10n)}',
                    child: ShadIconButton.ghost(
                      onPressed: _controller.show,
                      onSecondaryTapUp: (_) => _controller.show(),
                      icon: const Icon(LucideIcons.ellipsis, size: 18),
                      width: 36,
                      height: 36,
                    ),
                  ),
                ],
              )
            : widget.child,
      ),
    );
  }
}

Future<void> _changeProjectIcon(
  BuildContext context,
  WidgetRef ref,
  ProjectItem project,
) async {
  final icon = await showProjectIconPicker(context, project: project);
  if (icon == null || !context.mounted) return;
  await _updateProject(
    context,
    ref,
    project.id,
    UpdateProjectPatch(icon: icon),
  );
}

Future<void> _confirmDeleteProject(
  BuildContext context,
  WidgetRef ref,
  ProjectItem project,
) async {
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
      child: Text(
        ref.read(projectContextViewModelProvider(project.id)).hasChildren
            ? context.l10n.deleteProjectWithChildrenConfirmation(
                project.displayName(context.l10n),
              )
            : context.l10n.deleteProjectConfirmation(
                project.displayName(context.l10n),
              ),
      ),
    ),
  );
  if (confirmed != true || !context.mounted) {
    return;
  }
  try {
    await ref
        .read(projectContextViewModelProvider(project.id).notifier)
        .delete();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.couldNotDeleteProject(error))),
      );
    }
  }
}

Future<void> changeProjectColor(
  BuildContext context,
  WidgetRef ref,
  ProjectItem project,
) async {
  final color = await showProjectColorPicker(
    context,
    selectedColor: effectiveProjectColor(project),
  );
  if (color == null || !context.mounted) {
    return;
  }
  await _updateProject(
    context,
    ref,
    project.id,
    UpdateProjectPatch(color: color),
  );
}

Future<void> toggleProjectFavorite(
  BuildContext context,
  WidgetRef ref,
  ProjectItem project,
) {
  return _updateProject(
    context,
    ref,
    project.id,
    UpdateProjectPatch(isFavorite: !project.isFavorite),
  );
}

Future<void> _updateProject(
  BuildContext context,
  WidgetRef ref,
  String projectId,
  UpdateProjectPatch patch,
) async {
  try {
    await ref
        .read(projectContextViewModelProvider(projectId).notifier)
        .update(patch);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.couldNotUpdateProject(error))),
      );
    }
  }
}
