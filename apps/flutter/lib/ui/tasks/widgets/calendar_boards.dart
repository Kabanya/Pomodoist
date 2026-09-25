part of 'calendar_screen.dart';

class _CalendarMonthBoard extends StatelessWidget {
  const _CalendarMonthBoard({
    required this.days,
    required this.month,
    required this.projects,
    required this.now,
    required this.actions,
  });
  final List<CalendarDay> days;
  final int month;
  final Map<String, ProjectItem> projects;
  final DateTime now;
  final _CalendarActions actions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = math.max(875.0, constraints.maxWidth);
      final colors = context.appColors;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          child: Column(
            children: [
              Row(
                children: [
                  for (final day in days.take(7))
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          intl.DateFormat.E(
                            Localizations.localeOf(context).toString(),
                          ).format(day.date),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: colors.secondaryText),
                        ),
                      ),
                    ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Table(
                    border: TableBorder.all(color: colors.border),
                    defaultVerticalAlignment: TableCellVerticalAlignment.top,
                    children: [
                      for (var row = 0; row < (days.length / 7).ceil(); row++)
                        TableRow(
                          children: [
                            for (final day in days.skip(row * 7).take(7))
                              _CalendarDateDrop(
                                onDrop: (id) => actions.onMove(id, day.date),
                                child: Container(
                                  height: 208,
                                  color: day.date.month != month
                                      ? colors.surfaceTint.withValues(alpha: .5)
                                      : null,
                                  padding: const EdgeInsets.all(5),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      InkWell(
                                        onTap: () =>
                                            actions.onSelectDay(day.date),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 5,
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  5,
                                                ),
                                                decoration: BoxDecoration(
                                                  color:
                                                      _sameCalendarDay(
                                                        day.date,
                                                        now,
                                                      )
                                                      ? colors.accentFill
                                                      : null,
                                                  borderRadius:
                                                      BorderRadius.circular(5),
                                                ),
                                                child: Text(
                                                  '${day.date.day}',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelMedium
                                                      ?.copyWith(
                                                        color:
                                                            _sameCalendarDay(
                                                              day.date,
                                                              now,
                                                            )
                                                            ? colors.onAccent
                                                            : colors
                                                                  .primaryText,
                                                      ),
                                                ),
                                              ),
                                              const Spacer(),
                                              if (day.tasks.isNotEmpty)
                                                Text(
                                                  '${day.tasks.length}',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelSmall
                                                      ?.copyWith(
                                                        color: colors.mutedText,
                                                      ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: day.tasks.isEmpty
                                            ? _CalendarAddTarget(
                                                date: day.date,
                                                alignment:
                                                    Alignment.bottomCenter,
                                                onAdd: () =>
                                                    actions.onAdd(day.date),
                                              )
                                            : ListView.separated(
                                                itemCount: day.tasks.length,
                                                separatorBuilder: (_, _) =>
                                                    const SizedBox(height: 4),
                                                itemBuilder: (_, i) =>
                                                    _CalendarTaskCard(
                                                      task: day.tasks[i],
                                                      project:
                                                          projects[day
                                                              .tasks[i]
                                                              .projectId],
                                                      actions: actions,
                                                      compact: true,
                                                    ),
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _CalendarRoutineBoard extends StatelessWidget {
  const _CalendarRoutineBoard({
    required this.days,
    required this.settings,
    required this.projects,
    required this.now,
    required this.actions,
    required this.onConfigure,
  });
  final List<CalendarRoutineDay> days;
  final CalendarSettings settings;
  final Map<String, ProjectItem> projects;
  final DateTime now;
  final _CalendarActions actions;
  final VoidCallback onConfigure;

  Widget _tasks(
    BuildContext context,
    List<TaskItem> tasks, {
    VoidCallback? onAdd,
  }) => Padding(
    padding: const EdgeInsets.all(7),
    child: tasks.isEmpty
        ? SizedBox(
            height: 95,
            child: InkWell(
              onTap: onAdd,
              child: Center(
                child: Text(
                  context.l10n.calendarFreeTime,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: context.appColors.mutedText,
                  ),
                ),
              ),
            ),
          )
        : Column(
            children: [
              for (final task in tasks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _CalendarTaskCard(
                    task: task,
                    project: projects[task.projectId],
                    actions: actions,
                  ),
                ),
            ],
          ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: context.appColors.surface,
          border: Border.all(color: context.appColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 300,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    settings.routineName.isEmpty
                        ? context.l10n.calendarRoutineDefault
                        : settings.routineName,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    context.l10n.calendarRoutineDescription,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.appColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            ShadButton.outline(
              onPressed: onConfigure,
              leading: const Icon(LucideIcons.slidersHorizontal, size: 15),
              child: Text(context.l10n.calendarEditRoutine),
            ),
          ],
        ),
      ),
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: math.max(1060, constraints.maxWidth),
              child: SingleChildScrollView(
                child: Table(
                  columnWidths: const {0: FixedColumnWidth(100)},
                  border: TableBorder.all(color: context.appColors.border),
                  defaultVerticalAlignment: TableCellVerticalAlignment.top,
                  children: [
                    TableRow(
                      children: [
                        const SizedBox(),
                        for (final value in days)
                          _CalendarDayHeader(
                            day: value.day.date,
                            today: now,
                            onSelect: () => actions.onSelectDay(value.day.date),
                          ),
                      ],
                    ),
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            context.l10n.allDay,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                        for (final value in days)
                          _CalendarDateDrop(
                            onDrop: (id) => actions.onMove(
                              id,
                              value.day.date,
                              allDay: true,
                            ),
                            child: _tasks(
                              context,
                              value.day.allDay,
                              onAdd: () => actions.onAdd(value.day.date),
                            ),
                          ),
                      ],
                    ),
                    for (var i = 0; i < settings.periods.length; i++)
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _calendarPeriodName(
                                    context,
                                    settings.periods[i],
                                    i,
                                  ),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${_calendarTime(context, settings.periods[i].startMinutes)}\n${_calendarTime(context, settings.periods[i].endMinutes)}',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: context.appColors.mutedText,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          for (final value in days)
                            _CalendarDateDrop(
                              onDrop: (id) => actions.onMove(
                                id,
                                value.day.date,
                                minutes: settings.periods[i].startMinutes,
                              ),
                              child: _tasks(
                                context,
                                value.periods[i],
                                onAdd: () => actions.onAdd(
                                  value.day.date,
                                  settings.periods[i].startMinutes,
                                ),
                              ),
                            ),
                        ],
                      ),
                    if (days.any((value) => value.outside.isNotEmpty))
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              context.l10n.calendarOutsideRoutine,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                          for (final value in days)
                            _tasks(context, value.outside),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
