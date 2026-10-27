import 'package:pomodoist/ui/core/widgets/shortcut_hints.dart';
import 'package:pomodoist/ui/core/widgets/app_action_menu.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show LucideIcons, ShadDialog, ShadInput, ShadButton, ShadContextMenuItem;
import 'package:pomodoist/domain/models/tasks/project_hierarchy.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/routing/task_detail_navigation.dart';
import 'package:pomodoist/routing/project_map_navigation.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/action_feedback.dart';
import 'package:pomodoist/ui/core/widgets/adaptive_shell.dart'
    show showQuickAddDialog;
import 'package:pomodoist/ui/tasks/view_models/project_diagram_view_model.dart';
import 'package:pomodoist/ui/tasks/view_models/project_tree_data.dart';
import 'package:pomodoist/ui/tasks/view_models/project_tree_layout.dart';
import 'package:pomodoist/ui/tasks/view_models/task_detail_view_model.dart';
import 'project_context_menu.dart';
import 'project_icon.dart';
import 'project_localizations.dart';
import 'project_tree_controls.dart';
import 'task_branch_widgets.dart';
import 'task_list_item.dart';
import 'task_motion.dart';
import 'task_selection_region.dart';
import 'task_view_state.dart';

/// Geometry follows the same title style, line limit and fixed controls as cards.
Size projectDiagramNodeSize(
  String title,
  TextStyle style,
  TextScaler scaler,
  TextDirection direction,
) {
  final width = math.max(304.0, 240 + scaler.scale(64));
  final painter = TextPainter(
    text: TextSpan(text: title, style: style),
    textScaler: scaler,
    textDirection: direction,
    maxLines: 3,
    ellipsis: '…',
  )..layout(maxWidth: width - 24);
  final height =
      math.max(28.0, painter.height) +
      16 +
      math.max(24.0, scaler.scale(18)) +
      96;
  painter.dispose();
  return Size(width, height);
}

class ProjectDiagram extends ConsumerStatefulWidget {
  const ProjectDiagram({this.projectId, this.isActive = true, super.key});
  final String? projectId;
  final bool isActive;
  @override
  ConsumerState<ProjectDiagram> createState() => _ProjectDiagramState();
}

class _ProjectDiagramState extends ConsumerState<ProjectDiagram> {
  final _horizontal = ScrollController(), _vertical = ScrollController();
  final _viewport = GlobalKey();
  final _projectTree = ProjectTreeController();
  Timer? _autoScroll;
  Offset? _dragPoint;
  ProjectDiagramViewModel get _model =>
      ref.read(projectDiagramViewModelProvider(widget.projectId).notifier);
  @override
  void initState() {
    super.initState();
    _projectTree.addListener(_projectRevealed);
  }

  void _projectRevealed() {
    final id = _projectTree.lastRevealedParentId;
    if (id != null) unawaited(_action(() => _model.reveal('p:$id')));
  }

  @override
  void dispose() {
    _autoScroll?.cancel();
    _horizontal.dispose();
    _vertical.dispose();
    _projectTree.dispose();
    super.dispose();
  }

