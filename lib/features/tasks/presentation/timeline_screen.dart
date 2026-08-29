import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_l10n.dart';
import '../../../app/formatters.dart';
import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/action_feedback.dart';
import '../../../core/db/app_database.dart';
import '../domain/project_colors.dart';
import '../domain/task_models.dart';
import 'task_completion_feedback.dart';
import 'timeline_project_layout.dart';
import 'widgets/project_color_picker.dart';
import 'widgets/task_motion.dart';

const _defaultTimedTaskDuration = Duration(minutes: 30);
const _minTimedTaskDuration = Duration(minutes: timelineSnapMinutes);
const _minutesPerDay = 24 * 60;
const _timeRulerHeight = 32.0;
const _laneHeight = 64.0;
const _inlineAddWidth = 280.0;
const _blockGap = 4.0;

class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({this.selectedDate, super.key});

  final DateTime? selectedDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final today = _dateOnly(ref.watch(clockProvider).now().toLocal());
    final day = _dateOnly(selectedDate ?? today);
    final tasks = ref.watch(tasksByQueryProvider(const TaskQuery.all()));
    final projects = ref.watch(projectsProvider);
    final visibleHours = ref.watch(timelineVisibleHoursProvider);

    return TaskMotionScope(
      key: ValueKey(day),
      builder: (context, motion) => SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.navTimeline,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.timelineSubtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _TimelineHeader(day: day, today: today),
                    const SizedBox(height: 12),
                    _VisibleHoursControls(visibleHours: visibleHours),
                  ],
                ),
              ),
            ),
            tasks.when(
              data: (items) {
                final visibleById = {for (final item in items) item.id: item};
                for (final item in motion.retainedTasks) {
                  visibleById[item.id] = item;
                }
                return projects.when(
                  data: (projectItems) => SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    sliver: SliverToBoxAdapter(
                      child: _TimelineDay(
                        day: day,
                        tasks: visibleById.values.toList(),
                        projects: projectItems,
                        visibleHours: visibleHours,
                      ),
                    ),
                  ),
                  loading: () => const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, stackTrace) => SliverFillRemaining(
                    child: Center(child: Text(l10n.projectsUnavailable(error))),
                  ),
                );
              },
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stackTrace) => SliverFillRemaining(
                child: Center(child: Text(l10n.failedToLoadTasks(error))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineHeader extends StatelessWidget {
  const _TimelineHeader({required this.day, required this.today});

  final DateTime day;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton.filledTonal(
          tooltip: l10n.timelinePreviousDay,
          onPressed: () =>
              _goToDate(context, day.subtract(const Duration(days: 1))),
          icon: const Icon(Icons.chevron_left),
        ),
        FilledButton.tonalIcon(
          onPressed: () => _pickDate(context, day),
          icon: const Icon(Icons.event_outlined),
          label: Text(formatLocalDate(context, day)),
        ),
        IconButton.filledTonal(
          tooltip: l10n.timelineNextDay,
          onPressed: () => _goToDate(context, day.add(const Duration(days: 1))),
          icon: const Icon(Icons.chevron_right),
        ),
        OutlinedButton(
          onPressed: _isSameDay(day, today)
              ? null
              : () => _goToDate(context, today),
          child: Text(l10n.today),
        ),
      ],
    );
  }

  Future<void> _pickDate(BuildContext context, DateTime initialDate) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
      helpText: context.l10n.timelinePickDate,
    );
    if (picked != null && context.mounted) {
      _goToDate(context, picked);
    }
  }

  void _goToDate(BuildContext context, DateTime date) {
    context.go('/timeline?date=${_formatRouteDate(_dateOnly(date))}');
  }
}

class _VisibleHoursControls extends ConsumerWidget {
  const _VisibleHoursControls({required this.visibleHours});

