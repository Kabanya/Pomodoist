part of 'calendar_screen.dart';

class _CalendarAddTarget extends StatefulWidget {
  const _CalendarAddTarget({
    required this.date,
    required this.onAdd,
    this.alignment = Alignment.center,
  });

  final DateTime date;
  final VoidCallback onAdd;
  final Alignment alignment;

  @override
  State<_CalendarAddTarget> createState() => _CalendarAddTargetState();
}

class _CalendarAddTargetState extends State<_CalendarAddTarget> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final touch = switch (defaultTargetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => false,
      _ => true,
    };
    final colors = context.appColors;
    final label = context.l10n.taskSchedule;
    final date = intl.DateFormat.yMMMMd(
      Localizations.localeOf(context).toString(),
    ).format(widget.date);
    return Semantics(
      button: true,
      label: '$label, $date',
      onTap: widget.onAdd,
      child: InkWell(
        onTap: widget.onAdd,
        onHover: (value) => setState(() => _hovered = value),
        onFocusChange: (value) => setState(() => _focused = value),
        excludeFromSemantics: true,
        borderRadius: BorderRadius.circular(6),
        hoverColor: colors.surfaceTint.withValues(alpha: .5),
        focusColor: colors.accentTint,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Align(
            alignment: widget.alignment,
            child: AnimatedOpacity(
              opacity: touch || _hovered || _focused ? 1 : 0,
              duration: AppMotion.duration(context, AppMotion.hover),
              curve: AppMotion.curve,
              child: ExcludeSemantics(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceTint,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.secondaryText,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarTaskCard extends ConsumerStatefulWidget {
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
  ConsumerState<_CalendarTaskCard> createState() => _CalendarTaskCardState();
}

class _CalendarTaskCardState extends ConsumerState<_CalendarTaskCard> {
  final _menuController = ShadContextMenuController();
  bool _focusing = false;
  TaskItem get task => widget.task;
  ProjectItem? get project => widget.project;
  _CalendarActions get actions => widget.actions;
  bool get compact => widget.compact;
  bool get fill => widget.fill;

  @override
  void dispose() {
    _menuController.dispose();
    super.dispose();
  }

  Future<void> _focus(CalendarFocusAction action) async {
    if (_focusing) return;
    setState(() => _focusing = true);
    try {
      await ref
          .read(calendarViewModelProvider.notifier)
          .focusTask(
            task.id,
            action,
            confirmSwitch: () async {
              if (!mounted) return false;
              final confirmed = await showDialog<bool>(
                context: context,
                animationStyle: AnimationStyle(
                  duration: AppMotion.duration(context, AppMotion.popup),
                  reverseDuration: AppMotion.duration(context, AppMotion.popup),
                  curve: AppMotion.curve,
                ),
                builder: (dialogContext) => AlertDialog(
                  title: Text(context.l10n.taskFocusSwitchTitle),
                  content: Text(
                    context.l10n.taskFocusSwitchMessage(task.content),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: Text(context.l10n.commonCancel),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: Text(context.l10n.taskFocusSwitchConfirm),
                    ),
                  ],
                ),
              );
              return confirmed == true && mounted;
            },
          );
    } catch (_) {
      if (mounted)
        _calendarError(context, context.l10n.taskActionFailedCount(1));
    } finally {
      if (mounted) setState(() => _focusing = false);
    }
  }

  List<Widget> _menuItems(
    BuildContext context,
    AppDateTimePickerState picker,
    bool enabled,
    List<CalendarFocusAction> focusActions,
  ) {
    final l10n = context.l10n;
    final selection = TaskSelectionScope.maybeOf(context);
    if (selection != null && selection.active) {
      Widget bulk(
        IconData icon,
        String label,
        Future<void> Function(BuildContext) action,
      ) => ShadContextMenuItem(
        enabled: selection.hasSelection && !selection.pending,
        leading: Icon(icon, size: 16),
        onPressed: () => unawaited(action(context)),
        child: Text(label),
      );
      return [
        ShadContextMenuItem(
          enabled: false,
          child: Text(l10n.taskSelectedCount(selection.selectedCount)),
        ),
        if (task.canEdit)
          ShadContextMenuItem(
            enabled: !selection.pending && !actions.pending.contains(task.id),
            leading: Icon(
              selection.isSelected(task.id)
                  ? LucideIcons.circleCheck
                  : LucideIcons.circle,
              size: 16,
            ),
            onPressed: () => selection.toggle(task.id),
            child: Text(l10n.taskSelect),
          ),
        bulk(LucideIcons.calendar, l10n.taskDue, selection.showDue),
        bulk(LucideIcons.folder, l10n.taskProject, selection.showProject),
        bulk(LucideIcons.tag, l10n.taskLabels, selection.showLabels),
        bulk(LucideIcons.flag, l10n.taskPriority, selection.showPriority),
        bulk(LucideIcons.calendarX, l10n.taskClearDue, selection.clearSchedule),
        bulk(LucideIcons.copy, l10n.taskDuplicate, selection.duplicate),
        bulk(LucideIcons.trash2, l10n.commonDelete, selection.delete),
        bulk(LucideIcons.ellipsis, l10n.taskMore, selection.showMore),
      ];
    }
    return [
      ShadContextMenuItem(
        leading: const Icon(LucideIcons.externalLink, size: 16),
        onPressed: () => openTaskDetails(context, task.id),
        child: Text(l10n.commonOpen),
      ),
      for (final action in focusActions)
        ShadContextMenuItem(
          enabled: !_focusing && !actions.pending.contains(task.id),
          leading: Icon(switch (action) {
            CalendarFocusAction.pause => LucideIcons.pause,
            CalendarFocusAction.stop => LucideIcons.circleStop,
            _ => LucideIcons.play,
          }, size: 16),
          onPressed: () => unawaited(_focus(action)),
          child: Text(switch (action) {
            CalendarFocusAction.start => l10n.startFocus,
            CalendarFocusAction.pause => l10n.pause,
            CalendarFocusAction.resume => l10n.resume,
            CalendarFocusAction.startInterval => l10n.startInterval,
            CalendarFocusAction.stop => l10n.commonStop,
          }),
        ),
      if (enabled) ...[
        if (selection != null)
          ShadContextMenuItem(
            leading: const Icon(LucideIcons.listChecks, size: 16),
            onPressed: () => selection.begin(task.id),
            child: Text(l10n.taskSelect),
          ),
        ShadContextMenuItem(
          leading: const Icon(LucideIcons.calendar, size: 16),
          onPressed: () async {
            final date = await picker.pickDate(
              initialDate: task.schedule?.displayDate ?? DateTime.now(),
              firstDate: DateTime(1900),
              lastDate: DateTime(2200),
            );
            if (date != null && mounted) await actions.onMove(task.id, date);
          },
          child: Text(l10n.taskSchedule),
        ),
        ShadContextMenuItem(
          onPressed: () => unawaited(
            actions.onMove(
              task.id,
              task.schedule?.displayDate ?? DateTime.now(),
              allDay: true,
            ),
          ),
          child: Text(l10n.allDay),
        ),
        ShadContextMenuItem(
          onPressed: () => unawaited(actions.onUnschedule(task.id)),
          child: Text(l10n.taskClearDue),
        ),
        ShadContextMenuItem(
          leading: const Icon(LucideIcons.check, size: 16),
          onPressed: () => unawaited(actions.onComplete(task.id)),
          child: Text(l10n.markComplete),
        ),
        if (selection != null)
          ShadContextMenuItem(
            leading: const Icon(LucideIcons.trash2, size: 16),
            onPressed: () {
              selection.begin(task.id);
              unawaited(selection.delete(context));
            },
            child: Text(l10n.commonDelete),
          ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final selection = TaskSelectionScope.maybeOf(context);
    final selecting = selection?.active ?? false;
    final selected = selection?.isSelected(task.id) ?? false;
    void selectTask() {
      if (!task.canEdit ||
          task.isDeleted ||
          task.isCompleted ||
          (selection?.pending ?? false) ||
          actions.pending.contains(task.id))
        return;
      if (selecting) {
        selection?.toggle(task.id);
      } else {
        selection?.begin(task.id);
      }
    }

    final accent = projectColorValue(
      project == null ? inboxProjectColorHex : effectiveProjectColor(project!),
    );
    final enabled =
        task.canEdit &&
        !task.isCompleted &&
        !task.isDeleted &&
        !actions.pending.contains(task.id) &&
        !_focusing &&
        !(selection?.pending ?? false);
    final time = task.schedule == null
        ? context.l10n.calendarUnscheduled
        : formatTaskSchedule(context, task.schedule);
    final focusActions = ref.watch(calendarTaskFocusActionsProvider(task));
    final card = AppDateTimePicker(
      builder: (context, picker) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.contextMenu):
              _menuController.show,
          const SingleActivator(LogicalKeyboardKey.f10, shift: true):
              _menuController.show,
        },
        child: AppContextMenuRegion(
          controller: _menuController,
          enableLongPress: false,
          items: _menuItems(context, picker, enabled, focusActions),
          child: Tooltip(
            message: '${task.content}\n$time',
            child: Material(
              color: selected
                  ? colors.accentTint
                  : Color.alphaBlend(
                      accent.withValues(alpha: 0.08),
                      colors.surface,
                    ),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () {
                  final keyboard = HardwareKeyboard.instance;
                  if (selection != null &&
                      (selecting ||
                          keyboard.isControlPressed ||
                          keyboard.isMetaPressed)) {
                    selectTask();
                  } else {
                    openTaskDetails(context, task.id);
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  constraints: fill
                      ? const BoxConstraints.expand()
                      : BoxConstraints(minHeight: compact ? 40 : 58),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      width: selected ? 2 : 1,
                      color: selected
                          ? colors.accent
                          : task.priority == 1
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
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          9,
                          4,
                          4,
                          4,
                        ),
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
                                if (selecting &&
                                    task.canEdit &&
                                    constraints.maxWidth >= 40)
                                  Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                      end: 4,
                                    ),
                                    child: Icon(
                                      selected
                                          ? LucideIcons.circleCheck
                                          : LucideIcons.circle,
                                      size: 16,
                                      color: selected
                                          ? colors.accent
                                          : colors.secondaryText,
                                    ),
                                  ),
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w500,
                                            ),
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
                                          constraints.maxHeight >=
                                              lineHeight * 5 &&
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
                                    child: IconButton(
                                      padding: EdgeInsets.zero,
                                      tooltip: context.l10n.taskMore,
                                      icon: const Icon(
                                        LucideIcons.ellipsis,
                                        size: 15,
                                      ),
                                      onPressed: _menuController.show,
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
        ),
      ),
    );
    final accessibleCard = Semantics(
      selected: selecting ? selected : null,
      child: card,
    );
    if (!enabled || selecting) return accessibleCard;
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
            childWhenDragging: Opacity(opacity: .35, child: accessibleCard),
            child: accessibleCard,
          )
        : LongPressDraggable<String>(
            data: task.id,
            feedback: feedback,
            childWhenDragging: Opacity(opacity: .35, child: accessibleCard),
            child: accessibleCard,
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