  void _stopDrag() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _dragPoint = null;
  }

  void _drag(Offset position) {
    _dragPoint = position;
    _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      final box = _viewport.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize || _dragPoint == null) return;
      final p = box.globalToLocal(_dragPoint!);
      void scroll(
        ScrollController controller,
        double coordinate,
        double length,
        bool reverse,
      ) {
        if (!controller.hasClients) return;
        final speed = coordinate < 44
            ? -10.0
            : coordinate > length - 44
            ? 10.0
            : 0.0;
        final next = (controller.offset + (reverse ? -speed : speed)).clamp(
          0.0,
          controller.position.maxScrollExtent,
        );
        if (next != controller.offset) controller.jumpTo(next);
      }

      scroll(
        _horizontal,
        p.dx,
        box.size.width,
        Directionality.of(context) == TextDirection.rtl,
      );
      scroll(_vertical, p.dy, box.size.height, false);
    });
  }

  Future<void> _action(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) {
        showActionFeedback(
          context,
          message: context.l10n.taskActionFailedCount(1),
          icon: LucideIcons.circleAlert,
          sound: ActionFeedbackSound.none,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri;
    final fullscreen = isProjectMapFullscreen(location);
    final taskDetailsOpen = selectedTaskDetailsId(location) != null;
    void dismiss() {
      final viewportContext = _viewport.currentContext;
      final selection = viewportContext == null
          ? null
          : TaskSelectionScope.maybeOf(viewportContext);
      if (selection?.active == true) {
        selection!.close();
      } else {
        setProjectMapFullscreen(context, false);
      }
    }

    return BackButtonListener(
      onBackButtonPressed: () async {
        if (!widget.isActive || !fullscreen || taskDetailsOpen) return false;
        dismiss();
        return true;
      },
      child: ShortcutHintsScope(
        enabled: widget.isActive && fullscreen && !taskDetailsOpen,
        hints: [ShortcutHint(context.l10n.commonClose, 'Esc')],
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: (node, event) {
            if (widget.isActive &&
                fullscreen &&
                !taskDetailsOpen &&
                event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              dismiss();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildMap(context),
              PositionedDirectional(
                top: 8,
                end: 24,
                child: IconButton(
                  key: const Key('project-map-fullscreen'),
                  tooltip: fullscreen
                      ? context.l10n.projectMapCollapse
                      : context.l10n.projectMapExpand,
                  style: IconButton.styleFrom(
                    backgroundColor: context.appColors.surface,
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: widget.isActive
                      ? () => setProjectMapFullscreen(context, !fullscreen)
                      : null,
                  icon: Icon(
                    fullscreen ? LucideIcons.minimize : LucideIcons.maximize,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMap(BuildContext context) {
    final state = ref.watch(projectDiagramViewModelProvider(widget.projectId));
    final tree = state.tree;
    final l10n = context.l10n;
    if (tree.nodes.isEmpty) {
      if (state.loading) {
        return const Center(child: CircularProgressIndicator());
      }
      return TaskViewState(
        icon: LucideIcons.folder,
        title: state.hasError ? l10n.taskListLoadError : l10n.noProjects,
        actions: state.hasError
            ? ShadButton.secondary(
                onPressed: _model.retry,
                child: Text(l10n.commonRetry),
              )
            : null,
      );
    }
    final colors = context.appColors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final style = Theme.of(context).textTheme.bodyMedium!;
    final sizes = {
      for (final key in tree.visibleKeys)
        key: projectDiagramNodeSize(
          tree.nodes[key]!.project?.displayName(l10n) ??
              tree.nodes[key]!.task?.content ??
              l10n.navProjects,
          style,
          MediaQuery.textScalerOf(context),
          Directionality.of(context),
        ),
    };
    final layout = layoutProjectTree(tree, sizes, rtl: rtl);
    final selectedId = GoRouterState.of(context).uri.queryParameters['task'];
    final tasks = [for (final key in tree.visibleKeys) ?tree.nodes[key]!.task];
    return Column(
      children: [
        if (state.loading) const LinearProgressIndicator(),
        if (state.hasError)
          TextButton.icon(
            onPressed: _model.retry,
            icon: const Icon(LucideIcons.circleAlert, size: 16),
            label: Text(l10n.taskListLoadError),
          ),
        Expanded(
          child: TaskMotionScope(
            builder: (context, motion) => TaskSelectionRegion(
              visibleTasks: tasks,
              isActive: widget.isActive,
              allowProjectMove: tree.movesEnabled,
              scopeKey: projectDiagramScope(widget.projectId),
              child: ProjectTreeScope(
                controller: _projectTree,
                child: SizedBox.expand(
                  key: _viewport,
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(
                      context,
                    ).copyWith(scrollbars: false),
                    child: Scrollbar(
                      controller: _vertical,
                      thumbVisibility: true,
                      scrollbarOrientation: ScrollbarOrientation.right,
                      notificationPredicate: (n) =>
                          n.metrics.axis == Axis.vertical,
                      child: Scrollbar(
                        controller: _horizontal,
                        thumbVisibility: true,
                        notificationPredicate: (n) =>
                            n.metrics.axis == Axis.horizontal,
                        child: SingleChildScrollView(
                          controller: _horizontal,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: layout.size.width,
                            child: SingleChildScrollView(
                              controller: _vertical,
                              child: SizedBox(
                                width: layout.size.width,
                                height: layout.size.height,
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: CustomPaint(
                                          painter: _Connections(
                                            layout,
                                            colors.border,
                                            rtl,
                                          ),
                                        ),
                                      ),
                                    ),
                                    for (final entry in layout.rects.entries)
                                      Positioned.fromRect(
                                        rect: entry.value,
                                        child: _DiagramNode(
                                          key: ValueKey(entry.key),
                                          tree: tree,
                                          node: tree.nodes[entry.key]!,
                                          selected:
                                              selectedId != null &&
                                              tree.nodes[entry.key]!.task?.id ==
                                                  selectedId,
                                          onExpand: () => _action(
                                            () => _model.expand(
                                              entry.key,
                                              !tree.expandedKeys.contains(
                                                entry.key,
                                              ),
                                            ),
                                          ),
                                          onDrop: (target) {
                                            _stopDrag();
                                            unawaited(
                                              _action(
                                                () => _model.place(target),
                                              ),
                                            );
                                          },
                                          onDrag: _drag,
                                          onDragEnd: _stopDrag,
                                          onAddTask: () => _action(() async {
                                            await _model.reveal(entry.key);
                                            if (context.mounted) {
                                              showQuickAddDialog(
                                                context,
                                                projectId: tree
                                                    .nodes[entry.key]!
                                                    .project!
                                                    .id,
                                              );
                                            }
                                          }),
                                          onAddSubtask: () => _addSubtask(
                                            tree.nodes[entry.key]!.task!,
                                          ),
                                          onMoveTask: () =>
                                              _moveTask(tree, entry.key),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _addSubtask(TaskItem task) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _DiagramSubtaskDialog(task: task),
    );
    if (saved == true && mounted) {
      await _action(() => _model.reveal('t:${task.id}'));
    }
  }

  Future<void> _moveTask(ProjectTreeData tree, String key) async {
    final target = await showDialog<ProjectDiagramDrop>(
      context: context,
      builder: (context) {
        final l10n = context.l10n;
        return ShadDialog(
          title: Text(l10n.taskMove),
          child: Material(
            type: MaterialType.transparency,
            child: SizedBox(
              width: 420,
              height: 400,
              child: ListView(
                children: [
                  for (final node in tree.nodes.values)
                    for (final position in ProjectDropPosition.values)
                      if (projectDiagramDrop(tree, key, node.key, position)
                          case final target?)
                        ListTile(
                          title: Text(
                            node.project?.displayName(l10n) ??
                                node.task!.content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(switch (position) {
                            ProjectDropPosition.before =>
                              l10n.projectPlaceBefore,
                            ProjectDropPosition.inside =>
                              l10n.projectPlaceInside,
                            ProjectDropPosition.after => l10n.projectPlaceAfter,
                          }),
                          onTap: () => Navigator.pop(context, target),
                        ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (target != null && mounted) await _action(() => _model.place(target));
  }
}

class _DiagramNode extends ConsumerStatefulWidget {
  const _DiagramNode({
    required this.tree,
    required this.node,
    required this.selected,
    required this.onExpand,
    required this.onDrop,
    required this.onDrag,
    required this.onDragEnd,
    required this.onAddTask,
    required this.onAddSubtask,
    required this.onMoveTask,
    super.key,
  });
  final ProjectTreeData tree;
  final ProjectTreeNode node;
  final bool selected;
  final VoidCallback onExpand, onDragEnd, onAddTask, onAddSubtask, onMoveTask;
  final ValueChanged<ProjectDiagramDrop> onDrop;
  final ValueChanged<Offset> onDrag;
  @override
  ConsumerState<_DiagramNode> createState() => _DiagramNodeState();
}

class _DiagramNodeState extends ConsumerState<_DiagramNode> {
  ProjectDropPosition? _hover;
  PointerDeviceKind? _pointer;
  String? _source(Object data) => switch (data) {
    ProjectDragData d => 'p:${d.id}',
    String id => 't:$id',
    _ => null,
  };
  ProjectDropPosition _position(Offset global) {
    final box = context.findRenderObject()! as RenderBox;
    final y = box.globalToLocal(global).dy / box.size.height;
    return y < .2
        ? ProjectDropPosition.before
        : y > .8
        ? ProjectDropPosition.after
        : ProjectDropPosition.inside;
  }

  ProjectDiagramDrop? _target(DragTargetDetails<Object> details) {
    final key = _source(details.data);
    return key == null
        ? null
        : projectDiagramDrop(
            widget.tree,
            key,
            widget.node.key,
            _position(details.offset),
          );
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node, tree = widget.tree;
    final project = node.project;
    final colors = context.appColors;
    final l10n = context.l10n;
    final expanded = tree.expandedKeys.contains(node.key);
    final root = node.key == tree.rootKey;
    final canMove = canMoveProjectDiagramNode(tree, node.key);
    final canDrag = canMove && !usesTouchTaskInteraction;
    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: node.isCatalogRoot
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.navProjects,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const Spacer(),
                      Text(
                        node.progress.label,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      if (node.children.isEmpty)
                        Text(
                          l10n.noProjects,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                )
              : project == null
              ? TaskListItem(
                  task: node.task!,
                  diagram: true,
                  enableSubtaskDrop: false,
                  subtaskProgress: node.progress,
                  onAddSubtask: widget.onAddSubtask,
                  onDiagramMove: tree.movesEnabled ? widget.onMoveTask : null,
                )
              : Column(
                  children: [
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        hoverColor: Colors.transparent,
                        onTap: root
                            ? null
                            : () => context.go('/project/${project.id}'),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              project.displayName(l10n),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Icon(
                            projectIconData(project.icon),
                            size: 16,
                            color: colors.secondaryText,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            node.progress.label,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        if (project.canEdit && !project.isArchived)
                          IconButton(
                            onPressed: widget.onAddTask,
                            tooltip: l10n.addTask,
                            icon: const Icon(LucideIcons.plus, size: 18),
                          ),
                        const Spacer(),
                        if (!project.canEdit && canMove)
                          AppActionMenu(
                            tooltip: l10n.taskMore,
                            items: [
                              ShadContextMenuItem(
                                height: 44,
                                onPressed: () => showMoveProjectDialog(
                                  context,
                                  ref,
                                  project,
                                ),
                                leading: const Icon(
                                  LucideIcons.folderInput,
                                  size: 16,
                                ),
                                child: Text(l10n.moveProject),
                              ),
                            ],
                          ),
                        if (project.canEdit)
                          SizedBox(
                            width: 48,
                            height: 48,
                            child: ProjectContextMenu(
                              project: project,
                              showMenuButton: true,
                              allowMove: tree.movesEnabled,
                              child: const SizedBox.shrink(),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
        ),
        SizedBox(
          height: 44,
          child: Row(
            children: [
              if (node.children.isNotEmpty && !root)
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Semantics(
                      expanded: expanded,
                      child: IconButton(
                        onPressed: widget.onExpand,
                        tooltip: expanded
                            ? l10n.projectCollapseBranch
                            : l10n.projectExpandBranch,
                        icon: Icon(
                          expanded
                              ? LucideIcons.chevronDown
                              : LucideIcons.chevronRight,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              if (canDrag)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(LucideIcons.gripVertical, size: 14),
                ),
            ],
          ),
        ),
      ],
    );
    if (node.task case final task?) {
      final selection = TaskSelectionScope.maybeOf(context);
      content = Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: Colors.transparent,
          onTap: () => selection?.active == true
              ? selection!.toggle(task.id)
              : openTaskDetails(context, task.id),
          child: content,
        ),
      );
    }
    content = DecoratedBox(
      decoration: BoxDecoration(
        color: project == null ? colors.surface : colors.surfaceTint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _hover != null || widget.selected
              ? colors.accent
              : colors.border,
          width: _hover != null || widget.selected ? 2 : 1,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: content),
          if (_hover != null && _hover != ProjectDropPosition.inside)
            Positioned(
              top: _hover == ProjectDropPosition.before ? 0 : null,
              bottom: _hover == ProjectDropPosition.after ? 0 : null,
              left: 8,
              right: 8,
              height: 3,
              child: ColoredBox(color: colors.accent),
            ),
        ],
      ),
    );
    if (canDrag) {
      // Touch scroll stays native on the web as well as native mobile targets.
      content = Listener(
        onPointerDown: (event) {
          if (_pointer != event.kind) setState(() => _pointer = event.kind);
        },
        child: Draggable<Object>(
          maxSimultaneousDrags: _pointer == PointerDeviceKind.touch ? 0 : 1,
          data: project == null ? node.task!.id : ProjectDragData(project.id),
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: Material(
            color: colors.surface,
            borderRadius: BorderRadius.circular(8),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                project?.displayName(l10n) ?? node.task!.content,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          onDragUpdate: (details) => widget.onDrag(details.globalPosition),
          onDragEnd: (_) => widget.onDragEnd(),
          onDraggableCanceled: (_, _) => widget.onDragEnd(),
          childWhenDragging: Opacity(opacity: .4, child: content),
          child: content,
        ),
      );
    }
    return DragTarget<Object>(
      onWillAcceptWithDetails: (d) {
        final key = _source(d.data);
        return key != null && canEnterProjectDiagramDrop(tree, key, node.key);
      },
      onMove: (d) {
        final hover = _target(d) == null ? null : _position(d.offset);
        if (_hover != hover) setState(() => _hover = hover);
      },
      onLeave: (_) => setState(() => _hover = null),
      onAcceptWithDetails: (d) {
        final target = _target(d);
        setState(() => _hover = null);
        if (target != null) widget.onDrop(target);
      },
      builder: (_, _, _) => content,
    );
  }
}

class _Connections extends CustomPainter {
  _Connections(this.layout, this.color, this.rtl);
  final ProjectTreeLayout layout;
  final Color color;
  final bool rtl;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final (parent, child) in layout.edges) {
      final a = layout.rects[parent], b = layout.rects[child];
      if (a == null || b == null) continue;
      final path = Path();
      final start = rtl ? a.centerLeft : a.centerRight,
          end = rtl ? b.centerRight : b.centerLeft;
      final mid = (start.dx + end.dx) / 2;
      path
        ..moveTo(start.dx, start.dy)
        ..lineTo(mid, start.dy)
        ..lineTo(mid, end.dy)
        ..lineTo(end.dx, end.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_Connections old) =>
      old.layout != layout || old.color != color || old.rtl != rtl;
}

class _DiagramSubtaskDialog extends ConsumerStatefulWidget {
  const _DiagramSubtaskDialog({required this.task});
  final TaskItem task;
  @override
  ConsumerState<_DiagramSubtaskDialog> createState() =>
      _DiagramSubtaskDialogState();
}

class _DiagramSubtaskDialogState extends ConsumerState<_DiagramSubtaskDialog> {
  final _text = TextEditingController();
  final _identity = Object();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final saved = await ref
        .read(taskEditorViewModelProvider(_identity).notifier)
        .createSubtask(widget.task, _text.text);
    if (mounted && saved) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(taskEditorViewModelProvider(_identity));
    return ShadDialog(
      title: Text(context.l10n.addSubtask),
      actions: [
        ShadButton(
          onPressed: state.saving || _text.text.trim().isEmpty ? null : _save,
          child: Text(context.l10n.addSubtask),
        ),
      ],
      child: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShadInput(
              controller: _text,
              autofocus: true,
              placeholder: Text(context.l10n.addSubtaskHint),
              onChanged: (text) => ref
                  .read(taskEditorViewModelProvider(_identity).notifier)
                  .updateDraft(text),
              onSubmitted: (_) {
                if (!state.saving && _text.text.trim().isNotEmpty) {
                  unawaited(_save());
                }
              },
            ),
            if (state.failed)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(context.l10n.taskCreateFailed),
              ),
          ],
        ),
      ),
    );
  }
}
