part of 'calendar_screen.dart';

/// Compact calendars share a date and actions, never a seven-column task grid.
class _CalendarMobile extends ConsumerStatefulWidget {
  const _CalendarMobile({
    required this.state,
    required this.presentation,
    required this.day,
    required this.firstWeekday,
    required this.actions,
    required this.savingMode,
    required this.onMode,
    required this.onDate,
    required this.onOverview,
  });
  final CalendarState state;
  final CalendarPresentation presentation;
  final DateTime day;
  final int firstWeekday;
  final _CalendarActions actions;
  final bool savingMode;
  final Future<void> Function(CalendarMobileMode) onMode;
  final ValueChanged<DateTime> onDate;
  final VoidCallback onOverview;
  @override
  ConsumerState<_CalendarMobile> createState() => _CalendarMobileState();
}

class _CalendarMobileState extends ConsumerState<_CalendarMobile> {
  bool _monthExpanded = true;
  final _scroll = ScrollController();
  final _openPeriods = <int>{0};
  CalendarMobileMode get mode => widget.state.settings.mobileMode;
  CalendarDay get day => widget.presentation.days.firstWhere(
    (d) => _sameCalendarDay(d.date, widget.day),
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_CalendarMobile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.day != widget.day ||
        oldWidget.state.settings.mobileMode != mode) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  Widget _card(TaskItem task) => _CalendarTaskCard(
    key: ValueKey(task.id),
    task: task,
    project: widget.presentation.projectsById[task.projectId],
    actions: widget.actions,
    mobile: true,
  );

