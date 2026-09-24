import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/settings/preferences_repository.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository.dart';
import 'package:pomodoist/domain/models/tasks/calendar_models.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

export 'package:pomodoist/domain/models/tasks/calendar_models.dart';

const calendarSettingsKey = 'calendar.settings.v1';

final class CalendarState {
  const CalendarState({
    required this.now,
    required this.tasks,
    required this.projects,
    required this.settings,
    required this.settingsLoaded,
    required this.settingsError,
    required this.projectId,
  });

  final DateTime now;
  final AsyncValue<List<TaskItem>> tasks;
  final AsyncValue<List<ProjectItem>> projects;
  final CalendarSettings settings;
  final bool settingsLoaded;
  final Object? settingsError;
  final String? projectId;
}

final calendarViewModelProvider =
    NotifierProvider.autoDispose<CalendarViewModel, CalendarState>(
      CalendarViewModel.new,
    );

class CalendarViewModel extends Notifier<CalendarState> {
  late TaskRepository _tasks;
  late PreferencesRepository _preferences;
  CalendarSettings _settings = CalendarSettings();
  bool _settingsLoaded = false;
  Object? _settingsError;
  Future<void>? _loadFuture;
  Future<void> _saveQueue = Future.value();
  String? _projectId;

  @override
  CalendarState build() {
    _tasks = ref.watch(taskRepositoryProvider);
    _preferences = ref.watch(preferencesRepositoryProvider);
    _loadFuture ??= Future.microtask(_loadSettings);
    return _snapshot();
  }

  CalendarState _snapshot() {
    final projects = ref.watch(projectsProvider);
    if (_projectId != null &&
        projects.hasValue &&
        !projects.requireValue.any(
          (project) => project.id == _projectId && !project.isDeleted,
        )) {
      _projectId = null;
    }
    return CalendarState(
      now:
          (ref.watch(
                    taskTimeTickerProvider.select((tick) {
                      final value = tick.value?.toLocal();
                      return value == null
                          ? null
                          : DateTime(
                              value.year,
                              value.month,
                              value.day,
                              value.hour,
                              value.minute,
                            );
                    }),
                  ) ??
                  ref.read(clockProvider).now())
              .toLocal(),
      tasks: ref.watch(tasksByQueryProvider(const TaskQuery.all())),
      projects: projects,
      settings: _settings,
      settingsLoaded: _settingsLoaded,
      settingsError: _settingsError,
      projectId: _projectId,
    );
  }

  void _publish() {
    if (ref.mounted) state = _snapshot();
  }

  Future<void> _loadSettings({bool reload = false}) async {
    try {
      final values = (await _preferences.read([
        calendarSettingsKey,
      ], reload: reload)).getOrThrow();
      if (!ref.mounted) return;
      _settings = CalendarSettings.fromJsonString(
        values[calendarSettingsKey] as String?,
      );
      _settingsError = null;
    } catch (error) {
      if (!ref.mounted) return;
      _settingsError = error;
    } finally {
      if (ref.mounted) {
        _settingsLoaded = true;
        _publish();
      }
    }
  }

  Future<void> _save(CalendarSettings Function(CalendarSettings) update) async {
    final previous = _saveQueue;
    final completed = Completer<void>();
    _saveQueue = completed.future;
    try {
      await previous;
      await _loadFuture;
      final next = update(_settings);
      (await _preferences.write({
        calendarSettingsKey: next.toJsonString(),
      })).getOrThrow();
      if (ref.mounted) {
        _settings = next;
        _settingsError = null;
        _publish();
      }
    } catch (error) {
      if (ref.mounted) {
        _settingsError = error;
        _publish();
      }
      rethrow;
    } finally {
      completed.complete();
    }
  }

  Future<void> setMode(CalendarMode mode) =>
      _save((settings) => settings.copyWith(mode: mode));

  void setProject(String? projectId) {
    _projectId = projectId;
    _publish();
  }

  Future<void> saveRoutine(String name, List<CalendarPeriod> periods) {
    CalendarSettings.validateRoutine(name, periods);
    return _save(
      (settings) =>
          settings.copyWith(routineName: name.trim(), periods: periods),
    );
  }

  Future<void> retry() async {
    ref.invalidate(tasksByQueryProvider(const TaskQuery.all()));
    ref.invalidate(projectsProvider);
    _settingsLoaded = false;
    _settingsError = null;
    _publish();
    final load = _loadSettings(reload: true);
    _loadFuture = load;
    await load;
  }