  final TimelineVisibleHours visibleHours;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final hourWidth = ref.watch(timelineHourWidthProvider);
    final zoomIndex = timelineHourWidthLevels.indexOf(hourWidth);
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
              l10n.timelineVisibleHours,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colors.secondaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<int>(
                    key: const Key('timeline-start-minutes'),
                    initialValue: visibleHours.startMinutes,
                    decoration: InputDecoration(
                      labelText: l10n.timelineStartHour,
                    ),
                    items: [
                      for (final value in _timeOptions)
                        if (value < visibleHours.endMinutes)
                          DropdownMenuItem(
                            value: value,
                            child: Text(_formatMinutes(value)),
                          ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        unawaited(
                          ref
                              .read(timelineVisibleHoursProvider.notifier)
                              .setVisibleHours(value, visibleHours.endMinutes),
                        );
                      }
                    },
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<int>(
                    key: const Key('timeline-end-minutes'),
                    initialValue: visibleHours.endMinutes,
                    decoration: InputDecoration(
                      labelText: l10n.timelineEndHour,
                    ),
                    items: [
                      for (final value in _timeOptions)
                        if (value > visibleHours.startMinutes)
                          DropdownMenuItem(
                            value: value,
                            child: Text(_formatMinutes(value)),
                          ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        unawaited(
                          ref
                              .read(timelineVisibleHoursProvider.notifier)
                              .setVisibleHours(
                                visibleHours.startMinutes,
                                value,
                              ),
                        );
                      }
                    },
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton.outlined(
                      key: const Key('timeline-zoom-out'),
                      tooltip: l10n.timelineZoomOut,
                      onPressed: zoomIndex == 0
                          ? null
                          : () => unawaited(
                              ref
                                  .read(timelineHourWidthProvider.notifier)
                                  .zoomOut(),
                            ),
                      icon: const Icon(Icons.zoom_out),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      key: const Key('timeline-zoom-in'),
                      tooltip: l10n.timelineZoomIn,
                      onPressed: zoomIndex == timelineHourWidthLevels.length - 1
                          ? null
                          : () => unawaited(
                              ref
                                  .read(timelineHourWidthProvider.notifier)
                                  .zoomIn(),
                            ),
                      icon: const Icon(Icons.zoom_in),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineDay extends ConsumerWidget {
  const _TimelineDay({
    required this.day,
    required this.tasks,
    required this.projects,
    required this.visibleHours,
  });

  final DateTime day;
  final List<TaskItem> tasks;
  final List<ProjectItem> projects;
  final TimelineVisibleHours visibleHours;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hourWidth = ref.watch(timelineHourWidthProvider);
    final dayTasks = tasks.where((task) {
      final schedule = task.schedule;
      return !task.isCompleted &&
          schedule != null &&
          _isSameDay(schedule.displayDate, day);
    }).toList();
    final tasksById = {for (final task in dayTasks) task.id: task};
    final projectsById = {for (final project in projects) project.id: project};
    final allDayTasks = <TaskItem>[];
    final visibleTimedTasks = <TaskItem>[];
    final beforeTasks = <TaskItem>[];
    final afterTasks = <TaskItem>[];

    for (final task in dayTasks) {
      final schedule = task.schedule!;
      if (schedule.isAllDay) {
        allDayTasks.add(task);
        continue;
      }
      final startMinutes = _startMinutes(schedule);
      if (startMinutes < visibleHours.startMinutes) {
        beforeTasks.add(task);
      } else if (startMinutes >= visibleHours.endMinutes) {
        afterTasks.add(task);
      } else {
        visibleTimedTasks.add(task);
      }
    }

    allDayTasks.sort(_compareTimelineTaskOrder);
    visibleTimedTasks.sort(_compareTimedTaskOrder);
    beforeTasks.sort(_compareTimedTaskOrder);
    afterTasks.sort(_compareTimedTaskOrder);
    final collapsedProjectIds = ref.watch(timelineCollapsedProjectIdsProvider);
    final temporarilyVisibleProjectIds = ref.watch(
      timelineTemporarilyVisibleProjectIdsProvider,
    );
    final projectRows = buildTimelineProjectRows(
      projects: projects,
      tasks: dayTasks,
      collapsedProjectIds: collapsedProjectIds,
      temporarilyVisibleProjectIds: temporarilyVisibleProjectIds,
    );
    final timedTasksByProject = <String, List<TaskItem>>{};
    for (final task in visibleTimedTasks) {
      timedTasksByProject.putIfAbsent(task.projectId, () => []).add(task);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AllDaySection(
          day: day,
          tasks: allDayTasks,
          tasksById: tasksById,
          projectsById: projectsById,
        ),
        if (beforeTasks.isNotEmpty) ...[
          const SizedBox(height: 12),
          _OutOfRangeSection(
            key: const Key('timeline-before-hours-section'),
            title: context.l10n.timelineBeforeHours,
            tasks: beforeTasks,
            projectsById: projectsById,
          ),
        ],
        if (afterTasks.isNotEmpty) ...[
          const SizedBox(height: 12),
          _OutOfRangeSection(
            key: const Key('timeline-after-hours-section'),
            title: context.l10n.timelineAfterHours,
            tasks: afterTasks,
            projectsById: projectsById,
          ),
        ],
        const SizedBox(height: 12),
        _TimelineGrid(
          day: day,
          projectRows: projectRows,
          tasksByProject: timedTasksByProject,
          projects: projects,
          tasksById: tasksById,
          visibleHours: visibleHours,
          hourWidth: hourWidth,
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
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            color: accepting ? colors.accentTint : colors.surface,
            border: Border.all(
              color: accepting ? colors.accent : colors.border,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.timelineAllDay,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      '${widget.tasks.length}',
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: colors.mutedText),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_adding)
                  _InlineAddField(
                    key: const Key('timeline-inline-add-all-day'),
                    hintText: context.l10n.timelineAddAllDayHint,
                    onCancel: () => setState(() => _adding = false),
                    onSubmit: (input) async {
                      final taskId = await ref
                          .read(quickAddServiceProvider)
                          .createTask(
                            input,
                            defaultSchedule: TaskSchedule.allDay(widget.day),
                          );
                      if (mounted) {
                        TaskMotionScope.maybeOf(
                          this.context,
                        )?.created({taskId});
                        await playHaptic(AppHapticCue.light);
                        setState(() => _adding = false);
                      }
                    },
                  )
                else if (widget.tasks.isEmpty)
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
                else
                  Column(
                    children: [
                      for (final task in widget.tasks) ...[
                        _TimelineCompactTaskBlock(
                          task: task,
                          project: widget.projectsById[task.projectId],
                          showProjectName: true,
                        ),
                        if (task != widget.tasks.last)
                          const SizedBox(height: 8),
                      ],
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => setState(() => _adding = true),
                          icon: const Icon(Icons.add),
                          label: Text(context.l10n.commonAdd),
                        ),
                      ),
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

class _TimelineGrid extends ConsumerStatefulWidget {
  const _TimelineGrid({
    required this.day,
    required this.projectRows,
    required this.tasksByProject,
    required this.projects,
    required this.tasksById,
    required this.visibleHours,
    required this.hourWidth,
  });

  final DateTime day;
  final List<TimelineProjectRow> projectRows;
  final Map<String, List<TaskItem>> tasksByProject;
  final List<ProjectItem> projects;
  final Map<String, TaskItem> tasksById;
  final TimelineVisibleHours visibleHours;
  final int hourWidth;

  @override
  ConsumerState<_TimelineGrid> createState() => _TimelineGridState();
}

class _TimelineGridState extends ConsumerState<_TimelineGrid> {
  final _gridKey = GlobalKey();
  final _gridFocusNode = FocusNode(debugLabel: 'Timeline grid');
  final _horizontalScrollController = ScrollController();
  final _touchZoomPointers = <int, Offset>{};
  int? _addingAtMinutes;
  String? _addingProjectId;
  String? _resizingTaskId;
  int? _resizeStartEndMinutes;
  double _resizeDelta = 0;
  double? _touchZoomStartDistance;
  double? _touchZoomAnchorMinutes;
  int? _touchZoomStartHourWidth;
  int? _trackpadZoomStartHourWidth;
  (int, double, double)? _pendingGestureZoom;
  Timer? _clockTimer;

  double get _pixelsPerMinute => widget.hourWidth / 60;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _gridFocusNode.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _TimelineGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hourWidth == widget.hourWidth ||
        !_horizontalScrollController.hasClients) {
      return;
    }
    final position = _horizontalScrollController.position;
    final oldOffset = position.pixels;
    final pendingGestureZoom = _pendingGestureZoom;
    _pendingGestureZoom = null;
    final gestureAnchor = pendingGestureZoom?.$1 == widget.hourWidth
        ? pendingGestureZoom?.$2
        : null;
    final gestureAnchorMinutes = pendingGestureZoom?.$1 == widget.hourWidth
        ? pendingGestureZoom?.$3
        : null;
    if (oldOffset <= 0.5 && gestureAnchor == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _horizontalScrollController.hasClients) {
          _horizontalScrollController.jumpTo(0);
        }
      });
      return;
    }
    final anchor = (gestureAnchor ?? position.viewportDimension / 2).clamp(
      0.0,
      position.viewportDimension,
    );
    final centerMinutes =
        gestureAnchorMinutes ??
        oldWidget.visibleHours.startMinutes +
            (oldOffset + anchor) / (oldWidget.hourWidth / 60);
    final target =
        (centerMinutes - widget.visibleHours.startMinutes) * _pixelsPerMinute -
        anchor;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_horizontalScrollController.hasClients) {
        return;
      }
      final nextPosition = _horizontalScrollController.position;
      _horizontalScrollController.jumpTo(
        target.clamp(
          nextPosition.minScrollExtent,
          nextPosition.maxScrollExtent,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.visibleHours.startMinutes;
    final end = widget.visibleHours.endMinutes;
    final visibleMinutes = math.max(timelineSnapMinutes, end - start);
    final trackWidth = visibleMinutes * _pixelsPerMinute;
    final projectLayouts = _projectLayouts();
    final totalHeight = projectLayouts.isEmpty
        ? _timeRulerHeight + _laneHeight
        : projectLayouts.last.bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        final projectColumnWidth = constraints.maxWidth < 600 ? 112.0 : 200.0;
        return AnimatedBuilder(
          animation: _gridFocusNode,
          builder: (context, _) => DecoratedBox(
            key: const Key('timeline-grid-frame'),
            decoration: BoxDecoration(
              color: context.appColors.surface,
              border: Border.all(
                color: _gridFocusNode.hasPrimaryFocus
                    ? context.appColors.accent
                    : context.appColors.border,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    key: const Key('timeline-project-column'),
                    width: projectColumnWidth,
                    height: totalHeight,
                    child: Column(
                      children: [
                        _ProjectColumnHeader(
                          projects: widget.projects,
                          visibleProjectIds: widget.projectRows
                              .map((row) => row.project.id)
                              .toSet(),
                        ),
                        for (final layout in projectLayouts)
                          _TimelineProjectHeader(
                            layout: layout,
                            onColor: () => _changeProjectColor(
                              context,
                              layout.row.project,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (event) {
                        _gridFocusNode.requestFocus();
                        _handleTouchZoomDown(event);
                      },
                      onPointerMove: _handleTouchZoomMove,
                      onPointerUp: _handleTouchZoomEnd,
                      onPointerCancel: _handleTouchZoomEnd,
                      onPointerSignal: _handlePointerSignal,
                      onPointerPanZoomStart: (event) {
                        _trackpadZoomStartHourWidth = widget.hourWidth;
                      },
                      onPointerPanZoomUpdate: (event) {
                        final startWidth = _trackpadZoomStartHourWidth;
                        if (startWidth != null && event.scale != 1) {
                          _applyGestureZoom(
                            startWidth,
                            event.scale,
                            event.localPosition.dx,
                          );
                        }
                      },
                      onPointerPanZoomEnd: (_) {
                        _trackpadZoomStartHourWidth = null;
                      },
                      child: SingleChildScrollView(
                        key: const Key('timeline-horizontal-scroll'),
                        controller: _horizontalScrollController,
                        scrollDirection: Axis.horizontal,
                        child: Focus(
                          focusNode: _gridFocusNode,
                          onKeyEvent: _handleGridKeyEvent,
                          child: _timelineSurface(
                            context,
                            start,
                            end,
                            trackWidth,
                            totalHeight,
                            projectLayouts,
                          ),
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
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        event.kind != PointerDeviceKind.mouse ||
        event.scrollDelta.dy == 0 ||
        event.scrollDelta.dx != 0 ||
        !_horizontalScrollController.hasClients) {
      return;
    }
    final position = _horizontalScrollController.position;
    final delta = axisDirectionIsReversed(position.axisDirection)
        ? -event.scrollDelta.dy
        : event.scrollDelta.dy;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (
      resolvedEvent,
    ) {
      position.pointerScroll(delta);
      resolvedEvent.respond(allowPlatformDefault: false);
    });
  }

  KeyEventResult _handleGridKeyEvent(FocusNode node, KeyEvent event) {
    if (!node.hasPrimaryFocus ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => AxisDirection.left,
      LogicalKeyboardKey.arrowRight => AxisDirection.right,
      _ => null,
    };
    if (direction == null || node.context == null) {
      return KeyEventResult.ignored;
    }
    ScrollAction().invoke(ScrollIntent(direction: direction), node.context!);
    return KeyEventResult.handled;
  }

  void _handleTouchZoomDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) {
      return;
    }
    _touchZoomPointers[event.pointer] = event.localPosition;
    _resetTouchZoomStart();
  }

  void _handleTouchZoomMove(PointerMoveEvent event) {
    if (!_touchZoomPointers.containsKey(event.pointer)) {
      return;
    }
    _touchZoomPointers[event.pointer] = event.localPosition;
    if (_touchZoomPointers.length != 2 || _touchZoomStartDistance == null) {
      return;
    }
    final positions = _touchZoomPointers.values.toList(growable: false);
    final focalPoint = (positions[0] + positions[1]) / 2;
    _applyGestureZoom(
      _touchZoomStartHourWidth!,
      (positions[0] - positions[1]).distance / _touchZoomStartDistance!,
      focalPoint.dx,
      anchorMinutes: _touchZoomAnchorMinutes,
    );
  }

  void _handleTouchZoomEnd(PointerEvent event) {
    if (_touchZoomPointers.remove(event.pointer) != null) {
      _resetTouchZoomStart();
    }
  }

  void _resetTouchZoomStart() {
    _touchZoomStartDistance = null;
    _touchZoomAnchorMinutes = null;
    _touchZoomStartHourWidth = null;
    if (_touchZoomPointers.length != 2) {
      return;
    }
    final positions = _touchZoomPointers.values.toList(growable: false);
    _touchZoomStartDistance = (positions[0] - positions[1]).distance;
    _touchZoomStartHourWidth = widget.hourWidth;
    final focalPoint = (positions[0] + positions[1]) / 2;
    _touchZoomAnchorMinutes =
        widget.visibleHours.startMinutes +
        (_horizontalScrollController.offset + focalPoint.dx) / _pixelsPerMinute;
  }

  void _applyGestureZoom(
    int startWidth,
    double scale,
    double anchor, {
    double? anchorMinutes,
  }) {
    if (!scale.isFinite || scale <= 0) {
      return;
    }
    final currentWidth = ref.read(timelineHourWidthProvider);
    final scaledWidth = startWidth * scale;
    var targetWidth = currentWidth;
    var targetDistance = (currentWidth - scaledWidth).abs();
    for (final width in timelineHourWidthLevels) {
      final distance = (width - scaledWidth).abs();
      if (distance < targetDistance) {
        targetWidth = width;
        targetDistance = distance;
      }
    }
    if (targetWidth == currentWidth) {
      return;
    }
    _pendingGestureZoom = (
      targetWidth,
      anchor,
      anchorMinutes ??
          widget.visibleHours.startMinutes +
              (_horizontalScrollController.offset + anchor) / _pixelsPerMinute,
    );
    unawaited(
      ref.read(timelineHourWidthProvider.notifier).setHourWidth(targetWidth),
    );
  }

  List<_ProjectTimelineLayout> _projectLayouts() {
    var top = _timeRulerHeight;
    return [
      for (final row in widget.projectRows)
        (() {
          final taskLayouts = _layoutTimedTasks(
            widget.tasksByProject[row.project.id] ?? const <TaskItem>[],
          );
          final laneCount = taskLayouts.fold<int>(
            1,
            (count, layout) => math.max(count, layout.laneCount),
          );
          final layout = _ProjectTimelineLayout(
            row: row,
            tasks: taskLayouts,
            top: top,
            height: laneCount * _laneHeight,
          );
          top = layout.bottom;
          return layout;
        })(),
    ];
  }

  Widget _timelineSurface(
    BuildContext context,
    int start,
    int end,
    double width,
    double height,
    List<_ProjectTimelineLayout> projectLayouts,
  ) {
    final colors = context.appColors;
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          widget.tasksById.containsKey(details.data),
      onAcceptWithDetails: (details) {
        final task = widget.tasksById[details.data];
        final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
        if (task == null || box == null) {
          return;
        }
        final local = box.globalToLocal(details.offset);
        final projectLayout = _projectLayoutAt(projectLayouts, local.dy);
        if (projectLayout == null) {
          return;
        }
        final targetMinutes = _floorSnapMinutes(
          start + (local.dx / _pixelsPerMinute).floor(),
        );
        unawaited(
          _moveTaskToMinutes(
            context,
            ref,
            task,
            targetMinutes,
            projectLayout.row.project.id,
          ),
        );
      },
      builder: (context, candidateData, rejectedData) => SizedBox(
        key: _gridKey,
        width: width,
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: ColoredBox(color: colors.surface)),
            for (var minute = start; minute <= end; minute += 60)
              Positioned(
                key: Key('timeline-hour-line-$minute'),
                left: (minute - start) * _pixelsPerMinute,
                top: _timeRulerHeight,
                bottom: 0,
                width: 1,
                child: ColoredBox(color: colors.border),
              ),
            for (
              var minute = start;
              minute < end;
              minute += timelineSnapMinutes
            )
              if (minute % 60 != 0)
                Positioned(
                  key: Key('timeline-quarter-tick-$minute'),
                  left: (minute - start) * _pixelsPerMinute,
                  top: _timeRulerHeight - 8,
                  width: 1,
                  height: 8,
                  child: ColoredBox(
                    color: colors.border.withValues(alpha: 0.55),
                  ),
                ),
            for (final layout in projectLayouts)
              Positioned(
                top: layout.top,
                left: 0,
                right: 0,
                height: 1,
                child: ColoredBox(color: colors.border.withValues(alpha: 0.55)),
              ),
            for (final layout in projectLayouts)
              for (
                var minute = start;
                minute < end;
                minute += timelineSnapMinutes
              )
                Positioned(
                  key: Key('timeline-slot-${layout.row.project.id}-$minute'),
                  left: (minute - start) * _pixelsPerMinute,
                  top: layout.top,
                  width: timelineSnapMinutes * _pixelsPerMinute,
                  height: layout.height,
                  child: DragTarget<String>(
                    onWillAcceptWithDetails: (details) =>
                        widget.tasksById.containsKey(details.data),
                    onAcceptWithDetails: (details) {
                      final task = widget.tasksById[details.data];
                      if (task != null) {
                        unawaited(
                          _moveTaskToMinutes(
                            context,
                            ref,
                            task,
                            minute,
                            layout.row.project.id,
                          ),
                        );
                      }
                    },
                    builder: (context, candidates, rejectedData) =>
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() {
                            _addingAtMinutes = minute;
                            _addingProjectId = layout.row.project.id;
                          }),
                          child: ColoredBox(
                            color: candidates.isEmpty
                                ? Colors.transparent
                                : colors.accentTint,
                          ),
                        ),
                  ),
                ),
            for (var minute = start; minute <= end; minute += 60)
              Positioned(
                top: 7,
                left: math.max(0, (minute - start) * _pixelsPerMinute + 6),
                width: 64,
                child: Text(
                  _formatMinutes(minute),
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: colors.mutedText),
                ),
              ),
            if (_addingAtMinutes != null && _addingProjectId != null)
              _positionedInlineAdd(context, start, width, projectLayouts),
            for (final projectLayout in projectLayouts)
              for (final taskLayout in projectLayout.tasks)
                _positionedTimedBlock(
                  context,
                  projectLayout,
                  taskLayout,
                  start,
                  end,
                ),
            ..._currentTimeIndicator(context, start, end),
          ],
        ),
      ),
    );
  }

  _ProjectTimelineLayout? _projectLayoutAt(
    List<_ProjectTimelineLayout> layouts,
    double y,
  ) {
    for (final layout in layouts) {
      if (y >= layout.top && y < layout.bottom) {
        return layout;
      }
    }
    return null;
  }

  Widget _positionedInlineAdd(
    BuildContext context,
    int visibleStart,
    double trackWidth,
    List<_ProjectTimelineLayout> layouts,
  ) {
    final projectLayout = layouts.where(
      (layout) => layout.row.project.id == _addingProjectId,
    );
    if (projectLayout.isEmpty) {
      return const SizedBox.shrink();
    }
    final rawLeft =
        (_addingAtMinutes! - visibleStart) * _pixelsPerMinute + _blockGap;
    final fieldWidth = math.min(
      _inlineAddWidth,
      math.max(120.0, trackWidth - 16),
    );
    final maxLeft = math.max(8.0, trackWidth - fieldWidth - 8);
    final left = rawLeft.clamp(8.0, maxLeft).toDouble();
    return Positioned(
      top: projectLayout.first.top + 8,
      left: left,
      width: fieldWidth,
      child: _InlineAddField(
        key: const Key('timeline-inline-add-timed'),
        hintText: context.l10n.timelineAddTimedHint(
          _formatMinutes(_addingAtMinutes!),
        ),
        onCancel: () => setState(() {
          _addingAtMinutes = null;
          _addingProjectId = null;
        }),
        onSubmit: (input) async {
          final schedule = _timedScheduleFor(
            widget.day,
            _addingAtMinutes!,
            _defaultTimedTaskDuration,
          );
          final taskId = await ref
              .read(quickAddServiceProvider)
              .createTask(
                input,
                projectId: _addingProjectId,
                defaultSchedule: schedule,
              );
          if (mounted) {
            TaskMotionScope.maybeOf(this.context)?.created({taskId});
            await playHaptic(AppHapticCue.light);
            setState(() {
              _addingAtMinutes = null;
              _addingProjectId = null;
            });
          }
        },
      ),
    );
  }

  Widget _positionedTimedBlock(
    BuildContext context,
    _ProjectTimelineLayout projectLayout,
    _TimedTaskLayout layout,
    int visibleStart,
    int visibleEnd,
  ) {
    final task = layout.task;
    final schedule = task.schedule!;
    final startMinutes = _startMinutes(schedule);
    final realEndMinutes = _endMinutes(schedule);
    final previewEnd = _resizingTaskId == task.id
        ? _previewResizeEnd(task, realEndMinutes)
        : realEndMinutes;
    final left = (startMinutes - visibleStart) * _pixelsPerMinute + _blockGap;
    final visibleDuration = math.max(
      timelineSnapMinutes,
      math.min(previewEnd, visibleEnd) - startMinutes,
    );
    final maxVisibleWidth = math.max(
      36.0,
      (visibleEnd - startMinutes) * _pixelsPerMinute - _blockGap,
    );
    final width = math.min(
      math.max(36.0, visibleDuration * _pixelsPerMinute - _blockGap),
      maxVisibleWidth,
    );
    final top = projectLayout.top + layout.lane * _laneHeight + _blockGap;
    final height = _laneHeight - _blockGap * 2;
    return Positioned(
      top: top,
      left: left,
      width: width,
      height: height,
      child: _TimelineCompactTaskBlock(
        task: task,
        project: projectLayout.row.project,
        fillHeight: true,
        onResizeStart: () {
          setState(() {
            _resizingTaskId = task.id;
            _resizeStartEndMinutes = realEndMinutes;
            _resizeDelta = 0;
          });
        },
        onResizeUpdate: (delta) {
          setState(() => _resizeDelta += delta);
        },
        onResizeEnd: () {
          final endMinutes = _previewResizeEnd(task, realEndMinutes);
          setState(() {
            _resizingTaskId = null;
            _resizeStartEndMinutes = null;
            _resizeDelta = 0;
          });
          unawaited(_resizeTask(context, ref, task, endMinutes));
        },
      ),
    );
  }

  int _previewResizeEnd(TaskItem task, int fallbackEndMinutes) {
    final startMinutes = _startMinutes(task.schedule!);
    final base = _resizeStartEndMinutes ?? fallbackEndMinutes;
    return _snapMinutes(
      base + (_resizeDelta / _pixelsPerMinute).round(),
    ).clamp(startMinutes + timelineSnapMinutes, _minutesPerDay);
  }

  Future<void> _moveTaskToMinutes(
    BuildContext context,
    WidgetRef ref,
    TaskItem task,
    int targetMinutes,
    String targetProjectId,
  ) async {
    final existingSchedule = task.schedule;
    final duration = existingSchedule?.isTimed ?? false
        ? existingSchedule!.duration ?? _defaultTimedTaskDuration
        : _defaultTimedTaskDuration;
    final durationMinutes = duration.inMinutes.clamp(
      _minTimedTaskDuration.inMinutes,
      _minutesPerDay,
    );
    final clampedStart = targetMinutes.clamp(
      0,
      _minutesPerDay - durationMinutes,
    );
    final nextSchedule = _preserveRecurrence(
      task,
      _timedScheduleFor(
        widget.day,
        clampedStart,
        Duration(minutes: durationMinutes),
      ),
    );
    if (task.projectId == targetProjectId) {
      await _updateSchedule(context, ref, task, nextSchedule);
      return;
    }
    try {
      await ref
          .read(taskRepositoryProvider)
          .placeTaskOnTimeline(
            task.id,
            schedule: nextSchedule,
            projectId: targetProjectId,
          );
      if (context.mounted) {
        TaskMotionScope.maybeOf(context)?.landed({task.id});
        await playHaptic(AppHapticCue.light);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.taskActionFailedCount(1))),
        );
      }
    }
  }

  Future<void> _resizeTask(
    BuildContext context,
    WidgetRef ref,
    TaskItem task,
    int endMinutes,
  ) async {
    final startMinutes = _startMinutes(task.schedule!);
    final duration = Duration(minutes: endMinutes - startMinutes);
    await _updateSchedule(
      context,
      ref,
      task,
      _timedScheduleFor(widget.day, startMinutes, duration),
    );
  }

  List<Widget> _currentTimeIndicator(
    BuildContext context,
    int visibleStart,
    int visibleEnd,
  ) {
    final now = ref.read(clockProvider).now().toLocal();
    final minute = now.hour * 60 + now.minute;
    if (!_isSameDay(widget.day, now) ||
        minute < visibleStart ||
        minute >= visibleEnd) {
      return const [];
    }
    return [
      Positioned(
        key: const Key('timeline-current-time-indicator'),
        left: (minute - visibleStart) * _pixelsPerMinute,
        top: _timeRulerHeight,
        bottom: 0,
        width: 1,
        child: Semantics(
          label: context.l10n.timelineCurrentTime,
          child: ColoredBox(color: context.appColors.accent),
        ),
      ),
    ];
  }

  Future<void> _changeProjectColor(
    BuildContext context,
    ProjectItem project,
  ) async {
    if (project.id == inboxProjectId) {
      return;
    }
    final color = await showProjectColorPicker(
      context,
      selectedColor: effectiveProjectColor(project),
    );
    if (color == null || !context.mounted) {
      return;
    }
    try {
      await ref
          .read(projectRepositoryProvider)
          .updateProject(project.id, UpdateProjectPatch(color: color));
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.couldNotUpdateProject(error))),
        );
      }
    }
  }
}

