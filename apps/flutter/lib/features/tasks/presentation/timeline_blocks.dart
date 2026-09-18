part of 'timeline_screen.dart';

class _TimelineCompactTaskBlock extends ConsumerWidget {
  const _TimelineCompactTaskBlock({
    required this.task,
    this.project,
    this.showProjectName = false,
    this.fillHeight = false,
    this.allowResize = true,
    this.onResizeStart,
    this.onResizeUpdate,
    this.onResizeEnd,
  });

  final TaskItem task;
  final ProjectItem? project;
  final bool showProjectName;
  final bool fillHeight;
  final bool allowResize;
  final VoidCallback? onResizeStart;
  final ValueChanged<double>? onResizeUpdate;
  final VoidCallback? onResizeEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final priorityColor = _priorityColor(task.priority, colors);
    final projectHex = project == null
        ? inboxProjectColorHex
        : effectiveProjectColor(project!);
    final projectColor = projectColorValue(projectHex);
    final surfaceColor = Color.alphaBlend(
      projectColor.withValues(alpha: 0.08),
      colors.surface,
    );
    final schedule = task.schedule;
    final rawTimeLabel = schedule == null
        ? null
        : schedule.isTimed
        ? '${_formatMinutes(_startMinutes(schedule))}-${_formatMinutes(_endMinutes(schedule))}'
        : context.l10n.timelineAllDay;
    final timeLabel = showProjectName && project != null
        ? '${project!.name} · ${rawTimeLabel ?? ''}'
        : rawTimeLabel;
    final block = Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('timeline-task-${task.id}'),
        onTap: () => openTaskDetails(context, task.id),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: fillHeight
              ? const BoxConstraints.expand()
              : const BoxConstraints(minHeight: 44),
          decoration: BoxDecoration(
            color: surfaceColor,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: projectColor,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(8),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 6, 8, 6),
                child: LayoutBuilder(
                  builder: (context, constraints) => Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (constraints.maxWidth >= 72) ...[
                        SizedBox.square(
                          dimension: 28,
                          child: TaskCompletionControl(
                            taskId: task.id,
                            isCompleted: task.isCompleted,
                            color: priorityColor,
                            fillColor: colors.accentFill,
                            onPressed: () {
                              if (task.isCompleted) {
                                unawaited(() async {
                                  await ref
                                      .read(taskRepositoryProvider)
                                      .uncompleteTask(task.id);
                                  final reopened = await ref
                                      .read(taskRepositoryProvider)
                                      .watchTask(task.id)
                                      .first;
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
                                    ref,
                                    task.id,
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
                            Text(
                              task.content,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: colors.primaryText,
                                  ),
                            ),
                            if (timeLabel != null &&
                                (!schedule!.isTimed ||
                                    constraints.maxWidth >= 104)) ...[
                              const SizedBox(height: 2),
                              if (schedule.isTimed)
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: colors.surface.withValues(
                                      alpha: 0.72,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    child: Text(
                                      timeLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(color: colors.mutedText),
                                    ),
                                  ),
                                )
                              else
                                Text(
                                  timeLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(color: colors.mutedText),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (allowResize && onResizeStart != null && onResizeEnd != null)
                Positioned(
                  key: Key('timeline-resize-${task.id}'),
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 12,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (_) => onResizeStart?.call(),
                    onHorizontalDragUpdate: (details) =>
                        onResizeUpdate?.call(details.delta.dx),
                    onHorizontalDragEnd: (_) => onResizeEnd?.call(),
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
    return CallbackShortcuts(
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
