part of 'calendar_screen.dart';

class _CalendarTaskCard extends StatelessWidget {
  const _CalendarTaskCard({
    required this.task,
    required this.project,
    required this.actions,
    this.compact = false,
    this.fill = false,
  });
  final TaskItem task;
  final ProjectItem? project;
  final _CalendarActions actions;
  final bool compact;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final accent = projectColorValue(
      project == null ? inboxProjectColorHex : effectiveProjectColor(project!),
    );
    final enabled =
        task.canEdit &&
        !task.isCompleted &&
        !task.isDeleted &&
        !actions.pending.contains(task.id);
    final time = task.schedule == null
        ? context.l10n.calendarUnscheduled
        : formatTaskSchedule(context, task.schedule);
    final card = AppDateTimePicker(
      builder: (context, picker) => Tooltip(
        message: '${task.content}\n$time',
        child: Material(
          color: Color.alphaBlend(
            accent.withValues(alpha: 0.08),
            colors.surface,
          ),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: () => openTaskDetails(context, task.id),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              clipBehavior: Clip.antiAlias,
              constraints: fill
                  ? const BoxConstraints.expand()
                  : BoxConstraints(minHeight: compact ? 40 : 58),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: task.priority == 1
                      ? colors.overdue.withValues(alpha: .6)
                      : colors.border,
                ),
              ),
              child: Stack(
                children: [
                  PositionedDirectional(
                    start: 0,
                    top: 0,
                    bottom: 0,
                    width: 3,
                    child: ColoredBox(color: accent),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(9, 4, 4, 4),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final textStyle = Theme.of(
                          context,
                        ).textTheme.bodySmall!;
                        final lineHeight =
                            MediaQuery.textScalerOf(
                              context,
                            ).scale(textStyle.fontSize ?? 12) *
                            (textStyle.height ?? 1.4);
                        if (constraints.maxHeight < lineHeight)
                          return const SizedBox.shrink();
                        final menu =
                            constraints.maxWidth >= 90 &&
                            constraints.maxHeight >= 32;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    task.content,
                                    maxLines:
                                        !compact &&
                                            constraints.maxHeight >
                                                lineHeight * 5
                                        ? 2
                                        : 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(fontWeight: FontWeight.w500),
                                  ),
                                  if (!compact &&
                                      constraints.maxHeight >=
                                          lineHeight * 3) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      task.schedule?.isTimed == true
                                          ? '${_calendarTime(context, task.schedule!.start!.toLocal().hour * 60 + task.schedule!.start!.toLocal().minute)}–${_calendarTime(context, task.schedule!.end!.toLocal().hour * 60 + task.schedule!.end!.toLocal().minute)}'
                                          : time,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(color: accent),
                                    ),
                                  ],
                                  if (!compact &&
                                      constraints.maxHeight >= lineHeight * 5 &&
                                      project != null) ...[
                                    const SizedBox(height: 5),
                                    Text(
                                      project!.displayName(context.l10n),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: colors.secondaryText,
                                          ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (menu)
                              SizedBox(
                                width: 28,
                                height: 32,
                                child: PopupMenuButton<String>(
                                  padding: EdgeInsets.zero,
                                  tooltip: context.l10n.taskSchedule,
                                  icon: const Icon(
                                    LucideIcons.ellipsis,
                                    size: 15,
                                  ),
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: 'open',
                                      child: Text(context.l10n.commonOpen),
                                    ),
                                    if (enabled) ...[
                                      PopupMenuItem(
                                        value: 'schedule',
                                        child: Text(context.l10n.taskSchedule),
                                      ),
                                      PopupMenuItem(
                                        value: 'allDay',
                                        child: Text(context.l10n.allDay),
                                      ),
                                      PopupMenuItem(
                                        value: 'clear',
                                        child: Text(
                                          context.l10n.calendarUnscheduled,
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'complete',
                                        child: Text(context.l10n.markComplete),
                                      ),
                                    ],
                                  ],
                                  onSelected: (value) async {
                                    switch (value) {
                                      case 'open':
                                        openTaskDetails(context, task.id);
                                      case 'complete':
                                        await actions.onComplete(task.id);
                                      case 'clear':
                                        await actions.onUnschedule(task.id);
                                      case 'allDay':
                                        await actions.onMove(
                                          task.id,
                                          task.schedule?.displayDate ??
                                              DateTime.now(),
                                          allDay: true,
                                        );
                                      case 'schedule':
                                        final date = await picker.pickDate(
                                          initialDate:
                                              task.schedule?.displayDate ??
                                              DateTime.now(),
                                          firstDate: DateTime(1900),
                                          lastDate: DateTime(2200),
                                        );
                                        if (date != null)
                                          await actions.onMove(task.id, date);
                                    }
                                  },
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!enabled) return card;
    final feedback = Material(
      color: Colors.transparent,
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent),
        ),
        child: Text(
          task.content,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
    final desktop = switch (defaultTargetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      _ => false,
    };
    return desktop
        ? Draggable<String>(
            data: task.id,
            feedback: feedback,
            childWhenDragging: Opacity(opacity: .35, child: card),
            child: card,
          )
        : LongPressDraggable<String>(
            data: task.id,
            feedback: feedback,
            childWhenDragging: Opacity(opacity: .35, child: card),
            child: card,
          );
  }
}

class _CalendarUnscheduled extends StatelessWidget {
  const _CalendarUnscheduled({
    required this.tasks,
    required this.projects,
    required this.actions,
  });
  final List<TaskItem> tasks;
  final Map<String, ProjectItem> projects;
  final _CalendarActions actions;

  @override
  Widget build(BuildContext context) => DragTarget<String>(
    onWillAcceptWithDetails: (details) =>
        !actions.pending.contains(details.data),
    onAcceptWithDetails: (details) =>
        unawaited(actions.onUnschedule(details.data)),
    builder: (context, candidates, rejected) => Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        border: Border.all(
          color: candidates.isEmpty
              ? context.appColors.border
              : context.appColors.accent,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ExpansionTile(
        dense: true,
        initiallyExpanded: tasks.isNotEmpty,
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          '${context.l10n.calendarUnscheduled} · ${tasks.length}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        children: [
          SizedBox(
            height: 76,
            child: tasks.isEmpty
                ? Center(
                    child: Text(
                      context.l10n.noTasksHere,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    scrollDirection: Axis.horizontal,
                    itemCount: tasks.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => SizedBox(
                      width: 210,
                      child: _CalendarTaskCard(
                        task: tasks[i],
                        project: projects[tasks[i].projectId],
                        actions: actions,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}
