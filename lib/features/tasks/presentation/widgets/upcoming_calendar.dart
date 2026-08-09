import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/app_l10n.dart';
import '../../../../app/theme/app_theme.dart';

class UpcomingCalendar extends StatefulWidget {
  const UpcomingCalendar({
    super.key,
    required this.today,
    required this.selectedDate,
    required this.scheduledCounts,
    required this.loading,
    required this.onDateSelected,
    required this.onTodaySelected,
    required this.onClearSelection,
  });

  final DateTime today;
  final DateTime? selectedDate;
  final Map<DateTime, int> scheduledCounts;
  final bool loading;
  final ValueChanged<DateTime> onDateSelected;
  final VoidCallback onTodaySelected;
  final VoidCallback onClearSelection;

  @override
  State<UpcomingCalendar> createState() => _UpcomingCalendarState();
}

class _UpcomingCalendarState extends State<UpcomingCalendar> {
  final MenuController _menuController = MenuController();
  final FocusNode _monthFocusNode = FocusNode(
    debugLabel: 'Upcoming calendar month opener',
  );
  final FocusNode _railFocusNode = FocusNode(
    debugLabel: 'Upcoming calendar day rail',
  );
  final ScrollController _railScrollController = ScrollController();

  DateTime? _pageStart;
  DateTime? _rovingDate;
  int? _firstDayOfWeekIndex;
  int _pageSize = 7;
  double _horizontalDragDistance = 0;

  @override
  void dispose() {
    _monthFocusNode.dispose();
    _railFocusNode.dispose();
    _railScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final firstDayOfWeekIndex = MaterialLocalizations.of(
      context,
    ).firstDayOfWeekIndex;
    if (_pageStart == null || _firstDayOfWeekIndex != firstDayOfWeekIndex) {
      _firstDayOfWeekIndex = firstDayOfWeekIndex;
      final anchor = _localDate(widget.selectedDate ?? widget.today);
      _pageStart = _startOfWeek(anchor, firstDayOfWeekIndex);
      _rovingDate = anchor;
    }
  }