  CalendarPresentation presentation(
    DateTime day,
    CalendarMode mode, {
    required int firstWeekday,
  }) => buildCalendarPresentation(
    state.tasks.value ?? const [],
    state.projects.value ?? const [],
    day,
    mode,
    firstWeekday: firstWeekday,
    projectId: _projectId,
  );

  List<CalendarRoutineDay> routineDays(CalendarPresentation presentation) =>
      groupCalendarRoutineDays(presentation, _settings);

  Future<TaskItem> _current(String id, {bool allowCompleted = false}) async {
    final task = await _tasks.watchTask(id).first;
    if (task == null ||
        task.isDeleted ||
        !task.canEdit ||
        (!allowCompleted && task.isCompleted)) {
      throw StateError('Task is unavailable for editing');
    }
    return task;
  }

  Future<void> moveTask(
    String taskId,
    DateTime day, {
    int? minutes,
    bool allDay = false,
  }) async {
    final task = await _current(taskId);
    if (minutes != null && (minutes < 0 || minutes >= 1440)) {
      throw ArgumentError.value(minutes, 'minutes');
    }
    final existing = task.schedule;
    late final TaskSchedule next;
    if (allDay ||
        (minutes == null && (existing == null || existing.isAllDay))) {
      next = TaskSchedule.allDay(
        day,
        recurrence: existing?.recurrence,
        recurrenceSeriesId: existing?.recurrenceSeriesId,
      );
    } else if (minutes == null) {
      next = existing!.moveToDate(day);
    } else {
      final start = DateTime(
        day.year,
        day.month,
        day.day,
        minutes ~/ 60,
        minutes % 60,
      );
      final duration = existing?.isTimed == true
          ? existing!.duration!
          : Duration(
              minutes: ref.read(quickAddDefaultTimedBlockMinutesProvider),
            );
      next = TaskSchedule.timed(
        start: start,
        end: start.add(duration),
        timeZone: existing?.timeZone,
        recurrence: existing?.recurrence,
        recurrenceSeriesId: existing?.recurrenceSeriesId,
      );
    }
    (await _tasks.updateTask(
      taskId,
      UpdateTaskPatch(schedule: next),
    )).getOrThrow();
  }

  Future<void> resizeTask(String taskId, DateTime end) async {
    final task = await _current(taskId);
    final schedule = task.schedule;
    if (schedule == null || !schedule.isTimed)
      throw StateError('Task has no timed schedule');
    final next = TaskSchedule.timed(
      start: schedule.start!,
      end: end,
      timeZone: schedule.timeZone,
      recurrence: schedule.recurrence,
      recurrenceSeriesId: schedule.recurrenceSeriesId,
    );
    (await _tasks.updateTask(
      taskId,
      UpdateTaskPatch(schedule: next),
    )).getOrThrow();
  }

  Future<void> unscheduleTask(String taskId) async {
    await _current(taskId);
    (await _tasks.updateTask(
      taskId,
      UpdateTaskPatch(clearSchedule: true),
    )).getOrThrow();
  }

  Future<TaskItem?> completeTask(String taskId) async {
    await _current(taskId);
    (await _tasks.completeTask(taskId)).getOrThrow();
    return _tasks.watchTask(taskId).first;
  }

  Future<TaskItem?> reopenTask(String taskId) async {
    await _current(taskId, allowCompleted: true);
    (await _tasks.uncompleteTask(taskId)).getOrThrow();
    return _tasks.watchTask(taskId).first;
  }
}

List<CalendarRoutineDay> groupCalendarRoutineDays(
  CalendarPresentation presentation,
  CalendarSettings settings,
) {
  return [
    for (final day in presentation.days)
      () {
        final buckets = [for (final _ in settings.periods) <TaskItem>[]];
        final outside = <TaskItem>[];
        for (final event in day.events) {
          final task = event.task;
          final start = task.schedule!.start!.toLocal();
          if (start.year != day.date.year ||
              start.month != day.date.month ||
              start.day != day.date.day) {
            outside.add(task);
            continue;
          }
          final minute = start.hour * 60 + start.minute;
          final index = settings.periods.indexWhere(
            (period) =>
                minute >= period.startMinutes && minute < period.endMinutes,
          );
          if (index < 0) {
            outside.add(task);
          } else {
            buckets[index].add(task);
          }
        }
        return CalendarRoutineDay(day: day, periods: buckets, outside: outside);
      }(),
  ];
}

