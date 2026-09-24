import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' as intl;
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;

import 'package:pomodoist/domain/models/tasks/calendar_models.dart';
import 'package:pomodoist/domain/models/tasks/project_colors.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/routing/task_detail_navigation.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/localization/formatters.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/app_date_time_picker.dart';
import 'package:pomodoist/ui/tasks/view_models/calendar_view_model.dart';
import 'package:pomodoist/ui/tasks/widgets/calendar_overview_panel.dart';
import 'package:pomodoist/ui/tasks/widgets/project_color_picker.dart';
import 'package:pomodoist/ui/tasks/widgets/project_localizations.dart';
import 'package:pomodoist/ui/tasks/widgets/quick_add_dialog.dart';
import 'package:pomodoist/ui/tasks/widgets/task_completion_feedback.dart';

part 'calendar_time_grid.dart';
part 'calendar_boards.dart';
part 'calendar_task_card.dart';
part 'calendar_routine_editor.dart';

/// Converts a pointer position on the 24-hour grid into a quarter-hour slot.
int calendarDropMinutes(double localY, double hourHeight) {
  if (!localY.isFinite || !hourHeight.isFinite || hourHeight <= 0) {
    throw ArgumentError('Invalid calendar coordinates');
  }
  return ((localY / hourHeight * 60 / 15).round() * 15).clamp(0, 1425);
}

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({this.selectedDate, super.key});
  final DateTime? selectedDate;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  bool _overviewOpen = true;
  bool _savingMode = false;
  final _pending = <String>{};
  final _overviewFocus = FocusNode();

  @override
  void dispose() {
    _overviewFocus.dispose();
    super.dispose();
  }

  Future<void> _run(String id, Future<void> Function() action) async {
    if (_pending.contains(id)) return;
    setState(() => _pending.add(id));
    try {
      await action();
    } catch (_) {
      if (mounted)
        _calendarError(context, context.l10n.taskActionFailedCount(1));
    } finally {
      if (mounted) setState(() => _pending.remove(id));
    }
  }

  Future<void> _setMode(CalendarMode mode) async {
    if (_savingMode) return;
    setState(() => _savingMode = true);
    try {
      await ref.read(calendarViewModelProvider.notifier).setMode(mode);
    } catch (_) {
      if (mounted) _calendarError(context, context.l10n.calendarSaveFailed);
    } finally {
      if (mounted) setState(() => _savingMode = false);
    }
  }

  void _goToDate(DateTime date) {
    final uri = GoRouterState.of(context).uri;
    context.go(
      uri
          .replace(
            queryParameters: {
              ...uri.queryParameters,
              'date':
                  '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
            },
          )
          .toString(),
    );
  }

  Future<void> _selectDay(DateTime day) async {
    await _setMode(CalendarMode.day);
    if (mounted) _goToDate(day);
  }

  Future<void> _overview(DateTime date, bool wide) async {
    if (wide) {
      setState(() => _overviewOpen = !_overviewOpen);
      return;
    }
    await showDialog<void>(
      context: context,
      useSafeArea: true,
      animationStyle: AnimationStyle(
        duration: AppMotion.duration(context, AppMotion.popup),
        reverseDuration: AppMotion.duration(context, AppMotion.popup),
      ),
      builder: (dialogContext) => Dialog(
        alignment: AlignmentDirectional.centerEnd,
        insetPadding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 350,
          height: MediaQuery.sizeOf(context).height * .88,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: CalendarOverviewPanel(
              selectedDate: date,
              onDateSelected: (day) {
                Navigator.of(dialogContext).pop();
                _goToDate(day);
              },
              onOpenMonth: () {
                Navigator.of(dialogContext).pop();
                unawaited(_setMode(CalendarMode.month));
              },
              onClose: () => Navigator.of(dialogContext).pop(),
              onOpenTask: (id) {
                Navigator.of(dialogContext).pop();
                openTaskDetails(context, id);
              },
            ),
          ),
        ),
      ),
    );
    if (mounted) _overviewFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(calendarViewModelProvider);
    final vm = ref.read(calendarViewModelProvider.notifier);
    final selected = widget.selectedDate ?? state.now;
    final day = DateTime(selected.year, selected.month, selected.day);
    final mode = state.settings.mode;
    final material = MaterialLocalizations.of(context);
    final firstWeekday = material.firstDayOfWeekIndex == 0
        ? 7
        : material.firstDayOfWeekIndex;
    final presentation = vm.presentation(day, mode, firstWeekday: firstWeekday);
    final actions = _CalendarActions(
      pending: _pending,
      onMove: (id, target, {minutes, allDay = false}) => _run(
        id,
        () => vm.moveTask(id, target, minutes: minutes, allDay: allDay),
      ),
      onResize: (id, end) => _run(id, () => vm.resizeTask(id, end)),
      onUnschedule: (id) => _run(id, () => vm.unscheduleTask(id)),
      onComplete: (id) => _run(id, () async {
        await completeTaskWithUndoFeedback(
          context,
          complete: () => vm.completeTask(id),
          undo: () => vm.reopenTask(id),
        );
      }),
      onSelectDay: (date) => unawaited(_selectDay(date)),
      onAdd: (date, [minutes]) => unawaited(
        showQuickAddDialog(
          context,
          defaultDate: date,
          projectId: state.projectId,
          initialText: minutes == null ? '' : '${_calendarClock(minutes)} ',
        ),
      ),
    );
    final colors = context.appColors;
    final l10n = context.l10n;
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1060;
          final content = Padding(
            padding: EdgeInsets.fromLTRB(
              constraints.maxWidth < 600 ? 12 : 24,
              20,
              constraints.maxWidth < 600 ? 12 : 24,
              8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 20,
                  runSpacing: 12,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.navCalendar,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.calendarSubtitle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.secondaryText),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.surfaceTint,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Wrap(
                            children: [
                              for (final value in CalendarMode.values)
                                Padding(
                                  padding: const EdgeInsets.all(3),
                                  child: Semantics(
                                    selected: mode == value,
                                    child: TextButton(
                                      onPressed:
                                          _savingMode || !state.settingsLoaded
                                          ? null
                                          : () => unawaited(_setMode(value)),
                                      style: TextButton.styleFrom(
                                        foregroundColor: mode == value
                                            ? colors.primaryText
                                            : colors.secondaryText,
                                        backgroundColor: mode == value
                                            ? colors.surface
                                            : Colors.transparent,
                                        minimumSize: const Size(48, 40),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        _calendarModeLabel(context, value),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        ShadButton.outline(
                          focusNode: _overviewFocus,
                          onPressed: () => unawaited(_overview(day, wide)),
                          leading: Icon(
                            LucideIcons.panelRight,
                            size: 16,
                            color: wide && _overviewOpen ? colors.accent : null,
                          ),
                          child: Text(l10n.calendarOverview),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: l10n.calendarPreviousPeriod,
                                      onPressed: () => _goToDate(
                                        _shiftCalendarDate(day, mode, -1),
                                      ),
                                      icon: const Icon(
                                        LucideIcons.chevronLeft,
                                        size: 18,
                                      ),
                                    ),
                                    AppDateTimePicker(
                                      builder: (context, picker) => TextButton(
                                        focusNode: picker.focusNode,
                                        onPressed: () async {
                                          final picked = await picker.pickDate(
                                            initialDate: day,
                                            firstDate: DateTime(1900),
                                            lastDate: DateTime(2200),
                                          );
                                          if (picked != null && mounted)
                                            _goToDate(picked);
                                        },
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxWidth: math.max(
                                              70,
                                              math.min(
                                                260,
                                                constraints.maxWidth - 200,
                                              ),
                                            ),
                                          ),
                                          child: Text(
                                            _calendarPeriodLabel(
                                              context,
                                              day,
                                              mode,
                                              presentation.days,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleSmall,
                                          ),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: l10n.calendarNextPeriod,
                                      onPressed: () => _goToDate(
                                        _shiftCalendarDate(day, mode, 1),
                                      ),
                                      icon: const Icon(
                                        LucideIcons.chevronRight,
                                        size: 18,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => _goToDate(state.now),
                                      child: Text(l10n.today),
                                    ),
                                  ],
                                ),
                                PopupMenuButton<String>(
                                  tooltip: l10n.calendarAllProjects,
                                  onSelected: (id) =>
                                      vm.setProject(id.isEmpty ? null : id),
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      value: '',
                                      child: Text(l10n.calendarAllProjects),
                                    ),
                                    for (final project
                                        in presentation.projectsById.values)
                                      PopupMenuItem(
                                        value: project.id,
                                        child: Text(
                                          project.displayName(context.l10n),
                                        ),
                                      ),
                                  ],
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          LucideIcons.listFilter,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 6),
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: 180,
                                          ),
                                          child: Text(
                                            state.projectId == null
                                                ? l10n.calendarAllProjects
                                                : presentation
                                                          .projectsById[state
                                                              .projectId!]
                                                          ?.displayName(
                                                            context.l10n,
                                                          ) ??
                                                      l10n.calendarAllProjects,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (state.settingsError != null)
                              TextButton(
                                onPressed: vm.retry,
                                child: Text(l10n.calendarSaveFailed),
                              ),
                            const SizedBox(height: 8),
                            Expanded(
                              child:
                                  state.tasks.hasError ||
                                      state.projects.hasError
                                  ? Center(
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
                                    )
                                  : state.tasks.isLoading ||
                                        state.projects.isLoading
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : switch (mode) {
                                      CalendarMode.day ||
                                      CalendarMode.week => _CalendarTimeGrid(
                                        key: ValueKey((mode, day)),
                                        days: presentation.days,
                                        projects: presentation.projectsById,
                                        now: state.now,
                                        actions: actions,
                                      ),
                                      CalendarMode.month => _CalendarMonthBoard(
                                        days: presentation.days,
                                        month: day.month,
                                        projects: presentation.projectsById,
                                        now: state.now,
                                        actions: actions,
                                      ),
                                      CalendarMode.routine =>
                                        _CalendarRoutineBoard(
                                          days: vm.routineDays(presentation),
                                          settings: state.settings,
                                          projects: presentation.projectsById,
                                          now: state.now,
                                          actions: actions,
                                          onConfigure: () => unawaited(
                                            showDialog<void>(
                                              context: context,
                                              builder: (_) =>
                                                  _CalendarRoutineEditor(
                                                    settings: state.settings,
                                                    save: vm.saveRoutine,
                                                  ),
                                            ),
                                          ),
                                        ),
                                    },
                            ),
                            _CalendarUnscheduled(
                              tasks: presentation.unscheduled,
                              projects: presentation.projectsById,
                              actions: actions,
                            ),
                          ],
                        ),
                      ),
                      if (wide && _overviewOpen) ...[
                        const SizedBox(width: 22),
                        Container(
                          width: 300,
                          decoration: BoxDecoration(
                            border: BorderDirectional(
                              start: BorderSide(color: colors.border),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(start: 8),
                            child: CalendarOverviewPanel(
                              selectedDate: day,
                              onDateSelected: _goToDate,
                              onOpenMonth: () =>
                                  unawaited(_setMode(CalendarMode.month)),
                              onClose: () {
                                setState(() => _overviewOpen = false);
                                _overviewFocus.requestFocus();
                              },
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
          if (constraints.maxHeight < 540) {
            return SingleChildScrollView(
              child: SizedBox(height: 660, child: content),
            );
          }
          return content;
        },
      ),
    );
  }
}

class _CalendarActions {
  const _CalendarActions({
    required this.pending,
    required this.onMove,
    required this.onResize,
    required this.onUnschedule,
    required this.onComplete,
    required this.onSelectDay,
    required this.onAdd,
  });
  final Set<String> pending;
  final Future<void> Function(String, DateTime, {int? minutes, bool allDay})
  onMove;
  final Future<void> Function(String, DateTime) onResize;
  final Future<void> Function(String) onUnschedule;
  final Future<void> Function(String) onComplete;
  final ValueChanged<DateTime> onSelectDay;
  final void Function(DateTime, [int?]) onAdd;
}

void _calendarError(BuildContext context, String message) =>
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));