class _ProjectTimelineLayout {
  const _ProjectTimelineLayout({
    required this.row,
    required this.tasks,
    required this.top,
    required this.height,
  });

  final TimelineProjectRow row;
  final List<_TimedTaskLayout> tasks;
  final double top;
  final double height;

  double get bottom => top + height;
}

class _ProjectColumnHeader extends ConsumerWidget {
  const _ProjectColumnHeader({
    required this.projects,
    required this.visibleProjectIds,
  });

  final List<ProjectItem> projects;
  final Set<String> visibleProjectIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: _timeRulerHeight,
      child: Row(
        children: [
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.navProjects,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            key: const Key('timeline-project-menu'),
            tooltip: context.l10n.timelineProjectsMenu,
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => _TimelineProjectMenuDialog(
                projects: projects,
                visibleProjectIds: visibleProjectIds,
              ),
            ),
            icon: const Icon(Icons.tune, size: 18),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _TimelineProjectHeader extends ConsumerWidget {
  const _TimelineProjectHeader({required this.layout, required this.onColor});

  final _ProjectTimelineLayout layout;
  final VoidCallback onColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = layout.row.project;
    final collapsed = ref.watch(
      timelineCollapsedProjectIdsProvider.select(
        (ids) => ids.contains(project.id),
      ),
    );
    final projectColor = projectColorValue(effectiveProjectColor(project));
    return Container(
      key: Key('timeline-project-row-${project.id}'),
      height: layout.height,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: context.appColors.border.withValues(alpha: 0.55),
          ),
          left: BorderSide(color: projectColor, width: 3),
        ),
      ),
      padding: EdgeInsets.only(
        left: math.min(24, layout.row.depth * 12).toDouble(),
        right: 6,
      ),
      child: Row(
        children: [
          if (layout.row.hasVisibleChildren)
            IconButton(
              key: Key('timeline-project-collapse-${project.id}'),
              tooltip: collapsed
                  ? context.l10n.timelineExpandProject
                  : context.l10n.timelineCollapseProject,
              onPressed: () => unawaited(
                ref
                    .read(timelineCollapsedProjectIdsProvider.notifier)
                    .toggle(project.id),
              ),
              icon: Icon(
                collapsed ? Icons.chevron_right : Icons.expand_more,
                size: 18,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 32),
            )
          else
            const SizedBox(width: 28),
          ProjectColorSwatch(
            key: Key('timeline-project-color-${project.id}'),
            color: effectiveProjectColor(project),
            onPressed: project.id == inboxProjectId ? null : onColor,
            size: 10,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              project.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineProjectMenuDialog extends ConsumerWidget {
  const _TimelineProjectMenuDialog({
    required this.projects,
    required this.visibleProjectIds,
  });

  final List<ProjectItem> projects;
  final Set<String> visibleProjectIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final temporary = ref.watch(timelineTemporarilyVisibleProjectIdsProvider);
    final active =
        projects
            .where(
              (project) =>
                  project.id != inboxProjectId &&
                  !project.isArchived &&
                  !project.isDeleted,
            )
            .toList()
          ..sort((a, b) => a.orderKey.compareTo(b.orderKey));
    return AlertDialog(
      title: Text(context.l10n.navProjects),
      content: SizedBox(
        width: 420,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final project in active)
              ListTile(
                leading: ProjectColorSwatch(
                  color: effectiveProjectColor(project),
                  size: 16,
                ),
                title: Text(project.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: Key('timeline-project-menu-toggle-${project.id}'),
                      tooltip:
                          visibleProjectIds.contains(project.id) ||
                              temporary.contains(project.id)
                          ? context.l10n.timelineHideProject
                          : context.l10n.timelineShowProject,
                      onPressed:
                          visibleProjectIds.contains(project.id) &&
                              !temporary.contains(project.id)
                          ? null
                          : () => ref
                                .read(
                                  timelineTemporarilyVisibleProjectIdsProvider
                                      .notifier,
                                )
                                .toggle(project.id),
                      icon: Icon(
                        visibleProjectIds.contains(project.id) ||
                                temporary.contains(project.id)
                            ? Icons.visibility
                            : Icons.visibility_outlined,
                      ),
                    ),
                    IconButton(
                      key: Key('timeline-project-menu-favorite-${project.id}'),
                      tooltip: project.isFavorite
                          ? context.l10n.removeProjectFromFavorites
                          : context.l10n.addProjectToFavorites,
                      onPressed: () =>
                          unawaited(_toggleFavorite(context, ref, project)),
                      icon: Icon(
                        project.isFavorite ? Icons.star : Icons.star_border,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.commonClose),
        ),
      ],
    );
  }

  Future<void> _toggleFavorite(
    BuildContext context,
    WidgetRef ref,
    ProjectItem project,
  ) async {
    try {
      await ref
          .read(projectRepositoryProvider)
          .updateProject(
            project.id,
            UpdateProjectPatch(isFavorite: !project.isFavorite),
          );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.couldNotUpdateProject(error))),
        );
      }
    }
  }
}