CalendarPresentation buildCalendarPresentation(
  Iterable<TaskItem> tasks,
  Iterable<ProjectItem> projects,
  DateTime day,
  CalendarMode mode, {
  required int firstWeekday,
  String? projectId,
}) {
  if (firstWeekday < DateTime.monday || firstWeekday > DateTime.sunday) {
    throw ArgumentError.value(firstWeekday, 'firstWeekday');
  }
  final chosen = DateTime(day.year, day.month, day.day);
  DateTime start;
  int count;
  switch (mode) {
    case CalendarMode.day:
      start = chosen;
      count = 1;
    case CalendarMode.week:
    case CalendarMode.routine:
      start = DateTime(
        chosen.year,
        chosen.month,
        chosen.day - (chosen.weekday - firstWeekday + 7) % 7,
      );
      count = 7;
    case CalendarMode.month:
      final first = DateTime(chosen.year, chosen.month);
      start = DateTime(
        first.year,
        first.month,
        first.day - (first.weekday - firstWeekday + 7) % 7,
      );
      count = 42;
  }
  final visible = tasks
      .where(
        (task) =>
            !task.isDeleted &&
            !task.isCompleted &&
            (projectId == null || task.projectId == projectId),
      )
      .toList();
  final schedules = [for (final task in visible) (task, task.schedule)];
  final unscheduled = [
    for (final (task, schedule) in schedules)
      if (schedule == null) task,
  ]..sort(_compareTasks);
  final days = <CalendarDay>[];
  for (var offset = 0; offset < count; offset++) {
    final date = DateTime(start.year, start.month, start.day + offset);
    final nextDate = DateTime(date.year, date.month, date.day + 1);
    final allDay = <TaskItem>[];
    final segments = <_Segment>[];
    for (final (task, schedule) in schedules) {
      if (schedule == null) continue;
      if (schedule.isAllDay) {
        final due = schedule.date!;
        if (due.year == date.year &&
            due.month == date.month &&
            due.day == date.day)
          allDay.add(task);
        continue;
      }
      final taskStart = schedule.start!.toLocal();
      final taskEnd = schedule.end!.toLocal();
      if (!taskStart.isBefore(nextDate) || !taskEnd.isAfter(date)) continue;
      final clippedStart = taskStart.isBefore(date) ? date : taskStart;
      final clippedEnd = taskEnd.isAfter(nextDate) ? nextDate : taskEnd;
      segments.add(
        _Segment(
          task,
          clippedStart.hour * 60 + clippedStart.minute,
          clippedEnd == nextDate
              ? 1440
              : clippedEnd.hour * 60 +
                    clippedEnd.minute +
                    (clippedEnd.second != 0 ||
                            clippedEnd.millisecond != 0 ||
                            clippedEnd.microsecond != 0
                        ? 1
                        : 0),
          taskStart.isBefore(date),
          taskEnd.isAfter(nextDate),
        ),
      );
    }
    allDay.sort(_compareTasks);
    segments.sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : _compareTasks(a.task, b.task);
    });
    final events = <CalendarEvent>[];
    var index = 0;
    while (index < segments.length) {
      final component = <(_Segment, int)>[];
      final laneEnds = <int>[];
      var componentEnd = -1;
      do {
        final segment = segments[index++];
        var lane = laneEnds.indexWhere((end) => end <= segment.start);
        if (lane < 0) {
          lane = laneEnds.length;
          laneEnds.add(segment.end);
        } else {
          laneEnds[lane] = segment.end;
        }
        component.add((segment, lane));
        if (segment.end > componentEnd) componentEnd = segment.end;
      } while (index < segments.length && segments[index].start < componentEnd);
      for (final (segment, lane) in component) {
        events.add(
          CalendarEvent(
            task: segment.task,
            startMinutes: segment.start,
            endMinutes: segment.end,
            lane: lane,
            laneCount: laneEnds.length,
            continuesBefore: segment.before,
            continuesAfter: segment.after,
          ),
        );
      }
    }
    days.add(
      CalendarDay(
        date: date,
        allDay: allDay,
        events: events,
        tasks: [...allDay, for (final event in events) event.task],
      ),
    );
  }
  return CalendarPresentation(
    days: days,
    unscheduled: unscheduled,
    projectsById: {
      for (final project in projects)
        if (!project.isDeleted) project.id: project,
    },
  );
}

int _compareTasks(TaskItem a, TaskItem b) {
  final order = (a.dayOrder ?? 999999).compareTo(b.dayOrder ?? 999999);
  return order != 0 ? order : a.orderKey.compareTo(b.orderKey);
}

final class _Segment {
  const _Segment(this.task, this.start, this.end, this.before, this.after);
  final TaskItem task;
  final int start;
  final int end;
  final bool before;
  final bool after;
}
