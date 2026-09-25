part of 'calendar_screen.dart';

const _calendarHourHeight = 80.0;
const _calendarTimeWidth = 54.0;

class _CalendarTimeGrid extends StatefulWidget {
  const _CalendarTimeGrid({
    super.key,
    required this.days,
    required this.projects,
    required this.now,
    required this.actions,
  });
  final List<CalendarDay> days;
  final Map<String, ProjectItem> projects;
  final DateTime now;
  final _CalendarActions actions;
  @override
  State<_CalendarTimeGrid> createState() => _CalendarTimeGridState();
}

class _CalendarTimeGridState extends State<_CalendarTimeGrid> {
  late final ScrollController _vertical = ScrollController(
    initialScrollOffset:
        (widget.now.hour - 1).clamp(0, 21) * _calendarHourHeight,
  );
  final _horizontal = ScrollController();
  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final count = widget.days.length;
      final width = math.max(
        constraints.maxWidth,
        _calendarTimeWidth + count * (count == 1 ? 250.0 : 125.0),
      );
      final column = (width - _calendarTimeWidth) / count;
      final colors = context.appColors;
      final anyAllDay = widget.days.any((day) => day.allDay.isNotEmpty);
      return DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Scrollbar(
          controller: _horizontal,
          child: SingleChildScrollView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(width: _calendarTimeWidth),
                      for (final day in widget.days)
                        SizedBox(
                          width: column,
                          child: _CalendarDayHeader(
                            day: day.date,
                            today: widget.now,
                            onSelect: () =>
                                widget.actions.onSelectDay(day.date),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(
                    height: anyAllDay ? 104 : 44,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: _calendarTimeWidth,
                          child: Center(
                            child: Text(
                              context.l10n.allDay,
                              style: Theme.of(context).textTheme.labelSmall,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        for (final day in widget.days)
                          SizedBox(
                            width: column,
                            child: _CalendarDateDrop(
                              onDrop: (id) => widget.actions.onMove(
                                id,
                                day.date,
                                allDay: true,
                              ),
                              child: day.allDay.isEmpty
                                  ? _CalendarAddTarget(
                                      date: day.date,
                                      onAdd: () =>
                                          widget.actions.onAdd(day.date),
                                    )
                                  : ListView.separated(
                                      padding: const EdgeInsets.all(4),
                                      itemCount: day.allDay.length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(height: 4),
                                      itemBuilder: (_, i) => _CalendarTaskCard(
                                        task: day.allDay[i],
                                        project: widget
                                            .projects[day.allDay[i].projectId],
                                        actions: widget.actions,
                                        compact: true,
                                      ),
                                    ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: colors.border),
                  Expanded(
                    child: Scrollbar(
                      controller: _vertical,
                      child: SingleChildScrollView(
                        controller: _vertical,
                        child: SizedBox(
                          height: 24 * _calendarHourHeight,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                width: _calendarTimeWidth,
                                child: Stack(
                                  children: [
                                    for (var hour = 0; hour < 24; hour++)
                                      Positioned(
                                        top: hour * _calendarHourHeight + 4,
                                        left: 2,
                                        right: 6,
                                        child: Text(
                                          _calendarTime(context, hour * 60),
                                          textAlign: TextAlign.end,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: colors.mutedText,
                                                fontSize: 10,
                                              ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              for (final day in widget.days)
                                SizedBox(
                                  width: column,
                                  child: _CalendarTimeColumn(
                                    day: day,
                                    projects: widget.projects,
                                    now: widget.now,
                                    actions: widget.actions,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _CalendarDayHeader extends StatelessWidget {
  const _CalendarDayHeader({
    required this.day,
    required this.today,
    required this.onSelect,
  });
  final DateTime day;
  final DateTime today;
  final VoidCallback onSelect;
  @override
  Widget build(BuildContext context) {
    final active = _sameCalendarDay(day, today);
    final colors = context.appColors;
    return InkWell(
      onTap: onSelect,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              intl.DateFormat.E(
                Localizations.localeOf(context).toString(),
              ).format(day),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: colors.secondaryText),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: active ? colors.accentFill : null,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${day.day}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: active ? colors.onAccent : colors.primaryText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarDateDrop extends StatelessWidget {
  const _CalendarDateDrop({required this.onDrop, required this.child});
  final Future<void> Function(String) onDrop;
  final Widget child;
  @override
  Widget build(BuildContext context) => DragTarget<String>(
    onAcceptWithDetails: (details) => unawaited(onDrop(details.data)),
    builder: (context, candidate, _) => ColoredBox(
      color: candidate.isEmpty
          ? Colors.transparent
          : context.appColors.accentTint,
      child: child,
    ),
  );
}

class _CalendarTimeColumn extends StatefulWidget {
  const _CalendarTimeColumn({
    required this.day,
    required this.projects,
    required this.now,
    required this.actions,
  });
  final CalendarDay day;
  final Map<String, ProjectItem> projects;
  final DateTime now;
  final _CalendarActions actions;
  @override
  State<_CalendarTimeColumn> createState() => _CalendarTimeColumnState();
}

class _CalendarTimeColumnState extends State<_CalendarTimeColumn> {
  final _boxKey = GlobalKey();
  int? _hoverMinute;

  int _minute(Offset global) {
    final box = _boxKey.currentContext!.findRenderObject()! as RenderBox;
    return calendarDropMinutes(
      box.globalToLocal(global).dy,
      _calendarHourHeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final today = _sameCalendarDay(widget.day.date, widget.now);
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          !widget.actions.pending.contains(details.data),
      onMove: (details) {
        final next = _minute(details.offset);
        if (next != _hoverMinute) setState(() => _hoverMinute = next);
      },
      onLeave: (_) => setState(() => _hoverMinute = null),
      onAcceptWithDetails: (details) {
        final minute = _minute(details.offset);
        setState(() => _hoverMinute = null);
        unawaited(
          widget.actions.onMove(details.data, widget.day.date, minutes: minute),
        );
      },
      builder: (context, candidate, _) => LayoutBuilder(
        builder: (context, constraints) => Container(
          key: _boxKey,
          decoration: BoxDecoration(
            color: today
                ? colors.accentTint.withValues(alpha: .15)
                : colors.surface,
            border: BorderDirectional(start: BorderSide(color: colors.border)),
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              for (var hour = 0; hour < 24; hour++)
                Positioned(
                  top: hour * _calendarHourHeight,
                  left: 0,
                  right: 0,
                  height: _calendarHourHeight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onDoubleTapDown: (details) => widget.actions.onAdd(
                      widget.day.date,
                      calendarDropMinutes(
                        hour * _calendarHourHeight + details.localPosition.dy,
                        _calendarHourHeight,
                      ),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: colors.border)),
                      ),
                    ),
                  ),
                ),
              if (_hoverMinute != null)
                Positioned(
                  top: _hoverMinute! / 60 * _calendarHourHeight,
                  left: 2,
                  right: 2,
                  height: _calendarHourHeight / 2,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        color: colors.accentTint,
                        border: Border.all(color: colors.accent),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Text(
                        _calendarTime(context, _hoverMinute!),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ),
                ),
              for (final event in widget.day.events)
                PositionedDirectional(
                  top: event.startMinutes / 60 * _calendarHourHeight,
                  start:
                      event.lane / event.laneCount * constraints.maxWidth + 3,
                  width: math.max(
                    1,
                    constraints.maxWidth / event.laneCount - 6,
                  ),
                  height: math.max(
                    24,
                    (event.endMinutes - event.startMinutes) /
                            60 *
                            _calendarHourHeight -
                        3,
                  ),
                  child: _CalendarResizableEvent(
                    key: ValueKey((event.task.id, event.task.updatedAt)),
                    event: event,
                    date: widget.day.date,
                    project: widget.projects[event.task.projectId],
                    actions: widget.actions,
                  ),
                ),
              if (today)
                Positioned(
                  top:
                      (widget.now.hour * 60 + widget.now.minute) /
                      60 *
                      _calendarHourHeight,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Container(height: 1, color: colors.accent),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarResizableEvent extends StatefulWidget {
  const _CalendarResizableEvent({
    super.key,
    required this.event,
    required this.date,
    required this.project,
    required this.actions,
  });
  final CalendarEvent event;
  final DateTime date;
  final ProjectItem? project;
  final _CalendarActions actions;
  @override
  State<_CalendarResizableEvent> createState() =>
      _CalendarResizableEventState();
}

class _CalendarResizableEventState extends State<_CalendarResizableEvent> {
  double? _delta;
  bool _resizeFocused = false;
  int get _end =>
      ((widget.event.endMinutes + (_delta ?? 0) / _calendarHourHeight * 60) /
              15)
          .round()
          .clamp((widget.event.startMinutes ~/ 15) + 1, 96) *
      15;
  Future<void> _resize(int end) => widget.actions.onResize(
    widget.event.task.id,
    DateTime(
      widget.date.year,
      widget.date.month,
      widget.date.day,
      end ~/ 60,
      end % 60,
    ),
  );
  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final canResize =
        event.task.canEdit &&
        !(TaskSelectionScope.maybeOf(context)?.active ?? false) &&
        !event.continuesAfter &&
        !widget.actions.pending.contains(event.task.id);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: _CalendarTaskCard(
            task: event.task,
            project: widget.project,
            actions: widget.actions,
            fill: true,
          ),
        ),
        if (_delta != null)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: math.max(
              24,
              (_end - event.startMinutes) / 60 * _calendarHourHeight - 3,
            ),
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: context.appColors.accentTint.withValues(alpha: .5),
                  border: Border.all(color: context.appColors.accent),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        if (canResize)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 12,
            child: Focus(
              onFocusChange: (value) => setState(() => _resizeFocused = value),
              onKeyEvent: (_, eventKey) {
                if (eventKey is! KeyDownEvent) return KeyEventResult.ignored;
                if (eventKey.logicalKey == LogicalKeyboardKey.arrowDown) {
                  unawaited(_resize(math.min(1440, event.endMinutes + 15)));
                  return KeyEventResult.handled;
                }
                if (eventKey.logicalKey == LogicalKeyboardKey.arrowUp &&
                    event.endMinutes - event.startMinutes > 15) {
                  unawaited(_resize(event.endMinutes - 15));
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Semantics(
                label: context.l10n.calendarResize,
                onIncrease: () =>
                    unawaited(_resize(math.min(1440, event.endMinutes + 15))),
                onDecrease: event.endMinutes - event.startMinutes > 15
                    ? () => unawaited(_resize(event.endMinutes - 15))
                    : null,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart: (_) => setState(() => _delta = 0),
                    onVerticalDragUpdate: (details) => setState(
                      () => _delta = (_delta ?? 0) + details.delta.dy,
                    ),
                    onVerticalDragCancel: () => setState(() => _delta = null),
                    onVerticalDragEnd: (_) {
                      final end = _end;
                      setState(() => _delta = null);
                      unawaited(_resize(end));
                    },
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: 18,
                        height: 2,
                        margin: const EdgeInsets.only(bottom: 3),
                        color: _resizeFocused
                            ? context.appColors.accentFill
                            : context.appColors.mutedText.withValues(alpha: .5),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (_delta != null)
          PositionedDirectional(
            start: 0,
            top: 0,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.all(5),
                color: context.appColors.accentFill,
                child: Text(
                  _calendarTime(context, _end),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: context.appColors.onAccent,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