  Future<void> _unscheduled() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      sheetAnimationStyle: AnimationStyle(
        duration: AppMotion.duration(context, AppMotion.panel),
        reverseDuration: AppMotion.duration(context, AppMotion.panel),
      ),
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final state = ref.watch(calendarViewModelProvider);
          final data = ref
              .read(calendarViewModelProvider.notifier)
              .mobilePresentation(
                widget.day,
                firstWeekday: widget.firstWeekday,
              );
          return SizedBox(
            height: MediaQuery.sizeOf(context).height * .75,
            child: TaskSelectionRegion(
              floatingToolbar: false,
              visibleTasks: data.unscheduled.where((task) => task.canEdit),
              scopeKey: state.projectId,
              child: Column(
                children: [
                  ListTile(
                    title: Text(context.l10n.calendarUnscheduled),
                    trailing: IconButton(
                      tooltip: context.l10n.commonClose,
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(LucideIcons.x),
                    ),
                  ),
                  Expanded(
                    child: state.tasks.hasError
                        ? Center(
                            child: Text(context.l10n.taskActionFailedCount(1)),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: data.unscheduled.isEmpty
                                ? 1
                                : data.unscheduled.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) => data.unscheduled.isEmpty
                                ? Text(context.l10n.noTasksHere)
                                : _CalendarTaskCard(
                                    task: data.unscheduled[i],
                                    project:
                                        data.projectsById[data
                                            .unscheduled[i]
                                            .projectId],
                                    actions: widget.actions,
                                    mobile: true,
                                  ),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _configure() => unawaited(
    showDialog<void>(
      context: context,
      builder: (_) => _CalendarRoutineEditor(
        settings: widget.state.settings,
        save: ref.read(calendarViewModelProvider.notifier).saveRoutine,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final selection = TaskSelectionScope.maybeOf(context)!;
    final vm = ref.read(calendarViewModelProvider.notifier);
    final locale = Localizations.localeOf(context).toString();
    final failed =
        widget.state.tasks.hasError || widget.state.projects.hasError;
    final loading =
        widget.state.tasks.isLoading || widget.state.projects.isLoading;
    final periodLabel = mode == CalendarMobileMode.month && _monthExpanded
        ? MaterialLocalizations.of(context).formatMonthYear(widget.day)
        : intl.DateFormat.MMMEd(locale).format(widget.day);
    final footer = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          TextButton(
            onPressed: () => widget.onDate(widget.state.now),
            child: Text(l10n.today),
          ),
          Expanded(
            child: TextButton(
              onPressed: loading || failed
                  ? null
                  : () => widget.actions.onAdd(widget.day),
              child: Text(l10n.taskSchedule, textAlign: TextAlign.center),
            ),
          ),
          AppActionMenu(
            tooltip: l10n.taskMore,
            items: [
              ShadContextMenuItem(
                height: 44,
                onPressed: widget.onOverview,
                child: Text(l10n.calendarOverview),
              ),
              ShadContextMenuItem(
                height: 44,
                enabled: selection.visibleTasks.isNotEmpty,
                onPressed: () => selection.begin(),
                child: Text(l10n.taskSelect),
              ),
              ShadContextMenuItem(
                height: 44,
                onPressed: () => unawaited(_unscheduled()),
                child: Text(
                  '${l10n.calendarUnscheduled} · ${widget.presentation.unscheduled.length}',
                ),
              ),
              if (mode == CalendarMobileMode.routine)
                ShadContextMenuItem(
                  height: 44,
                  onPressed: _configure,
                  child: Text(l10n.calendarEditRoutine),
                ),
              Divider(height: 8, color: colors.border),
              ShadContextMenuItem(
                height: 44,
                leading: Icon(
                  widget.state.projectId == null ? LucideIcons.check : null,
                  size: 16,
                ),
                onPressed: () => vm.setProject(null),
                child: Semantics(
                  selected: widget.state.projectId == null,
                  child: Text(l10n.calendarAllProjects),
                ),
              ),
              for (final project in widget.presentation.projectsById.values)
                ShadContextMenuItem(
                  height: 44,
                  leading: Icon(
                    widget.state.projectId == project.id
                        ? LucideIcons.check
                        : null,
                    size: 16,
                  ),
                  onPressed: () => vm.setProject(project.id),
                  child: Semantics(
                    selected: widget.state.projectId == project.id,
                    child: Text(project.displayName(l10n)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceTint,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        for (final value in CalendarMobileMode.values)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: Semantics(
                                selected: mode == value,
                                child: TextButton(
                                  onPressed:
                                      widget.savingMode ||
                                          !widget.state.settingsLoaded
                                      ? null
                                      : () => unawaited(widget.onMode(value)),
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size(44, 44),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    foregroundColor: mode == value
                                        ? colors.primaryText
                                        : colors.secondaryText,
                                    backgroundColor: mode == value
                                        ? colors.surface
                                        : Colors.transparent,
                                    textStyle: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          fontWeight: mode == value
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                        ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                  child: Text(switch (value) {
                                    CalendarMobileMode.day => l10n.calendarDay,
                                    CalendarMobileMode.month =>
                                      l10n.calendarMonth,
                                    CalendarMobileMode.routine =>
                                      l10n.calendarRhythm,
                                  }, textAlign: TextAlign.center),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (widget.state.settingsError != null)
                SliverToBoxAdapter(
                  child: TextButton(
                    onPressed: vm.retry,
                    child: Text(l10n.calendarSaveFailed),
                  ),
                ),
              if (failed)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l10n.taskActionFailedCount(1)),
                        TextButton(
                          onPressed: vm.retry,
                          child: Text(l10n.commonRetry),
                        ),
                      ],
                    ),
                  ),
                )
              else if (loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: l10n.calendarPreviousPeriod,
                          onPressed: () => _shift(-1),
                          icon: const Icon(LucideIcons.chevronLeft, size: 18),
                        ),
                        Expanded(
                          child: AppDateTimePicker(
                            builder: (context, picker) => TextButton(
                              focusNode: picker.focusNode,
                              onPressed: () async {
                                final date = await picker.pickDate(
                                  initialDate: widget.day,
                                  firstDate: DateTime(1900),
                                  lastDate: DateTime(2200),
                                );
                                if (date != null && mounted) {
                                  widget.onDate(date);
                                }
                              },
                              child: Text(
                                periodLabel,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: l10n.calendarNextPeriod,
                          onPressed: () => _shift(1),
                          icon: const Icon(LucideIcons.chevronRight, size: 18),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: _dates()),
                if (mode == CalendarMobileMode.month)
                  SliverToBoxAdapter(
                    child: TextButton.icon(
                      onPressed: () =>
                          setState(() => _monthExpanded = !_monthExpanded),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.secondaryText,
                        minimumSize: const Size(44, 44),
                      ),
                      icon: Icon(
                        _monthExpanded
                            ? LucideIcons.chevronUp
                            : LucideIcons.chevronDown,
                        size: 16,
                      ),
                      label: Text(
                        _monthExpanded
                            ? l10n.calendarCollapseMonth
                            : l10n.calendarExpandMonth,
                      ),
                    ),
                  ),
                if (mode == CalendarMobileMode.month)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Text(
                        intl.DateFormat.MMMMEEEEd(locale).format(widget.day),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ),
                if (mode == CalendarMobileMode.routine)
                  ..._routine()
                else if (mode == CalendarMobileMode.month)
                  ..._taskList(day.tasks)
                else
                  ..._timeline(),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],
            ],
          ),
        ),
        if (!selection.active)
          MediaQuery.sizeOf(context).width < 820
              ? BottomPanelSurface(child: footer)
              : DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    border: Border(top: BorderSide(color: colors.border)),
                  ),
                  child: footer,
                ),
      ],
    );
  }

  void _shift(int direction) {
    final d = widget.day;
    widget.onDate(
      mode == CalendarMobileMode.month && _monthExpanded
          ? DateTime(d.year, d.month + direction, 1)
          : DateTime(d.year, d.month, d.day + direction),
    );
  }

  Widget _dates() {
    final month = mode == CalendarMobileMode.month && _monthExpanded;
    final chosen = widget.day;
    final start = DateTime(
      chosen.year,
      chosen.month,
      chosen.day - (chosen.weekday - widget.firstWeekday + 7) % 7,
    );
    final dates = month
        ? widget.presentation.days.map((d) => d.date).toList()
        : List.generate(
            7,
            (i) => DateTime(start.year, start.month, start.day + i),
          );
    final colors = context.appColors;
    final material = MaterialLocalizations.of(context);
    // Only date cells are a seven-column grid; task content stays full width.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Text(
                    material.narrowWeekdays[(widget.firstWeekday + i) % 7],
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.secondaryText,
                    ),
                  ),
                ),
            ],
          ),
          for (var row = 0; row < dates.length ~/ 7; row++)
            Row(
              children: [
                for (final date in dates.skip(row * 7).take(7))
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final active = _sameCalendarDay(date, chosen);
                        final today = _sameCalendarDay(date, widget.state.now);
                        final count = month
                            ? widget.presentation.days
                                  .firstWhere((d) => d.date == date)
                                  .tasks
                                  .length
                            : 0;
                        return Semantics(
                          selected: active,
                          label:
                              '${material.formatFullDate(date)}${count > 0 ? ', ${context.l10n.kanbanTasksCount(count)}' : ''}',
                          child: TextButton(
                            onPressed: () => widget.onDate(date),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              minimumSize: const Size(44, 48),
                              foregroundColor: active
                                  ? colors.onAccent
                                  : today
                                  ? colors.accent
                                  : month && date.month != chosen.month
                                  ? colors.mutedText
                                  : colors.primaryText,
                            ),
                            child: ExcludeSemantics(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    constraints: const BoxConstraints(
                                      minWidth: 30,
                                      minHeight: 30,
                                    ),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: active ? colors.accentFill : null,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text('${date.day}'),
                                  ),
                                  if (month)
                                    SizedBox(
                                      height: 6,
                                      child: Center(
                                        child: Container(
                                          width: 3,
                                          height: 3,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: count == 0
                                                ? Colors.transparent
                                                : colors.secondaryText,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  List<Widget> _taskList(List<TaskItem> tasks) => tasks.isEmpty
      ? [SliverToBoxAdapter(child: _empty())]
      : [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.separated(
              itemCount: tasks.length,
              itemBuilder: (_, i) => _card(tasks[i]),
              separatorBuilder: (_, _) => const SizedBox(height: 8),
            ),
          ),
        ];

  Widget _empty() => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        Text(
          context.l10n.calendarFreeTime,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: context.appColors.secondaryText,
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => widget.actions.onAdd(widget.day),
          child: Text(context.l10n.taskSchedule),
        ),
      ],
    ),
  );

  List<Widget> _timeline() {
    // Time labels and free windows carry scale; overlapping tasks stay readable.
    final events = day.events;
    var end = 0;
    final rows = <Widget>[];
    if (day.allDay.isNotEmpty) {
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            context.l10n.allDay,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      );
      for (final task in day.allDay) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _card(task),
          ),
        );
      }
    }
    for (final event in events) {
      if (end > 0 && event.startMinutes > end) {
        final start = end;
        rows.add(
          TextButton(
            onPressed: () => widget.actions.onAdd(widget.day, start),
            style: TextButton.styleFrom(
              foregroundColor: context.appColors.secondaryText,
              minimumSize: const Size(44, 48),
            ),
            child: Text(
              '${_calendarTime(context, start)}–${_calendarTime(context, event.startMinutes)} · ${context.l10n.calendarFreeTime}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        );
      }
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 56,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _calendarTime(context, event.startMinutes),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: context.appColors.secondaryText,
                    ),
                  ),
                ),
              ),
              Expanded(child: _card(event.task)),
            ],
          ),
        ),
      );
      end = math.max(end, event.endMinutes);
    }
    if (rows.isEmpty) return [SliverToBoxAdapter(child: _empty())];
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        sliver: SliverList.list(children: rows),
      ),
    ];
  }

  List<Widget> _routine() {
    final settings = widget.state.settings;
    final grouped = groupCalendarRoutineDays(
      widget.presentation,
      settings,
    ).single;
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                settings.routineName.isEmpty
                    ? context.l10n.calendarRoutineDefault
                    : settings.routineName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: context.l10n.calendarEditRoutine,
              onPressed: _configure,
              icon: const Icon(LucideIcons.slidersHorizontal, size: 20),
            ),
          ],
        ),
      ),
      if (day.allDay.isNotEmpty) ...[
        Text(
          context.l10n.allDay,
          style: Theme.of(context).textTheme.labelMedium,
        ),
        for (final task in day.allDay)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _card(task),
          ),
      ],
      for (var i = 0; i < settings.periods.length; i++)
        _period(i, grouped.periods[i]),
      if (grouped.outside.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            context.l10n.calendarOutsideRoutine,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        for (final task in grouped.outside)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _card(task),
          ),
      ],
    ];
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.list(children: children),
      ),
    ];
  }

  Widget _period(int index, List<TaskItem> tasks) {
    final period = widget.state.settings.periods[index];
    final open = _openPeriods.contains(index);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: context.appColors.border),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(_calendarPeriodName(context, period, index)),
          subtitle: Text(
            '${_calendarTime(context, period.startMinutes)}–${_calendarTime(context, period.endMinutes)} · ${context.l10n.kanbanTasksCount(tasks.length)}',
          ),
          trailing: Icon(
            open ? LucideIcons.chevronUp : LucideIcons.chevronDown,
            size: 18,
          ),
          onTap: () => setState(
            () => open ? _openPeriods.remove(index) : _openPeriods.add(index),
          ),
        ),
        if (open) ...[
          for (final task in tasks)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _card(task),
            ),
          if (tasks.isEmpty)
            Text(
              context.l10n.calendarFreeTime,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.appColors.secondaryText,
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () =>
                  widget.actions.onAdd(widget.day, period.startMinutes),
              child: Text(context.l10n.taskSchedule),
            ),
          ),
        ],
      ],
    );
  }
}

