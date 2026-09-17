import '../project_localizations.dart';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadDialog;

import '../../../../app/app_l10n.dart';
import '../../../../app/providers.dart';
import '../../../../app/theme/app_theme.dart';
import '../../domain/project_hierarchy.dart';
import '../../domain/task_models.dart';
import '../project_list_data.dart';

class ProjectTreeController extends ChangeNotifier {
  final collapsedIds = <String>{};
  String? draggedId;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void toggle(String id) {
    if (!collapsedIds.remove(id)) collapsedIds.add(id);
    notifyListeners();
  }

  void drag(String? id) {
    if (_disposed) return;
    draggedId = id;
    notifyListeners();
  }

  void reveal(String? parentId, List<ProjectItem> projects) {
    if (_disposed) return;
    final parents = projectParents(projects);
    final seen = <String>{};
    while (parentId != null && seen.add(parentId)) {
      collapsedIds.remove(parentId);
      parentId = parents[parentId];
    }
    notifyListeners();
  }
}

class ProjectTreeScope extends InheritedWidget {
  const ProjectTreeScope({
    required this.controller,
    required super.child,
    super.key,
  });
  final ProjectTreeController controller;
  static ProjectTreeController? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ProjectTreeScope>()
      ?.controller;
  @override
  bool updateShouldNotify(ProjectTreeScope oldWidget) => true;
}

Future<void> moveProjectInTree(
  BuildContext context,
  WidgetRef ref,
  String id,
  ProjectMoveTarget target,
) async {
  final tree = ProjectTreeScope.of(context);
  final projects = ref.read(projectsProvider).value ?? const <ProjectItem>[];
  try {
    await ref
        .read(projectRepositoryProvider)
        .moveProject(
          id,
          parentId: target.parentId,
          beforeProjectId: target.beforeProjectId,
        );
    tree?.reveal(target.parentId, projects);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.couldNotUpdateProject(error))),
      );
    }
  }
}

