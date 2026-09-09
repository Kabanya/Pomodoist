import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show
        LucideIcons,
        ShadButton,
        ShadContextMenuController,
        ShadContextMenuItem,
        ShadContextMenuRegion,
        ShadDialog;

import '../../../../app/app_l10n.dart';
import '../../../../app/providers.dart';
import '../../domain/project_colors.dart';
import '../../domain/task_models.dart';
import 'create_project_dialog.dart';
import 'project_color_picker.dart';
import 'project_icon.dart';

class ProjectContextMenu extends ConsumerStatefulWidget {
  const ProjectContextMenu({
    required this.project,
    required this.child,
    super.key,
  });

  final ProjectItem project;
  final Widget child;

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
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.contextMenu): _controller.show,
        const SingleActivator(LogicalKeyboardKey.f10, shift: true):
            _controller.show,
      },
      child: ShadContextMenuRegion(
        controller: _controller,
        tapEnabled: false,
        longPressEnabled: true,
        items: [
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
        child: widget.child,
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
      child: Text(context.l10n.deleteProjectConfirmation(project.name)),
    ),
  );
  if (confirmed != true || !context.mounted) {
    return;
  }
  try {
    await ref.read(projectRepositoryProvider).deleteProject(project.id);
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
    await ref.read(projectRepositoryProvider).updateProject(projectId, patch);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.couldNotUpdateProject(error))),
      );
    }
  }
}
