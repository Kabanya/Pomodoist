import 'package:pomodoist/ui/tasks/view_models/task_subtask_progress.dart';
import 'package:pomodoist/ui/tasks/view_models/task_branch_view_model.dart';
import 'dart:async';
import 'package:pomodoist/ui/tasks/widgets/task_branch_widgets.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' as intl;

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/widgets/compact_shell_layout.dart';
import 'package:pomodoist/ui/tasks/view_models/upcoming_view_model.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/core/widgets/action_feedback.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/widgets/quick_add_bar.dart';
import 'package:pomodoist/ui/tasks/widgets/task_list_item.dart';
import 'package:pomodoist/ui/tasks/widgets/task_motion.dart';
import 'package:pomodoist/ui/tasks/widgets/task_selection_region.dart';
import 'package:pomodoist/ui/tasks/widgets/upcoming_calendar.dart';
import 'package:pomodoist/ui/tasks/view_models/upcoming_day_groups.dart';

class UpcomingScreen extends ConsumerStatefulWidget {
  const UpcomingScreen({this.selectedDate, super.key});

  final DateTime? selectedDate;

  @override
  ConsumerState<UpcomingScreen> createState() => _UpcomingScreenState();
}

class _UpcomingScreenState extends ConsumerState<UpcomingScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _headerKey = GlobalKey();

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
    final routeDay = widget.selectedDate == null
        ? null
        : _dateOnly(widget.selectedDate!.toLocal());
    final selectedDay = routeDay;
    _syncRouteSelection(selectedDay);
    _schedulePendingScroll();
    final viewState = ref
        .watch(
          upcomingViewModelProvider(selectedDay).select(UpcomingLayout.new),
        )
        .state;
    final today = viewState.today;
    final projects = viewState.projects;
    final loadError = viewState.error;
    final loading = viewState.loading;
    return TaskMotionScope(
      key: ValueKey(selectedDay),
      builder: (context, motion) {
        final groups = ref
            .read(upcomingViewModelProvider(selectedDay).notifier)
            .groupsWithRetained(motion.retainedTasks);
        final allItems = List<TaskItem>.unmodifiable(
          mergeTasks(viewState.tasks, motion.retainedTasks),
        );
        final liveIds = {for (final task in viewState.tasks) task.id};
        final visibleTasks = [
          for (final group in groups)
            for (final row in group.rows)
              if (liveIds.contains(row.task.id)) row.task,
        ];
        return SafeArea(
          bottom: false,
          child: Consumer(
            builder: (context, ref, child) {
              final latest = ref.watch(
                upcomingViewModelProvider(
                  selectedDay,
                ).select((state) => state.tasks),
              );
              final byId = {for (final task in latest) task.id: task};
              return TaskSelectionRegion(
                scopeKey: selectedDay,
                visibleTasks: [
                  for (final task in visibleTasks)
                    if (byId.containsKey(task.id)) byId[task.id]!,
                ],
                child: child!,
              );
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth.clamp(0.0, 1200.0);
                final padding =
                    (constraints.maxWidth - width) / 2 +
                    _responsiveHorizontalPadding(width);
                final progress = motion.retainedTasks.isEmpty
                    ? ref.read(taskHierarchyViewModelProvider).progress
                    : taskSubtaskProgressById(allItems);
                return CustomScrollView(
                  key: const ValueKey('upcoming-scroll-view'),
                  controller: _scrollController,
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(padding, 20, padding, 0),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          key: _headerKey,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!CompactShellHeading.isShown(context)) ...[
                              Text(
                                context.l10n.navUpcoming,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                              const SizedBox(height: 16),
                            ],
                            UpcomingCalendar(
                              today: today,
                              selectedDate: selectedDay,
                              scheduledCounts: viewState.scheduledCounts,
                              loading: loading,
                              onDateSelected: (date) =>
                                  _selectDate(context, selectedDay, date),
                              onTodaySelected: () =>
                                  _selectToday(context, today),
                              onClearSelection: () => _clearSelection(context),
                            ),
                            if (!usesCompactMobileLayout(context)) ...[
                              const SizedBox(height: 16),
                              QuickAddBar(
                                defaultDate: selectedDay ?? today,
                                onTaskCreated: (ids) {
                                  motion.created(ids.toSet());
                                  unawaited(
                                    revealCreatedTaskBranches(
                                      context,
                                      ref,
                                      'upcoming',
                                      ids,
                                    ),
                                  );
                                  unawaited(playHaptic(AppHapticCue.light));
                                },
                              ),
                            ],
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(padding, 0, padding, 32),
                      sliver: loadError != null
                          ? SliverToBoxAdapter(
                              child: _UpcomingMessage(
                                key: const ValueKey('upcoming-error'),
                                message: context.l10n.failedToLoadTasks(
                                  loadError,
                                ),
                              ),
                            )
                          : loading
                          ? const SliverToBoxAdapter(
                              child: _UpcomingMessage(
                                key: ValueKey('upcoming-loading'),
                                child: CircularProgressIndicator(),
                              ),
                            )
                          : groups.isEmpty
                          ? SliverToBoxAdapter(
                              child: _UpcomingMessage(
                                key: const ValueKey('upcoming-empty'),
                                message: context.l10n.noUpcomingTasks,
                              ),
                            )
                          : UpcomingAgenda(
                              groups: groups,
                              today: today,
                              progressById: progress,
                              projectsById: {
                                for (final project
                                    in projects.value ?? const <ProjectItem>[])
                                  project.id: project,
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
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
          if (MediaQuery.disableAnimationsOf(context)) {
            _scrollController.jumpTo(
              _scrollController.position.minScrollExtent,
            );
          } else {
            unawaited(
              _scrollController.animateTo(
                _scrollController.position.minScrollExtent,
                duration: AppMotion.panel,
                curve: AppMotion.curve,
              ),
            );
          }
        }
        return;
      }

      if (!_scrollController.hasClients ||
          ref.read(upcomingViewModelProvider(widget.selectedDate)).loading) {
        return;
      }
      final header = _headerKey.currentContext?.findRenderObject();
      if (header is! RenderBox || !header.hasSize) return;
      _pendingScrollDay = null;
      // The selected day is the first projected day. Measure the header after
      // layout; the lazy day row need not already be mounted.
      final offset = (header.size.height + 20).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      if (MediaQuery.disableAnimationsOf(context)) {
        _scrollController.jumpTo(offset);
      } else {
        unawaited(
          _scrollController.animateTo(
            offset,
            duration: AppMotion.panel,
            curve: AppMotion.curve,
          ),
        );
      }
    });
  }
}

class UpcomingAgenda extends StatelessWidget {
  const UpcomingAgenda({
    required this.groups,
    required this.today,
    required this.progressById,
    required this.projectsById,
    super.key,
  });
  final List<UpcomingDayGroup> groups;
  final DateTime today;
  final Map<String, TaskSubtaskProgress> progressById;
  final Map<String, ProjectItem> projectsById;

  @override
  Widget build(BuildContext context) {
    final entries = [
      for (var day = 0; day < groups.length; day++)
        for (
          var row = 0;
          row < (groups[day].rows.isEmpty ? 1 : groups[day].rows.length);
          row++
        )
          (day: day, row: row),
    ];
    String entryKey(int index) {
      final entry = entries[index];
      final group = groups[entry.day];
      return group.rows.isEmpty
          ? 'empty-${_routeDate(group.date)}'
          : group.rows[entry.row].task.id;
    }

    final indices = {
      for (var i = 0; i < entries.length; i++)
        ValueKey('agenda-row-${entryKey(i)}'): i,
    };
    return SliverList(
      key: const ValueKey('upcoming-agenda'),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final entry = entries[index];
          final group = groups[entry.day];
          final first = entry.row == 0;
          final row = group.rows.isEmpty ? null : group.rows[entry.row];
          final heading = Semantics(
            header: true,
            child: Text(
              _upcomingDayHeaderLabel(context, group.date, today),
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          );
          final task = row == null
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    context.l10n.noTasksForDay,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.appColors.secondaryText,
                    ),
                  ),
                )
              : TaskListRow(
                  key: ValueKey('task-row-${row.task.id}'),
                  row: row,
                  branchScope: 'upcoming',
                  progress: progressById[row.task.id],
                  presentation: TaskListItemPresentation.agenda,
                  project: projectsById[row.task.projectId],
                );
          return KeyedSubtree(
            key: ValueKey('agenda-row-${entryKey(index)}'),
            child: Padding(
              padding: EdgeInsets.only(top: first && entry.day > 0 ? 18 : 0),
              child: KeyedSubtree(
                key: first
                    ? ValueKey('upcoming-day-group-${_routeDate(group.date)}')
                    : null,
                child: LayoutBuilder(
                  key: first
                      ? ValueKey('upcoming-day-card-${_routeDate(group.date)}')
                      : null,
                  builder: (context, constraints) {
                    final contents = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!first)
                          TaskListDivider(
                            previousDepth: group.rows[entry.row - 1].depth,
                            previousRow: group.rows[entry.row - 1],
                            nextDepth: row!.depth,
                            nextRow: row,
                          ),
                        task,
                      ],
                    );
                    if (constraints.maxWidth >= 760) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 112,
                            child: first
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: heading,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 24),
                          Expanded(child: contents),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (first)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: heading,
                          ),
                        contents,
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
        childCount: entries.length,
        findChildIndexCallback: (key) => indices[key],
      ),
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
