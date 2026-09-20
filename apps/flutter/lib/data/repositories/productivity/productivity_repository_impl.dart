import 'package:pomodoist/utils/result.dart';
import 'package:pomodoist/data/repositories/productivity/productivity_repository.dart';
import 'dart:async';

import 'package:drift/drift.dart';

import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/productivity_local_service.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/productivity/productivity_models.dart';

class DriftProductivityRepository implements ProductivityRepository {
  DriftProductivityRepository(AppDatabase db)
    : _productivity = ProductivityLocalService(db);

  final ProductivityLocalService _productivity;

  @override
  Stream<ProductivitySummary> watchTodaySummary() {
    late final StreamController<ProductivitySummary> controller;
    StreamSubscription<List<TaskRow>>? taskSubscription;
    StreamSubscription<List<FocusIntervalRow>>? intervalSubscription;
    StreamSubscription<List<TaskCompletionRow>>? completionSubscription;
    var listening = false;
    var revision = 0;

    Future<void> emit() async {
      final current = ++revision;
      try {
        final summary = await _calculateSummary(DateTime.now());
        if (listening && current == revision && !controller.isClosed) {
          controller.add(summary);
        }
      } on Object catch (error, stackTrace) {
        if (listening && current == revision && !controller.isClosed) {
          controller.addError(error, stackTrace);
        }
      }
    }

    controller = StreamController<ProductivitySummary>(
      onListen: () {
        listening = true;
        taskSubscription = _productivity.watchTasks().listen(
          (_) => unawaited(emit()),
          onError: controller.addError,
        );
        intervalSubscription = _productivity.watchFocusIntervals().listen(
          (_) => unawaited(emit()),
          onError: controller.addError,
        );
        completionSubscription = _productivity.watchTaskCompletions().listen(
          (_) => unawaited(emit()),
          onError: controller.addError,
        );
        unawaited(emit());
      },
      onCancel: () async {
        listening = false;
        revision++;
        await taskSubscription?.cancel();
        await intervalSubscription?.cancel();
        await completionSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<Result<void>> recalculateDailyStats(DateTime localDate) =>
      Result.capture<void>(() async {
        final summary = await _calculateSummary(localDate);
        final dateKey = _dateKey(localDate.toLocal());
        final now = DateTime.now().toUtc();
        await _productivity.insertDailyStats(
          FocusDailyStatsCompanion.insert(
            id: '${localUserId}_$dateKey',
            userId: localUserId,
            localDate: dateKey,
            completedTasks: Value(summary.completedTasks),
            completedFocusIntervals: Value(summary.completedFocusIntervals),
            totalFocusSeconds: Value(summary.totalFocusSeconds),
            plannedFocusIntervals: Value(summary.plannedFocusIntervals),
            calculatedAt: now,
          ),
        );
      });

  Future<ProductivitySummary> _calculateSummary(DateTime localDate) async {
    final tasks = await _productivity.activeTasks();
    final completions = await _productivity.allTaskCompletions();
    final intervals = await _productivity.activeFocusIntervals();
    return evaluateProductivitySummary(
      reportDate: localDate,
      tasks: tasks,
      completions: completions,
      intervals: intervals,
    );
  }
}

ProductivitySummary evaluateProductivitySummary({
  required DateTime reportDate,
  required List<TaskRow> tasks,
  required List<TaskCompletionRow> completions,
  required List<FocusIntervalRow> intervals,
  DateTime Function(DateTime value)? localize,
  DateTime? now,
}) {
  final toLocal = localize ?? (DateTime value) => value.toLocal();
  final day = DateTime(reportDate.year, reportDate.month, reportDate.day);
  final activeTasks = tasks.where((task) => !task.isDeleted).toList();
  final activeIntervals = intervals
      .where((interval) => !interval.isDeleted)
      .toList();
  final days = lastSevenProductivityDays(day);
  final daily = _dailySummaries(
    days,
    completions,
    activeIntervals,
    toLocal,
    now ?? DateTime.now().toUtc(),
  );
  final openTasks = activeTasks
      .where((task) => task.status != 'completed')
      .toList();
  final plannedFocusIntervals = openTasks
      .where((task) {
        final due = _dueDate(task.dueJson, toLocal);
        return due != null && !due.isAfter(day);
      })
      .fold<int>(0, (sum, task) => sum + (task.estimatedFocusIntervals ?? 0));
  final completedWork = activeIntervals
      .where(
        (interval) => interval.type == 'work' && interval.status == 'completed',
      )
      .length;
  final today = daily[_dateKey(day)]!;

  return ProductivitySummary(
    completedTasks: today.completedTasks,
    completedFocusIntervals: today.completedFocusIntervals,
    totalFocusSeconds: today.totalFocusSeconds,
    plannedFocusIntervals: plannedFocusIntervals,
    openTasks: openTasks.length,
    allTimeCompletedTasks: completions.length,
    allTimeCompletedFocusIntervals: completedWork,
    lastSevenDays: [for (final date in days) daily[_dateKey(date)]!],
  );
}

Map<String, ProductivityDaySummary> _dailySummaries(
  List<DateTime> days,
  List<TaskCompletionRow> completions,
  List<FocusIntervalRow> intervals,
  DateTime Function(DateTime value) localize,
  DateTime now,
) {
  final start = days.first;
  final today = days.last;
  final tasksByDay = <String, int>{};
  final intervalsByDay = <String, int>{};
  final secondsByDay = <String, int>{};

  bool inRange(DateTime date) => !date.isBefore(start) && !date.isAfter(today);

  for (final completion in completions) {
    final day = _dayOnly(localize(completion.completedAt));
    if (!inRange(day)) {
      continue;
    }
    final key = _dateKey(day);
    tasksByDay[key] = (tasksByDay[key] ?? 0) + 1;
  }

  for (final interval in intervals) {
    if (interval.type != 'work' || interval.status != 'completed') {
      continue;
    }
    final day = _dayOnly(localize(interval.startedAt));
    if (!inRange(day)) {
      continue;
    }
    final key = _dateKey(day);
    intervalsByDay[key] = (intervalsByDay[key] ?? 0) + 1;
    secondsByDay[key] =
        (secondsByDay[key] ?? 0) + _actualSeconds(interval, now);
  }

  return {
    for (final day in days)
      _dateKey(day): ProductivityDaySummary(
        localDate: day,
        completedTasks: tasksByDay[_dateKey(day)] ?? 0,
        completedFocusIntervals: intervalsByDay[_dateKey(day)] ?? 0,
        totalFocusSeconds: secondsByDay[_dateKey(day)] ?? 0,
      ),
  };
}

DateTime? _dueDate(
  String? dueJson,
  DateTime Function(DateTime value) localize,
) {
  final schedule = TaskSchedule.fromJsonString(dueJson);
  if (schedule == null) {
    return null;
  }
  return _dayOnly(
    schedule.isAllDay ? schedule.date! : localize(schedule.start!),
  );
}

int _actualSeconds(FocusIntervalRow row, DateTime now) {
  final end = row.completedAt ?? row.stoppedAt ?? now;
  final seconds =
      end.difference(row.startedAt).inSeconds - row.pausedTotalSeconds;
  return seconds < 0 ? 0 : seconds;
}

DateTime _dayOnly(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

List<DateTime> lastSevenProductivityDays(DateTime today) {
  return [
    for (var index = 6; index >= 0; index--)
      DateTime(today.year, today.month, today.day - index),
  ];
}

String _dateKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}