  @override
  void didUpdateWidget(UpcomingCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectionChanged = !_sameDate(
      oldWidget.selectedDate,
      widget.selectedDate,
    );
    final todayChanged = !_sameDate(oldWidget.today, widget.today);
    if (_firstDayOfWeekIndex != null &&
        (selectionChanged || (widget.selectedDate == null && todayChanged))) {
      final anchor = _localDate(widget.selectedDate ?? widget.today);
      _pageStart = _startOfWeek(anchor, _firstDayOfWeekIndex!);
      _rovingDate = anchor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = _localDate(widget.today);
    final selectedDate = widget.selectedDate == null
        ? null
        : _localDate(widget.selectedDate!);
    final scheduledCounts = _normalizedCounts(widget.scheduledCounts);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 760;
        final pageSize = isWide ? 14 : 7;
        var pageStart = _pageStart!;
        if (pageSize != _pageSize &&
            !_dateIsInPage(_rovingDate!, pageStart, pageSize)) {
          pageStart = _startOfWeek(_rovingDate!, _firstDayOfWeekIndex!);
          _pageStart = pageStart;
        }
        _pageSize = pageSize;
        final minimumRailWidth = pageSize * 48.0;
        final railWidth = constraints.maxWidth < minimumRailWidth
            ? minimumRailWidth
            : constraints.maxWidth;
        final dates = List.generate(
          pageSize,
          (index) => _addCalendarDays(pageStart, index),
        );

        return Card(
          key: const ValueKey('upcoming-calendar'),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(context, isWide: isWide, pageSize: pageSize),
              const Divider(),
              Focus(
                key: const ValueKey('upcoming-calendar-focus'),
                focusNode: _railFocusNode,
                onKeyEvent: _handleRailKey,
                child: AnimatedBuilder(
                  animation: _railFocusNode,
                  builder: (context, child) {
                    return Listener(
                      key: const ValueKey('upcoming-calendar-days'),
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: isWide
                          ? null
                          : (_) => _horizontalDragDistance = 0,
                      onPointerMove: isWide
                          ? null
                          : (details) {
                              _horizontalDragDistance += details.delta.dx;
                            },
                      onPointerUp: isWide
                          ? null
                          : (_) => _finishSwipe(Directionality.of(context)),
                      child: SingleChildScrollView(
                        controller: _railScrollController,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: railWidth,
                          child: Row(
                            children: [
                              for (final date in dates)
                                Expanded(
                                  child: _DayCell(
                                    date: date,
                                    today: today,
                                    selected: selectedDate == date,
                                    count: scheduledCounts[date] ?? 0,
                                    roving: _rovingDate == date,
                                    railFocused: _railFocusNode.hasFocus,
                                    onActivate: () => _activateDate(date),
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
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context, {
    required bool isWide,
    required int pageSize,
  }) {
    final materialL10n = MaterialLocalizations.of(context);
    final colors = context.appColors;
    final direction = Directionality.of(context);
    final pageEnd = _addCalendarDays(_pageStart!, pageSize - 1);
    final firstMonth = materialL10n.formatMonthYear(_pageStart!);
    final lastMonth = materialL10n.formatMonthYear(pageEnd);
    final monthLabel = firstMonth == lastMonth
        ? firstMonth
        : '$firstMonth – $lastMonth';
    final monthButton = Tooltip(
      message: context.l10n.upcomingOpenDatePicker,
      child: TextButton.icon(
        key: const ValueKey('upcoming-calendar-month'),
        focusNode: _monthFocusNode,
        onPressed: isWide
            ? () {
                if (_menuController.isOpen) {
                  _menuController.close();
                } else {
                  _menuController.open();
                }
              }
            : _showMonthSheet,
        icon: const Icon(Icons.calendar_month_outlined, size: 20),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(monthLabel, maxLines: 1),
        ),
        style: TextButton.styleFrom(
          foregroundColor: colors.primaryText,
          minimumSize: const Size(48, 48),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 6),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('upcoming-calendar-previous'),
            tooltip: context.l10n.upcomingPreviousPeriod,
            onPressed: () => _movePage(-pageSize),
            icon: Icon(
              direction == TextDirection.rtl
                  ? Icons.chevron_right
                  : Icons.chevron_left,
            ),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
          SizedBox(
            width: 18,
            height: 18,
            child: widget.loading
                ? const SizedBox(
                    key: ValueKey('upcoming-calendar-loading'),
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
          Expanded(
            child: isWide
                ? MenuAnchor(
                    controller: _menuController,
                    childFocusNode: _monthFocusNode,
                    onClose: _restoreMonthFocus,
                    menuChildren: [
                      SizedBox(
                        key: const ValueKey('upcoming-calendar-month-popover'),
                        width: 360,
                        height: 400,
                        child: PrimaryScrollController.none(
                          child: _buildDatePicker(_menuController.close),
                        ),
                      ),
                    ],
                    builder: (context, controller, child) =>
                        Center(child: monthButton),
                  )
                : Center(child: monthButton),
          ),
          TextButton(
            key: const ValueKey('upcoming-calendar-today'),
            onPressed: _selectToday,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(context.l10n.today),
            ),
          ),
          IconButton(
            key: const ValueKey('upcoming-calendar-next'),
            tooltip: context.l10n.upcomingNextPeriod,
            onPressed: () => _movePage(pageSize),
            icon: Icon(
              direction == TextDirection.rtl
                  ? Icons.chevron_left
                  : Icons.chevron_right,
            ),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
        ],
      ),
    );
  }

  void _movePage(int days) {
    setState(() {
      _pageStart = _addCalendarDays(_pageStart!, days);
      _rovingDate = _addCalendarDays(_rovingDate!, days);
    });
    _resetRailScroll();
  }

  void _finishSwipe(TextDirection textDirection) {
    final distance = _horizontalDragDistance;
    if (distance.abs() < 48) {
      return;
    }
    final movesForward = textDirection == TextDirection.rtl
        ? distance > 0
        : distance < 0;
    _movePage(movesForward ? _pageSize : -_pageSize);
  }

  void _resetRailScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _railScrollController.hasClients) {
        _railScrollController.jumpTo(
          _railScrollController.position.minScrollExtent,
        );
      }
    });
  }

  KeyEventResult _handleRailKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _moveRovingDate(isRtl ? 1 : -1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _moveRovingDate(isRtl ? -1 : 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _moveRovingDate(-DateTime.daysPerWeek);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _moveRovingDate(DateTime.daysPerWeek);
    } else if (key == LogicalKeyboardKey.home) {
      setState(() => _rovingDate = _pageStart);
    } else if (key == LogicalKeyboardKey.end) {
      setState(() {
        _rovingDate = _addCalendarDays(_pageStart!, _pageSize - 1);
      });
    } else if (key == LogicalKeyboardKey.pageUp) {
      _movePage(-_pageSize);
    } else if (key == LogicalKeyboardKey.pageDown) {
      _movePage(_pageSize);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space) {
      _activateDate(_rovingDate!);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _moveRovingDate(int days) {
    setState(() {
      final next = _addCalendarDays(_rovingDate!, days);
      final pageEnd = _addCalendarDays(_pageStart!, _pageSize);
      if (next.isBefore(_pageStart!)) {
        _pageStart = _addCalendarDays(_pageStart!, -_pageSize);
      } else if (!next.isBefore(pageEnd)) {
        _pageStart = _addCalendarDays(_pageStart!, _pageSize);
      }
      _rovingDate = next;
    });
    _resetRailScroll();
  }

  void _activateDate(DateTime value, {bool reanchor = false}) {
    final date = _localDate(value);
    final today = _localDate(widget.today);
    if (date == today) {
      _resetToTodayPage();
      if (_sameDate(widget.selectedDate, date)) {
        widget.onClearSelection();
      } else {
        widget.onDateSelected(date);
      }
      return;
    }

    setState(() {
      _rovingDate = date;
      if (reanchor) {
        _pageStart = _startOfWeek(date, _firstDayOfWeekIndex!);
      }
    });
    widget.onDateSelected(date);
  }

  void _selectToday() {
    _resetToTodayPage();
    widget.onTodaySelected();
  }

  void _resetToTodayPage() {
    final today = _localDate(widget.today);
    setState(() {
      _pageStart = _startOfWeek(today, _firstDayOfWeekIndex!);
      _rovingDate = today;
    });
  }

  CalendarDatePicker _buildDatePicker(VoidCallback close) {
    final today = _localDate(widget.today);
    final firstDate = DateTime(today.year - 100, 1, 1);
    final lastDate = DateTime(today.year + 100, 12, 31);
    final candidate = _localDate(widget.selectedDate ?? _rovingDate ?? today);
    final initialDate =
        candidate.isBefore(firstDate) || candidate.isAfter(lastDate)
        ? today
        : candidate;
    return CalendarDatePicker(
      initialDate: initialDate,
      currentDate: today,
      firstDate: firstDate,
      lastDate: lastDate,
      onDateChanged: (date) {
        _activateDate(date, reanchor: true);
        close();
      },
    );
  }

  Future<void> _showMonthSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            key: const ValueKey('upcoming-calendar-month-sheet'),
            height: 420,
            child: PrimaryScrollController.none(
              child: _buildDatePicker(() => Navigator.of(sheetContext).pop()),
            ),
          ),
        );
      },
    );
    _restoreMonthFocus();
  }

  void _restoreMonthFocus() {
    if (!mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _monthFocusNode.requestFocus();
      }
    });
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.today,
    required this.selected,
    required this.count,
    required this.roving,
    required this.railFocused,
    required this.onActivate,
  });

  final DateTime date;
  final DateTime today;
  final bool selected;
  final int count;
  final bool roving;
  final bool railFocused;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final materialL10n = MaterialLocalizations.of(context);
    final colors = context.appColors;
    final key = _dateKey(date);
    final isToday = date == today;
    final isPast = date.isBefore(today);
    const enabled = true;
    final visibleCount = count <= 0 ? 0 : (count >= 3 ? 3 : count);
    final label = <String>[
      materialL10n.formatFullDate(date),
      if (isToday) context.l10n.today,
      context.l10n.upcomingTaskCount(count),
    ].join(', ');
    final textColor = isPast ? colors.mutedText : colors.primaryText;
    final weekdayColor = isPast ? colors.mutedText : colors.secondaryText;
    final dotColor = isPast
        ? colors.mutedText
        : switch (visibleCount) {
            1 => colors.mutedText,
            2 => colors.secondaryText,
            _ => colors.accent,
          };
    final dotSize = switch (visibleCount) {
      1 => 5.0,
      2 => 6.0,
      _ => 7.0,
    };

    return Semantics(
      key: ValueKey('upcoming-calendar-day-$key'),
      label: label,
      button: true,
      enabled: enabled,
      selected: selected,
      focusable: roving,
      focused: roving && railFocused,
      onTap: onActivate,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onActivate,
        child: SizedBox(
          height: 88,
          child: Container(
            key: selected
                ? ValueKey('upcoming-calendar-selected-marker-$key')
                : null,
            margin: const EdgeInsets.all(3),
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? colors.accentTint : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? colors.accent
                    : roving && railFocused
                    ? colors.info
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 16,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _weekdayLabel(context, date.weekday),
                      style: Theme.of(
                        context,
                      ).textTheme.labelMedium?.copyWith(color: weekdayColor),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  key: isToday
                      ? ValueKey('upcoming-calendar-today-marker-$key')
                      : null,
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: isToday
                        ? Border.all(color: colors.accent, width: 1.5)
                        : null,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(
                        materialL10n.formatDecimal(date.day),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: isPast
                                  ? colors.mutedText
                                  : selected
                                  ? colors.accent
                                  : textColor,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  height: 12,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var index = 0; index < visibleCount; index++) ...[
                        if (index > 0) const SizedBox(width: 3),
                        DecoratedBox(
                          key: ValueKey('upcoming-calendar-dot-$key-$index'),
                          decoration: BoxDecoration(
                            color: dotColor,
                            shape: BoxShape.circle,
                          ),
                          child: SizedBox.square(dimension: dotSize),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

DateTime _localDate(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

DateTime _addCalendarDays(DateTime value, int days) {
  return DateTime(value.year, value.month, value.day + days);
}

bool _dateIsInPage(DateTime date, DateTime pageStart, int pageSize) {
  return !date.isBefore(pageStart) &&
      date.isBefore(_addCalendarDays(pageStart, pageSize));
}

bool _sameDate(DateTime? a, DateTime? b) {
  if (a == null || b == null) {
    return a == b;
  }
  return _localDate(a) == _localDate(b);
}

Map<DateTime, int> _normalizedCounts(Map<DateTime, int> values) {
  final normalized = <DateTime, int>{};
  for (final entry in values.entries) {
    final date = _localDate(entry.key);
    normalized[date] = (normalized[date] ?? 0) + entry.value;
  }
  return normalized;
}

DateTime _startOfWeek(DateTime date, int firstDayOfWeekIndex) {
  final materialWeekdayIndex = date.weekday % DateTime.daysPerWeek;
  final daysSinceStart =
      (materialWeekdayIndex - firstDayOfWeekIndex) % DateTime.daysPerWeek;
  return _addCalendarDays(date, -daysSinceStart);
}

String _dateKey(DateTime date) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)}';
}

String _weekdayLabel(BuildContext context, int weekday) {
  final l10n = context.l10n;
  return switch (weekday) {
    DateTime.monday => l10n.weekMon,
    DateTime.tuesday => l10n.weekTue,
    DateTime.wednesday => l10n.weekWed,
    DateTime.thursday => l10n.weekThu,
    DateTime.friday => l10n.weekFri,
    DateTime.saturday => l10n.weekSat,
    DateTime.sunday => l10n.weekSun,
    _ => '',
  };
}
