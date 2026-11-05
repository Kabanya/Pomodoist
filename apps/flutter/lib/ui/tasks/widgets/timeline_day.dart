part of 'timeline_screen.dart';

class _TimelineDay extends ConsumerWidget {
  const _TimelineDay({
    required this.day,
    required this.presentation,
    required this.visibleHours,
    required this.compact,
  });

  final DateTime day;
  final TimelineDayPresentation presentation;
  final TimelineVisibleHours visibleHours;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hourWidth = ref.watch(
      timelineViewModelProvider.select((state) => state.hourWidth),
    );
    final data = presentation.data;
    final tasksById = presentation.tasksById;
    final projectsById = presentation.projectsById;
    final projectRows = presentation.projectRows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AllDaySection(
          day: day,
          tasks: data.allDay,
          tasksById: tasksById,
          projectsById: projectsById,
        ),
        if (data.beforeHours.isNotEmpty) ...[
          const SizedBox(height: 12),
          _OutOfRangeSection(
            key: const Key('timeline-before-hours-section'),
            title: context.l10n.timelineBeforeHours,
            tasks: data.beforeHours,
            projectsById: projectsById,
          ),
        ],
        if (data.afterHours.isNotEmpty) ...[
          const SizedBox(height: 12),
          _OutOfRangeSection(
            key: const Key('timeline-after-hours-section'),
            title: context.l10n.timelineAfterHours,
            tasks: data.afterHours,
            projectsById: projectsById,
          ),
        ],
        const SizedBox(height: 32),
        LayoutBuilder(
          builder: (context, constraints) {
            final projectWidth = _timelineProjectColumnWidth(
              context,
              constraints.maxWidth,
            );
            return _TimelineGrid(
              day: day,
              projectRows: projectRows,
              tasksByProject: data.timedByProject,
              compact: compact,
              baseHourExtent: compact
                  ? 48
                  : math.max(
                      60,
                      (constraints.maxWidth -
                              projectWidth -
                              _timelineRulerTail(context)) /
                          9,
                    ),
              tasksById: tasksById,
              visibleHours: visibleHours,
              hourWidth: hourWidth,
            );
          },
        ),
      ],
    );
  }
}

class _AllDaySection extends ConsumerStatefulWidget {
  const _AllDaySection({
    required this.day,
    required this.tasks,
    required this.tasksById,
    required this.projectsById,
  });

  final DateTime day;
  final List<TaskItem> tasks;
  final Map<String, TaskItem> tasksById;
  final Map<String, ProjectItem> projectsById;

  @override
  ConsumerState<_AllDaySection> createState() => _AllDaySectionState();
}

class _AllDaySectionState extends ConsumerState<_AllDaySection> {
  bool _adding = false;
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        final task = widget.tasksById[details.data];
        return task?.schedule?.isTimed ?? false;
      },
      onAcceptWithDetails: (details) {
        final task = widget.tasksById[details.data];
        if (task != null) {
          unawaited(
            _updateSchedule(
              context,
              ref,
              task,
              TaskSchedule.allDay(widget.day),
            ),
          );
        }
      },
      builder: (context, candidateData, rejectedData) {
        final accepting = candidateData.isNotEmpty;
        return AnimatedContainer(
          key: const Key('timeline-all-day-section'),
          duration: AppMotion.duration(context, AppMotion.hover),
          decoration: BoxDecoration(
            color: accepting ? colors.accentTint : colors.surface,
            border: Border.all(
              color: accepting ? colors.accent : colors.border,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          curve: AppMotion.curve,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        expanded: _expanded,
                        child: InkWell(
                          key: const Key('timeline-all-day-toggle'),
                          onTap: () => setState(() => _expanded = !_expanded),
                          borderRadius: BorderRadius.circular(8),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 44),
                            child: Row(
                              children: [
                                Icon(
                                  _expanded
                                      ? LucideIcons.chevronDown
                                      : LucideIcons.chevronRight,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Flexible(
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: context.l10n.timelineAllDay,
                                        ),
                                        TextSpan(
                                          text: ' · ${widget.tasks.length}',
                                          style: TextStyle(
                                            color: colors.mutedText,
                                          ),
                                        ),
                                      ],
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_expanded && !_adding && widget.tasks.isNotEmpty)
                      Tooltip(
                        message: context.l10n.timelineAddAllDayHint,
                        child: ShadIconButton.ghost(
                          onPressed: () => setState(() => _adding = true),
                          width: 44,
                          height: 44,
                          icon: const Icon(LucideIcons.plus, size: 18),
                        ),
                      ),
                  ],
                ),
                if (_adding)
                  Offstage(
                    offstage: !_expanded,
                    child: ExcludeFocus(
                      excluding: !_expanded,
                      child: _InlineAddField(
                        key: const Key('timeline-inline-add-all-day'),
                        hintText: context.l10n.timelineAddAllDayHint,
                        onCancel: () => setState(() => _adding = false),
                        onSubmit: (input) async {
                          final taskId = await ref
                              .read(timelineViewModelProvider.notifier)
                              .create(
                                input,
                                schedule: TaskSchedule.allDay(widget.day),
                              );
                          if (mounted) {
                            TaskMotionScope.maybeOf(
                              this.context,
                            )?.created({taskId});
                            await playHaptic(AppHapticCue.light);
                            setState(() => _adding = false);
                          }
                        },
                      ),
                    ),
                  )
                else if (_expanded && widget.tasks.isEmpty)
                  InkWell(
                    onTap: () => setState(() => _adding = true),
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      height: 44,
                      child: Center(
                        child: Text(
                          context.l10n.timelineNoAllDayTasks,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colors.mutedText),
                        ),
                      ),
                    ),
                  )
                else if (_expanded)
                  Column(
                    children: [
                      for (final task in widget.tasks) ...[
                        _TimelineCompactTaskBlock(
                          task: task,
                          project: widget.projectsById[task.projectId],
                          showProjectName: true,
                          allDayRow: true,
                        ),
                        if (task != widget.tasks.last)
                          Divider(height: 1, color: colors.border),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OutOfRangeSection extends StatelessWidget {
  const _OutOfRangeSection({
    super.key,
    required this.title,
    required this.tasks,
    required this.projectsById,
  });

  final String title;
  final List<TaskItem> tasks;
  final Map<String, ProjectItem> projectsById;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            for (final task in tasks) ...[
              _TimelineCompactTaskBlock(
                task: task,
                project: projectsById[task.projectId],
                showProjectName: true,
                allowResize: false,
              ),
              if (task != tasks.last) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}
