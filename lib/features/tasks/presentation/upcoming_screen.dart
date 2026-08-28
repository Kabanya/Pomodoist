import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' as intl;

import '../../../app/app_l10n.dart';
import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/action_feedback.dart';
import '../domain/task_models.dart';
import 'widgets/quick_add_bar.dart';
import 'widgets/task_list_item.dart';
import 'widgets/task_motion.dart';
import 'widgets/task_selection_region.dart';
import 'widgets/upcoming_calendar.dart';
import 'widgets/upcoming_day_groups.dart';

class UpcomingScreen extends ConsumerStatefulWidget {
  const UpcomingScreen({this.selectedDate, super.key});

  final DateTime? selectedDate;

  @override
  ConsumerState<UpcomingScreen> createState() => _UpcomingScreenState();
}

class _UpcomingScreenState extends ConsumerState<UpcomingScreen> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _dayAnchors = <String, GlobalKey>{};

  DateTime? _lastRouteSelection;
  DateTime? _pendingScrollDay;
  bool _routeSelectionInitialized = false;
  bool _pendingScrollTop = false;
  bool _scrollScheduled = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider).now().toLocal();
    final today = _dateOnly(now);
    final routeDay = widget.selectedDate == null
        ? null
        : _dateOnly(widget.selectedDate!.toLocal());
    final selectedDay = routeDay;
    _syncRouteSelection(selectedDay);
    _schedulePendingScroll();
    final openTasks = ref.watch(tasksByQueryProvider(const TaskQuery.all()));
    final completedTasks = ref.watch(
      tasksByQueryProvider(const TaskQuery.completed()),
    );
    final projects = ref.watch(projectsProvider);
    final loadError = openTasks.hasError
        ? openTasks.error
        : completedTasks.hasError
        ? completedTasks.error
        : null;
    final loading =
        loadError == null && (!openTasks.hasValue || !completedTasks.hasValue);
    final loadedItems = _mergeTasks(
      openTasks.value ?? const <TaskItem>[],
      completedTasks.value ?? const <TaskItem>[],
    );
    return TaskMotionScope(
      key: ValueKey(selectedDay),
      builder: (context, motion) {
        final itemsById = {for (final task in loadedItems) task.id: task};
        for (final task in motion.retainedTasks) {
          itemsById[task.id] = task;
        }
        final allItems = List<TaskItem>.unmodifiable(itemsById.values);
        final scheduledTasks = _scheduledTasks(allItems);
        final scheduledCounts = _scheduledTaskCounts(scheduledTasks);
        final groups = buildUpcomingDayGroups(
          scheduledTasks,
          selectedDate: selectedDay,
          visibleFromDate: selectedDay ?? today,
        );
        final visibleTasks = [
          for (final group in groups)
            for (final row in group.rows) row.task,
        ];
        return SafeArea(
          bottom: false,
          child: TaskSelectionRegion(
            visibleTasks: visibleTasks,
            scopeKey: selectedDay,
            child: SingleChildScrollView(
              key: const ValueKey('upcoming-scroll-view'),
              controller: _scrollController,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final horizontalPadding = _responsiveHorizontalPadding(
                        constraints.maxWidth,
                      );
                      return Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          20,
                          horizontalPadding,
                          32,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.navUpcoming,
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 16),
                            UpcomingCalendar(
                              today: today,
                              selectedDate: selectedDay,
                              scheduledCounts: scheduledCounts,
                              loading: loading,
                              onDateSelected: (date) =>
                                  _selectDate(context, selectedDay, date),
                              onTodaySelected: () =>
                                  _selectToday(context, today),
                              onClearSelection: () => _clearSelection(context),
                            ),
                            const SizedBox(height: 16),
                            QuickAddBar(
                              defaultDate: selectedDay ?? today,
                              onTaskCreated: (taskIds) {
                                motion.created(taskIds.toSet());
                                unawaited(playHaptic(AppHapticCue.light));
                              },
                            ),
                            const SizedBox(height: 20),
                            if (loadError != null)
                              _UpcomingMessage(
                                key: const ValueKey('upcoming-error'),
                                message: context.l10n.failedToLoadTasks(
                                  loadError,
                                ),
                              )
                            else if (loading)
                              const _UpcomingMessage(
                                key: ValueKey('upcoming-loading'),
                                child: CircularProgressIndicator(),
                              )
                            else
                              _buildAgenda(
                                context,
                                groups: groups,
                                allItems: allItems,
                                today: today,
                                projects:
                                    projects.value ?? const <ProjectItem>[],
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAgenda(
    BuildContext context, {
    required List<UpcomingDayGroup> groups,
    required List<TaskItem> allItems,
    required DateTime today,
    required List<ProjectItem> projects,
  }) {
    if (groups.isEmpty) {
      return _UpcomingMessage(
        key: const ValueKey('upcoming-empty'),
        message: context.l10n.noUpcomingTasks,
      );
    }
    return UpcomingAgenda(
      groups: groups,
      today: today,
      dayAnchorBuilder: _dayAnchor,
      progressById: taskSubtaskProgressById(allItems),
      projectsById: {for (final project in projects) project.id: project},
    );
  }

  void _selectDate(BuildContext context, DateTime? selectedDay, DateTime date) {
    final day = _dateOnly(date.toLocal());
    if (selectedDay == day) {
      _clearSelection(context);
      return;
    }
    context.go('/upcoming?date=${_routeDate(day)}');
  }

  void _clearSelection(BuildContext context) {
    _prepareSelectionClear();
    context.go('/upcoming');
  }

  void _selectToday(BuildContext context, DateTime today) =>
      context.go('/upcoming?date=${_routeDate(today)}');

  void _prepareSelectionClear() {
    _pendingScrollDay = null;
    _pendingScrollTop = true;
    _schedulePendingScroll();
  }

  void _syncRouteSelection(DateTime? selectedDay) {
    if (_routeSelectionInitialized && _lastRouteSelection == selectedDay) {
      return;
    }
    _routeSelectionInitialized = true;
    _lastRouteSelection = selectedDay;
    _pendingScrollDay = selectedDay;
    _pendingScrollTop = selectedDay == null;
  }

  GlobalKey _dayAnchor(DateTime date) {
    final key = _routeDate(date);
    return _dayAnchors.putIfAbsent(
      key,
      () => GlobalKey(debugLabel: 'upcoming-day-anchor-$key'),
    );
  }

  void _schedulePendingScroll() {
    if (_scrollScheduled || (_pendingScrollDay == null && !_pendingScrollTop)) {
      return;
    }
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted) {
        return;
      }
      if (_pendingScrollTop) {
        _pendingScrollTop = false;
        if (_scrollController.hasClients) {
          unawaited(
            _scrollController.animateTo(
              _scrollController.position.minScrollExtent,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
            ),
          );
        }
        return;
      }

      final day = _pendingScrollDay;
      final anchorContext = day == null ? null : _dayAnchor(day).currentContext;
      if (anchorContext == null) {
        return;
      }
      _pendingScrollDay = null;
      unawaited(
        Scrollable.ensureVisible(
          anchorContext,
          alignment: 0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }
}

class UpcomingAgenda extends StatelessWidget {
  const UpcomingAgenda({
    required this.groups,
    required this.today,
    required this.progressById,
    required this.projectsById,
    this.dayAnchorBuilder,
    super.key,
  });

  final List<UpcomingDayGroup> groups;
  final DateTime today;
  final Map<String, TaskSubtaskProgress> progressById;
  final Map<String, ProjectItem> projectsById;
  final Key Function(DateTime date)? dayAnchorBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('upcoming-agenda'),
      children: [
        for (var index = 0; index < groups.length; index++) ...[
          if (index > 0) const SizedBox(height: 18),
          KeyedSubtree(
            key: ValueKey(
              'upcoming-day-group-${_routeDate(groups[index].date)}',
            ),
            child: KeyedSubtree(
              key: dayAnchorBuilder?.call(groups[index].date),
              child: _UpcomingDayCard(
                group: groups[index],
                today: today,
                progressById: progressById,
                projectsById: projectsById,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _UpcomingDayCard extends StatelessWidget {
  const _UpcomingDayCard({
    required this.group,
    required this.today,
    required this.progressById,
    required this.projectsById,
  });

  final UpcomingDayGroup group;
  final DateTime today;
  final Map<String, TaskSubtaskProgress> progressById;
  final Map<String, ProjectItem> projectsById;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 14, bottom: 8),
            child: Text(
              _upcomingDayHeaderLabel(context, group.date, today),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: colors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        DecoratedBox(
          key: ValueKey('upcoming-day-card-${_routeDate(group.date)}'),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (group.rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    context.l10n.noTasksForDay,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: colors.mutedText),
                  ),
                )
              else
                for (var index = 0; index < group.rows.length; index++) ...[
                  if (index > 0)
                    Divider(height: 1, indent: 52, color: colors.border),
                  TaskListItem(
                    task: group.rows[index].task,
                    depth: group.rows[index].depth,
                    subtaskProgress: progressById[group.rows[index].task.id],
                    presentation: TaskListItemPresentation.agenda,
                    project: projectsById[group.rows[index].task.projectId],
                  ),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

class _UpcomingMessage extends StatelessWidget {
  const _UpcomingMessage({this.message, this.child, super.key});

  final String? message;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 180,
      child: Center(
        child:
            child ??
            Text(message!, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}

Map<DateTime, int> _scheduledTaskCounts(Iterable<TaskItem> tasks) {
  final counts = <DateTime, int>{};
  for (final task in tasks) {
    final schedule = task.schedule;
    if (schedule == null) {
      continue;
    }
    final date = _dateOnly(schedule.displayDate.toLocal());
    counts.update(date, (value) => value + 1, ifAbsent: () => 1);
  }
  return counts;
}

List<TaskItem> _mergeTasks(
  Iterable<TaskItem> open,
  Iterable<TaskItem> completed,
) {
  final tasksById = <String, TaskItem>{};
  for (final task in open) {
    tasksById.putIfAbsent(task.id, () => task);
  }
  for (final task in completed) {
    tasksById.putIfAbsent(task.id, () => task);
  }
  return List<TaskItem>.unmodifiable(tasksById.values);
}

List<TaskItem> _scheduledTasks(Iterable<TaskItem> tasks) {
  return [
    for (final task in tasks)
      if (!task.isDeleted && task.schedule != null) task,
  ];
}

String _relativeWeekdayLabel(
  BuildContext context,
  DateTime date,
  DateTime today,
) {
  final day = _dateOnly(date);
  final localToday = _dateOnly(today);
  final tomorrow = DateTime(
    localToday.year,
    localToday.month,
    localToday.day + 1,
  );
  if (day == localToday) {
    return context.l10n.today;
  }
  if (day == tomorrow) {
    return context.l10n.tomorrow;
  }
  return intl.DateFormat.EEEE(context.l10n.localeName).format(day);
}

String _upcomingDayHeaderLabel(
  BuildContext context,
  DateTime date,
  DateTime today,
) {
  final day = _dateOnly(date);
  final locale = context.l10n.localeName;
  final dateLabel = day.year == today.year
      ? intl.DateFormat.MMMMd(locale).format(day)
      : intl.DateFormat.yMMMMd(locale).format(day);
  final label = '${_relativeWeekdayLabel(context, day, today)}, $dateLabel';
  if (label.isEmpty) {
    return label;
  }
  return '${label[0].toUpperCase()}${label.substring(1)}';
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

double _responsiveHorizontalPadding(double width) {
  if (width < 352) {
    return ((width - 320) / 2).clamp(0, 16).toDouble();
  }
  if (width < 760) {
    return 16;
  }
  return 24;
}

String _routeDate(DateTime date) {
  final normalized = _dateOnly(date);
  return '${normalized.year.toString().padLeft(4, '0')}-'
      '${normalized.month.toString().padLeft(2, '0')}-'
      '${normalized.day.toString().padLeft(2, '0')}';
}