class _TimelineCompactTaskBlock extends ConsumerWidget {
  const _TimelineCompactTaskBlock({
    required this.task,
    this.project,
    this.showProjectName = false,
    this.fillHeight = false,
    this.allowResize = true,
    this.onResizeStart,
    this.onResizeUpdate,
    this.onResizeEnd,
  });

  final TaskItem task;
  final ProjectItem? project;
  final bool showProjectName;
  final bool fillHeight;
  final bool allowResize;
  final VoidCallback? onResizeStart;
  final ValueChanged<double>? onResizeUpdate;
  final VoidCallback? onResizeEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final priorityColor = _priorityColor(task.priority, colors);
    final projectHex = project == null
        ? inboxProjectColorHex
        : effectiveProjectColor(project!);
    final projectColor = projectColorValue(projectHex);
    final schedule = task.schedule;
    final rawTimeLabel = schedule == null
        ? null
        : schedule.isTimed
        ? '${_formatMinutes(_startMinutes(schedule))}-${_formatMinutes(_endMinutes(schedule))}'
        : context.l10n.timelineAllDay;
    final timeLabel = showProjectName && project != null
        ? '${project!.name} · ${rawTimeLabel ?? ''}'
        : rawTimeLabel;
    final block = Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('timeline-task-${task.id}'),
        onTap: () => context.push('/task/${task.id}'),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: fillHeight
              ? const BoxConstraints.expand()
              : const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.fromLTRB(11, 6, 8, 6),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: priorityColor.withValues(alpha: 0.7)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: projectColor,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(8),
                    ),
                  ),
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (constraints.maxWidth >= 72) ...[
                      SizedBox.square(
                        dimension: 28,
                        child: TaskCompletionControl(
                          taskId: task.id,
                          isCompleted: task.isCompleted,
                          color: priorityColor,
                          fillColor: colors.accentFill,
                          onPressed: () {
                            if (task.isCompleted) {
                              unawaited(() async {
                                await ref
                                    .read(taskRepositoryProvider)
                                    .uncompleteTask(task.id);
                                final reopened = await ref
                                    .read(taskRepositoryProvider)
                                    .watchTask(task.id)
                                    .first;
                                if (context.mounted && reopened != null) {
                                  TaskMotionScope.maybeOf(
                                    context,
                                  )?.reopened([reopened]);
                                  await playHaptic(AppHapticCue.light);
                                }
                              }());
                            } else {
                              unawaited(
                                completeTaskWithUndoFeedback(
                                  context,
                                  ref,
                                  task.id,
                                ).then<void>((_) {}),
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            task.content,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colors.primaryText,
                                ),
                          ),
                          if (timeLabel != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              timeLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: colors.mutedText),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (allowResize && onResizeStart != null && onResizeEnd != null)
                Positioned(
                  key: Key('timeline-resize-${task.id}'),
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 12,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (_) => onResizeStart?.call(),
                    onHorizontalDragUpdate: (details) =>
                        onResizeUpdate?.call(details.delta.dx),
                    onHorizontalDragEnd: (_) => onResizeEnd?.call(),
                    child: Center(
                      child: Container(
                        width: 3,
                        height: 32,
                        decoration: BoxDecoration(
                          color: priorityColor.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return TaskMotionItem(
      taskId: task.id,
      child: _TimelineDragSource(task: task, child: block),
    );
  }
}

class _TimelineDragSource extends StatelessWidget {
  const _TimelineDragSource({required this.task, required this.child});

  final TaskItem task;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final feedback = Transform.scale(
      scale: 1.025,
      child: Material(
        color: Colors.transparent,
        child: SizedBox(width: 260, height: 64, child: child),
      ),
    );
    final childWhenDragging = Opacity(opacity: 0.35, child: child);
    if (_usesImmediateTaskDrag(defaultTargetPlatform)) {
      return Draggable<String>(
        data: task.id,
        feedback: feedback,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        childWhenDragging: childWhenDragging,
        child: child,
      );
    }
    return LongPressDraggable<String>(
      data: task.id,
      feedback: feedback,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      childWhenDragging: childWhenDragging,
      child: child,
    );
  }
}

class _InlineAddField extends StatefulWidget {
  const _InlineAddField({
    super.key,
    required this.hintText,
    required this.onSubmit,
    required this.onCancel,
  });

  final String hintText;
  final Future<void> Function(String input) onSubmit;
  final VoidCallback onCancel;

  @override
  State<_InlineAddField> createState() => _InlineAddFieldState();
}

class _InlineAddFieldState extends State<_InlineAddField> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.appColors.surface,
          border: Border.all(color: context.appColors.accent),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              IconButton(
                tooltip: context.l10n.commonCancel,
                onPressed: _busy ? null : widget.onCancel,
                icon: const Icon(Icons.close),
              ),
              IconButton.filledTonal(
                tooltip: context.l10n.commonAdd,
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final input = _controller.text.trim();
    if (input.isEmpty || _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onSubmit(input);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.taskCreateFailed)));
      setState(() => _busy = false);
    }
  }
}

class _TimedTaskLayout {
  const _TimedTaskLayout({
    required this.task,
    required this.lane,
    required this.laneCount,
  });

  final TaskItem task;
  final int lane;
  final int laneCount;
}

List<_TimedTaskLayout> _layoutTimedTasks(List<TaskItem> tasks) {
  final sorted = [...tasks]..sort(_compareTimedTaskOrder);
  final layouts = <_TimedTaskLayout>[];
  var index = 0;
  while (index < sorted.length) {
    final cluster = <TaskItem>[];
    var clusterEnd = _endMinutes(sorted[index].schedule!);
    do {
      final task = sorted[index];
      cluster.add(task);
      clusterEnd = math.max(clusterEnd, _endMinutes(task.schedule!));
      index++;
    } while (index < sorted.length &&
        _startMinutes(sorted[index].schedule!) < clusterEnd);

    final laneEnds = <int>[];
    final assigned = <TaskItem, int>{};
    for (final task in cluster) {
      final start = _startMinutes(task.schedule!);
      var lane = laneEnds.indexWhere((end) => end <= start);
      if (lane == -1) {
        lane = laneEnds.length;
        laneEnds.add(0);
      }
      laneEnds[lane] = _endMinutes(task.schedule!);
      assigned[task] = lane;
    }
    final laneCount = math.max(1, laneEnds.length);
    for (final task in cluster) {
      layouts.add(
        _TimedTaskLayout(
          task: task,
          lane: assigned[task]!,
          laneCount: laneCount,
        ),
      );
    }
  }
  return layouts;
}

Future<void> _updateSchedule(
  BuildContext context,
  WidgetRef ref,
  TaskItem task,
  TaskSchedule schedule,
) async {
  try {
    final nextSchedule = _preserveRecurrence(task, schedule);
    await ref
        .read(taskRepositoryProvider)
        .updateTask(task.id, UpdateTaskPatch(schedule: nextSchedule));
    if (context.mounted) {
      TaskMotionScope.maybeOf(context)?.landed({task.id});
      await playHaptic(AppHapticCue.light);
    }
  } catch (_) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.taskActionFailedCount(1))),
    );
  }
}