/// A single confirmation applies both date and time; cancelling changes nothing.
Future<({DateTime day, int? minutes})?> _pickCalendarMobileTime(
  BuildContext context, {
  required DateTime initialDate,
  required int? initialMinutes,
  bool allowAllDay = true,
}) {
  var date = DateUtils.dateOnly(initialDate);
  var minute = initialMinutes ?? 9 * 60;
  var allDay = allowAllDay && initialMinutes == null;
  return showModalBottomSheet<({DateTime day, int? minutes})>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    sheetAnimationStyle: AnimationStyle(
      duration: AppMotion.duration(context, AppMotion.panel),
      reverseDuration: AppMotion.duration(context, AppMotion.panel),
    ),
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, update) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: AppDateTimePicker(
              builder: (context, picker) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    allowAllDay
                        ? context.l10n.taskSchedule
                        : context.l10n.calendarResize,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    focusNode: picker.focusNode,
                    icon: const Icon(LucideIcons.calendar, size: 18),
                    onPressed: () async {
                      final picked = await picker.pickDate(
                        initialDate: date,
                        firstDate: DateTime(1900),
                        lastDate: DateTime(2200),
                      );
                      if (picked != null && context.mounted) {
                        update(() => date = picked);
                      }
                    },
                    label: Text(
                      MaterialLocalizations.of(context).formatFullDate(date),
                    ),
                  ),
                  if (allowAllDay)
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.l10n.allDay),
                      value: allDay,
                      onChanged: (value) => update(() => allDay = value),
                    ),
                  if (!allDay)
                    OutlinedButton.icon(
                      icon: const Icon(LucideIcons.clock, size: 18),
                      onPressed: () async {
                        final picked = await picker.pickTime(
                          initialTime: TimeOfDay(
                            hour: minute ~/ 60,
                            minute: minute % 60,
                          ),
                        );
                        if (picked != null && context.mounted) {
                          update(
                            () => minute = picked.hour * 60 + picked.minute,
                          );
                        }
                      },
                      label: Text(_calendarTime(context, minute)),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.pop(sheetContext, (
                      day: date,
                      minutes: allDay ? null : minute,
                    )),
                    child: Text(context.l10n.commonSave),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: Text(context.l10n.commonCancel),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