String _calendarClock(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
String _calendarTime(BuildContext context, int minute) => minute == 1440
    ? _calendarTime(context, 0)
    : MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );
bool _sameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
DateTime _shiftCalendarDate(DateTime day, CalendarMode mode, int direction) =>
    mode == CalendarMode.month
    ? DateTime(day.year, day.month + direction, 1)
    : DateTime(
        day.year,
        day.month,
        day.day + direction * (mode == CalendarMode.day ? 1 : 7),
      );
String _calendarModeLabel(BuildContext context, CalendarMode mode) =>
    switch (mode) {
      CalendarMode.day => context.l10n.calendarDay,
      CalendarMode.week => context.l10n.calendarWeek,
      CalendarMode.month => context.l10n.calendarMonth,
      CalendarMode.routine => context.l10n.calendarRoutine,
    };
String _calendarPeriodLabel(
  BuildContext context,
  DateTime day,
  CalendarMode mode,
  List<CalendarDay> days,
) {
  final locale = Localizations.localeOf(context).toString();
  if (mode == CalendarMode.day) return intl.DateFormat.MMMd(locale).format(day);
  if (mode == CalendarMode.month)
    return MaterialLocalizations.of(context).formatMonthYear(day);
  return '${intl.DateFormat.MMMd(locale).format(days.first.date)} – ${intl.DateFormat.MMMMd(locale).format(days.last.date)}';
}

String _calendarPeriodName(
  BuildContext context,
  CalendarPeriod period,
  int index,
) => period.name.isNotEmpty
    ? period.name
    : switch (index) {
        0 => context.l10n.calendarMorning,
        1 => context.l10n.calendarAfternoon,
        2 => context.l10n.calendarEvening,
        _ => context.l10n.calendarNewPeriod,
      };
