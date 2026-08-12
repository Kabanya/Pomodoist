import 'dart:async';

import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../tasks/domain/task_models.dart';
import '../domain/productivity_models.dart';

class DriftProductivityRepository implements ProductivityRepository {
  DriftProductivityRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<ProductivitySummary> watchTodaySummary() {
    late final StreamController<ProductivitySummary> controller;
    StreamSubscription<List<TaskRow>>? taskSubscription;
    StreamSubscription<List<FocusIntervalRow>>? intervalSubscription;
    StreamSubscription<List<TaskCompletionRow>>? completionSubscription;

    Future<void> emit() async {
      if (!controller.isClosed) {
        controller.add(await _calculateSummary(DateTime.now()));
      }
    }

    controller = StreamController<ProductivitySummary>(
      onListen: () {
        taskSubscription = _db.select(_db.tasks).watch().listen((_) => emit());
        intervalSubscription = _db
            .select(_db.focusIntervals)
            .watch()
            .listen((_) => emit());
        completionSubscription = _db
            .select(_db.taskCompletions)
            .watch()
            .listen((_) => emit());
        emit();
      },
      onCancel: () async {
        await taskSubscription?.cancel();
        await intervalSubscription?.cancel();
        await completionSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> recalculateDailyStats(DateTime localDate) async {
    final summary = await _calculateSummary(localDate);
    final dateKey = _dateKey(localDate.toLocal());
    final now = DateTime.now().toUtc();
    await _db
        .into(_db.focusDailyStats)
        .insertOnConflictUpdate(
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
  }

  Future<ProductivitySummary> _calculateSummary(DateTime localDate) async {
    final tasks = await (_db.select(
      _db.tasks,
    )..where((task) => task.isDeleted.equals(false))).get();
    final completions = await _db.select(_db.taskCompletions).get();
    final intervals = await (_db.select(
      _db.focusIntervals,
    )..where((interval) => interval.isDeleted.equals(false))).get();
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