TaskSchedule _preserveRecurrence(TaskItem task, TaskSchedule schedule) {
  final recurrence = task.schedule?.recurrence;
  if (recurrence != null) {
    return schedule.withRecurrence(recurrence);
  }
  return schedule.withRecurrenceSeriesId(task.schedule?.recurrenceSeriesKey);
}

TaskSchedule _timedScheduleFor(
  DateTime day,
  int startMinutes,
  Duration duration,
) {
  final start = _dateOnly(day).add(Duration(minutes: startMinutes));
  return TaskSchedule.timed(start: start, end: start.add(duration));
}

Color _priorityColor(int priority, AppThemePalette colors) {
  return switch (priority) {
    1 => colors.accent,
    2 => colors.warning,
    3 => colors.info,
    _ => colors.border,
  };
}

int _compareTimelineTaskOrder(TaskItem a, TaskItem b) {
  final dayOrderCompare = (a.dayOrder ?? 999999).compareTo(
    b.dayOrder ?? 999999,
  );
  if (dayOrderCompare != 0) {
    return dayOrderCompare;
  }
  return a.orderKey.compareTo(b.orderKey);
}

int _compareTimedTaskOrder(TaskItem a, TaskItem b) {
  final scheduleCompare = _startMinutes(
    a.schedule!,
  ).compareTo(_startMinutes(b.schedule!));
  if (scheduleCompare != 0) {
    return scheduleCompare;
  }
  return _compareTimelineTaskOrder(a, b);
}

int _startMinutes(TaskSchedule schedule) {
  final start = schedule.start!.toLocal();
  return start.hour * 60 + start.minute;
}

int _endMinutes(TaskSchedule schedule) {
  final end = schedule.end!.toLocal();
  if (!_isSameDay(schedule.start!.toLocal(), end)) {
    return _minutesPerDay;
  }
  return end.hour * 60 + end.minute;
}

int _snapMinutes(int minutes) {
  return (minutes / timelineSnapMinutes).round() * timelineSnapMinutes;
}

int _floorSnapMinutes(int minutes) {
  return (minutes ~/ timelineSnapMinutes) * timelineSnapMinutes;
}

String _formatMinutes(int minutes) {
  final clamped = minutes.clamp(0, _minutesPerDay);
  final hour = clamped ~/ 60;
  final minute = clamped % 60;
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

String _formatRouteDate(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool _usesImmediateTaskDrag(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => false,
  };
}

final _timeOptions = [
  for (
    var minutes = 0;
    minutes <= _minutesPerDay;
    minutes += timelineSnapMinutes
  )
    minutes,
];
