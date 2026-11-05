part of 'timeline_screen.dart';

class _TimelineCompactTaskBlock extends ConsumerWidget {
  const _TimelineCompactTaskBlock({
    required this.task,
    this.project,
    this.showProjectName = false,
    this.fillHeight = false,
    this.allDayRow = false,
    this.vertical = false,
    this.allowResize = true,
    this.onResizeStart,
    this.onResizeUpdate,
    this.onResizeEnd,
    this.onResizeCancel,
  });

  final TaskItem task;
  final ProjectItem? project;
  final bool showProjectName;
  final bool fillHeight;
  final bool allDayRow;
  final bool vertical;
  final bool allowResize;
  final VoidCallback? onResizeStart;
  final ValueChanged<double>? onResizeUpdate;
  final VoidCallback? onResizeEnd;
  final VoidCallback? onResizeCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final priorityColor = _priorityColor(task.priority, colors);
    final projectHex = project == null
        ? inboxProjectColorHex
        : effectiveProjectColor(project!);
    final projectColor = projectColorValue(projectHex);
    final schedule = task.schedule;
    final timeRange = schedule?.isTimed == true
        ? '${_formatMinutes(timelineStartMinutes(schedule!))} – '
              '${_formatMinutes(timelineEndMinutes(schedule))}'
        : null;
    final projectName =
        project?.displayName(context.l10n) ??
        (task.projectId == inboxProjectId ? context.l10n.navInbox : null);
    final timeLabel = showProjectName && projectName != null
        ? [projectName, ?timeRange].join(' · ')
        : timeRange;
    final splitMetadata =
        vertical &&
        projectName != null &&
        timeRange != null &&
        MediaQuery.textScalerOf(context).scale(16) > 20;
    final canResize =
        allowResize && onResizeStart != null && onResizeEnd != null;
    void finishResize() => onResizeEnd?.call();
    final block = Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('timeline-task-${task.id}'),
        onTap: () => openTaskDetails(context, task.id),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: fillHeight
              ? const BoxConstraints.expand()
              : BoxConstraints(minHeight: allDayRow ? 60 : 44),
          decoration: BoxDecoration(
            color: allDayRow ? Colors.transparent : colors.accentTint,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            children: [
              if (!allDayRow)
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  bottom: 0,
                  width: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: projectColor,
                      borderRadius: const BorderRadiusDirectional.horizontal(
                        start: Radius.circular(8),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  allDayRow ? 0 : 10,
                  4,
                  canResize && !vertical ? 13 : 6,
                  4,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) => Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (allDayRow || constraints.maxWidth >= 68) ...[
                        SizedBox.square(
                          dimension: allDayRow ? 44 : 36,
                          child: TaskCompletionControl(
                            taskId: task.id,
                            tooltip: task.isCompleted
                                ? context.l10n.markOpen
                                : context.l10n.markComplete,
                            isCompleted: task.isCompleted,
                            color: priorityColor,
                            fillColor: colors.accentFill,
                            onPressed: () {
                              if (task.isCompleted) {
                                unawaited(() async {
                                  final reopened = await ref
                                      .read(timelineViewModelProvider.notifier)
                                      .reopen(task.id);
                                  if (context.mounted && reopened != null) {
                                    TaskMotionScope.maybeOf(
                                      context,
                                    )?.reopened([reopened]);
                                    await playHaptic(AppHapticCue.light);
                                  }
                                }());
                              } else {
                                unawaited(
                                  completeTaskWithUndoFeedback(
                                    context,
                                    complete: () => ref
                                        .read(
                                          timelineViewModelProvider.notifier,
                                        )
                                        .complete(task.id),
                                    undo: () => ref
                                        .read(
                                          timelineViewModelProvider.notifier,
                                        )
                                        .reopen(task.id),
                                  ).then<void>((_) {}),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    task.content,
                                    maxLines:
                                        allDayRow || (fillHeight && !vertical)
                                        ? 2
                                        : 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          fontWeight: allDayRow
                                              ? FontWeight.w500
                                              : FontWeight.w700,
                                          color: colors.primaryText,
                                        ),
                                  ),
                                ),
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: constraints.maxWidth / 4,
                                  ),
                                  child: TaskHierarchySummary(
                                    task: task,
                                    compact: true,
                                  ),
                                ),
                              ],
                            ),
                            if (timeLabel != null)
                              Flexible(
                                child: Text(
                                  splitMetadata
                                      ? '$projectName\n$timeRange'
                                      : timeLabel,
                                  maxLines: splitMetadata ? 2 : 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(color: colors.mutedText),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (canResize)
                PositionedDirectional(
                  key: Key('timeline-resize-${task.id}'),
                  end: 0,
                  start: vertical ? 0 : null,
                  top: vertical ? null : 0,
                  bottom: 0,
                  width: vertical ? null : 12,
                  height: vertical ? 9 : null,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: vertical
                        ? null
                        : (_) => onResizeStart?.call(),
                    onHorizontalDragUpdate: vertical
                        ? null
                        : (details) => onResizeUpdate?.call(
                            Directionality.of(context) == TextDirection.rtl
                                ? -details.delta.dx
                                : details.delta.dx,
                          ),
                    onHorizontalDragEnd: vertical
                        ? null
                        : (_) => finishResize(),
                    onVerticalDragStart: vertical
                        ? (_) => onResizeStart?.call()
                        : null,
                    onVerticalDragUpdate: vertical
                        ? (details) => onResizeUpdate?.call(details.delta.dy)
                        : null,
                    onVerticalDragEnd: vertical ? (_) => finishResize() : null,
                    onHorizontalDragCancel: vertical ? null : onResizeCancel,
                    onVerticalDragCancel: vertical ? onResizeCancel : null,
                    child: const SizedBox.expand(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return TaskMotionItem(
      taskId: task.id,
      child: _TimelineDragSource(task: task, child: block),
    );
  }
}

class _TimelineDragSource extends StatelessWidget {
  const _TimelineDragSource({required this.task, required this.child});

  final TaskItem task;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final feedback = Transform.scale(
      scale: 1.025,
      child: Material(
        color: Colors.transparent,
        child: SizedBox(width: 260, height: 64, child: child),
      ),
    );
    final childWhenDragging = Opacity(opacity: 0.35, child: child);
    if (_usesImmediateTaskDrag(defaultTargetPlatform)) {
      return Draggable<String>(
        data: task.id,
        feedback: feedback,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        childWhenDragging: childWhenDragging,
        child: child,
      );
    }
    return LongPressDraggable<String>(
      data: task.id,
      feedback: feedback,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      childWhenDragging: childWhenDragging,
      child: child,
    );
  }
}

class _InlineAddField extends StatefulWidget {
  const _InlineAddField({
    super.key,
    required this.hintText,
    required this.onSubmit,
    required this.onCancel,
  });

  final String hintText;
  final Future<void> Function(String input) onSubmit;
  final VoidCallback onCancel;

  @override
  State<_InlineAddField> createState() => _InlineAddFieldState();
}

class _InlineAddFieldState extends State<_InlineAddField> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShortcutHintsScope(
      hints: [ShortcutHint(context.l10n.commonCancel, 'Esc')],
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.appColors.surface,
            border: Border.all(color: context.appColors.accent),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      hintText: widget.hintText,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                Tooltip(
                  message: context.l10n.commonCancel,
                  child: ShadIconButton.ghost(
                    onPressed: _busy ? null : widget.onCancel,
                    icon: const Icon(LucideIcons.x),
                    enabled: !(_busy),
                    width: 40,
                    height: 40,
                  ),
                ),
                Tooltip(
                  message: context.l10n.commonAdd,
                  child: ShadIconButton.secondary(
                    onPressed: _busy ? null : _submit,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.plus),
                    enabled: !(_busy),
                    width: 40,
                    height: 40,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final input = _controller.text.trim();
    if (input.isEmpty || _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onSubmit(input);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.taskCreateFailed)));
      setState(() => _busy = false);
    }
  }
}

class _TimedTaskLayout {
  const _TimedTaskLayout({
    required this.task,
    required this.lane,
    required this.laneCount,
  });

  final TaskItem task;
  final int lane;
  final int laneCount;
}