Future<void> showMoveProjectDialog(
  BuildContext context,
  WidgetRef ref,
  ProjectItem project,
) async {
  final target = await showDialog<ProjectMoveTarget>(
    context: context,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final projects = ref.watch(projectsProvider);
        return ShadDialog(
          title: Text(context.l10n.moveProject),
          child: Material(
            type: MaterialType.transparency,
            child: SizedBox(
              width: 420,
              height: 360,
              child: projects.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) =>
                    Text(context.l10n.projectsUnavailable(error)),
                data: (items) {
                  final rows = projectRows(
                    items
                        .where(
                          (p) =>
                              p.id != inboxProjectId &&
                              !p.isArchived &&
                              !p.isDeleted,
                        )
                        .toList(),
                  );
                  return ListView(
                    children: [
                      ListTile(
                        leading: const Icon(LucideIcons.folders),
                        title: Text(context.l10n.projectTopLevel),
                        onTap: () => Navigator.pop(
                          context,
                          const ProjectMoveTarget(null, null),
                        ),
                      ),
                      for (final row in rows)
                        if (canParentProject(
                          items,
                          projectId: project.id,
                          parentId: row.project.id,
                        ))
                          ListTile(
                            contentPadding: EdgeInsetsDirectional.only(
                              start: 16 + math.min(row.depth, 4) * 12.0,
                              end: 16,
                            ),
                            title: Text(row.project.displayName(context.l10n)),
                            onTap: () => Navigator.pop(
                              context,
                              ProjectMoveTarget(row.project.id, null),
                            ),
                          ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    ),
  );
  if (target != null && context.mounted) {
    await moveProjectInTree(context, ref, project.id, target);
  }
}

/// Typed payload keeps project drops separate from task drags.
class ProjectDragData {
  const ProjectDragData(this.id);
  final String id;
}

class ProjectTreeRow extends ConsumerStatefulWidget {
  const ProjectTreeRow({
    required this.row,
    required this.child,
    this.dragEnabled = true,
    super.key,
  });
  final ProjectListRow row;
  final Widget child;
  final bool dragEnabled;
  @override
  ConsumerState<ProjectTreeRow> createState() => _ProjectTreeRowState();
}

class _ProjectTreeRowState extends ConsumerState<ProjectTreeRow>
    with AutomaticKeepAliveClientMixin {
  ProjectDropPosition? _hover;
  bool _dragging = false;
  EdgeDraggingAutoScroller? _autoScroller;
  ProjectTreeController? _tree;
  @override
  bool get wantKeepAlive => _dragging;

  @override
  void dispose() {
    _autoScroller?.stopAutoScroll();
    super.dispose();
  }

  ProjectDropPosition _position(Offset global) {
    final box = context.findRenderObject()! as RenderBox;
    final y = box.globalToLocal(global).dy / box.size.height;
    return y < .25
        ? ProjectDropPosition.before
        : y > .75
        ? ProjectDropPosition.after
        : ProjectDropPosition.inside;
  }

  ProjectMoveTarget? _target(DragTargetDetails<ProjectDragData> details) =>
      widget.dragEnabled
      ? projectDropTarget(
          ref.read(projectsProvider).value ?? [],
          details.data.id,
          widget.row.project.id,
          _position(details.offset),
        )
      : null;

  void _endDrag() {
    _autoScroller?.stopAutoScroll();
    _tree?.drag(null);
    if (mounted) {
      setState(() => _dragging = false);
      updateKeepAlive();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final tree = ProjectTreeScope.of(context)!;
    _tree = tree;
    final colors = context.appColors;
    final row = widget.row;
    final enabled = widget.dragEnabled && !row.project.isArchived;
    Widget content = Row(
      children: [
        SizedBox(width: math.min(row.depth, 4) * 12.0),
        Expanded(child: widget.child),
        if (row.hasChildren)
          Semantics(
            expanded: !tree.collapsedIds.contains(row.project.id),
            label: row.project.displayName(context.l10n),
            child: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: tree.collapsedIds.contains(row.project.id)
                  ? context.l10n.expandProjects
                  : context.l10n.collapseProjects,
              onPressed: () => tree.toggle(row.project.id),
              icon: Icon(
                tree.collapsedIds.contains(row.project.id)
                    ? LucideIcons.chevronRight
                    : LucideIcons.chevronDown,
                size: 16,
              ),
            ),
          ),
      ],
    );
    if (enabled) {
      content = _MouseProjectDraggable(
        data: ProjectDragData(row.project.id),
        allowedButtonsFilter: (buttons) => buttons == kPrimaryMouseButton,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        onDragStarted: () {
          setState(() => _dragging = true);
          updateKeepAlive();
          tree.drag(row.project.id);
        },
        onDragEnd: (_) => _endDrag(),
        onDragUpdate: (details) {
          final scrollable = Scrollable.maybeOf(context);
          if (scrollable == null) return;
          _autoScroller ??= EdgeDraggingAutoScroller(
            scrollable,
            velocityScalar: 12,
          );
          _autoScroller!.startAutoScrollIfNecessary(
            Rect.fromCenter(
              center: details.globalPosition,
              width: 48,
              height: 80,
            ),
          );
        },
        feedback: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                row.project.displayName(context.l10n),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        child: content,
      );
    }
    return DragTarget<ProjectDragData>(
      onWillAcceptWithDetails: (details) => _target(details) != null,
      onMove: (details) => setState(
        () => _hover = _target(details) == null
            ? null
            : _position(details.offset),
      ),
      onLeave: (_) => setState(() => _hover = null),
      onAcceptWithDetails: (details) {
        final target = _target(details);
        setState(() => _hover = null);
        if (target != null) {
          moveProjectInTree(context, ref, details.data.id, target);
        }
      },
      builder: (context, candidates, rejected) => DecoratedBox(
        decoration: BoxDecoration(
          color: _hover == ProjectDropPosition.inside
              ? colors.accentTint
              : null,
          border: Border(
            top: BorderSide(
              color: _hover == ProjectDropPosition.before
                  ? colors.accent
                  : Colors.transparent,
              width: 2,
            ),
            bottom: BorderSide(
              color: _hover == ProjectDropPosition.after
                  ? colors.accent
                  : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: content,
      ),
    );
  }
}

class ProjectTreeRootTarget extends ConsumerWidget {
  const ProjectTreeRootTarget({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ProjectTreeScope.of(context)?.draggedId == null) {
      return const SizedBox.shrink();
    }
    return DragTarget<ProjectDragData>(
      onWillAcceptWithDetails: (details) => details.data.id != inboxProjectId,
      onAcceptWithDetails: (details) => moveProjectInTree(
        context,
        ref,
        details.data.id,
        const ProjectMoveTarget(null, null),
      ),
      builder: (context, candidates, _) => Container(
        height: 48,
        alignment: Alignment.center,
        color: candidates.isEmpty
            ? context.appColors.surfaceTint
            : context.appColors.accentTint,
        child: Text(context.l10n.projectTopLevel),
      ),
    );
  }
}

class _MouseProjectDraggable extends Draggable<ProjectDragData> {
  const _MouseProjectDraggable({
    required super.data,
    required super.feedback,
    required super.child,
    super.allowedButtonsFilter,
    super.dragAnchorStrategy,
    super.onDragStarted,
    super.onDragEnd,
    super.onDragUpdate,
  });

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) => ImmediateMultiDragGestureRecognizer(
    supportedDevices: {PointerDeviceKind.mouse},
    allowedButtonsFilter: allowedButtonsFilter,
  )..onStart = onStart;
}
