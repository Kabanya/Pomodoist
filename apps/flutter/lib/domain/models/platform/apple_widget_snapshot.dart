import 'package:pomodoist/domain/models/habits/habit_models.dart';
import 'package:pomodoist/domain/models/productivity/productivity_models.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

class AppleWidgetSnapshot {
  AppleWidgetSnapshot({
    required this.day,
    required Iterable<TaskItem> tasks,
    required Iterable<TaskItem> agenda,
    required Iterable<AppleWidgetHabit> habits,
    required this.totalHabits,
    required this.completedHabits,
    required this.completedTasks,
    required Iterable<ProductivityDaySummary> week,
    this.focusTaskTitle,
  }) : tasks = List.unmodifiable(tasks),
       agenda = List.unmodifiable(agenda),
       habits = List.unmodifiable(habits),
       week = List.unmodifiable(week);

  final DateTime day;
  final String? focusTaskTitle;
  final List<TaskItem> tasks, agenda;
  final List<AppleWidgetHabit> habits;
  final int totalHabits, completedHabits, completedTasks;
  final List<ProductivityDaySummary> week;
}

class AppleWidgetHabit {
  const AppleWidgetHabit(this.habit, this.count, this.target);
  final Habit habit;
  final int count, target;
  bool get completed => count >= target;
}

AppleWidgetSnapshot buildAppleWidgetSnapshot({
  required DateTime now,
  required Iterable<TaskItem> tasks,
  required Iterable<Habit> habits,
  required Iterable<HabitCheckIn> checkIns,
  required ProductivitySummary productivity,
  String? focusTaskTitle,
}) {
  final day = habitDate(now.toLocal());
  final pending = tasks
      .where(
        (task) => task.scopeId == null && !task.isDeleted && !task.isCompleted,
      )
      .toList();
  final agenda =
      pending.where((task) => task.schedule?.displayDate == day).toList()..sort(
        (a, b) => a.schedule!.occurrenceStartLocal.compareTo(
          b.schedule!.occurrenceStartLocal,
        ),
      );
  final habitRows = [
    for (final habit in habits)
      if (habit.isScheduledOn(day))
        AppleWidgetHabit(
          habit,
          habitPeriodCounts(
            habit,
            day,
            checkIns,
          ).values.fold(0, (a, b) => a + b),
          habit.scheduleFor(day)!.targetPerDay,
        ),
  ];
  final monday = DateTime(day.year, day.month, day.day - day.weekday + 1);
  return AppleWidgetSnapshot(
    day: day,
    focusTaskTitle: focusTaskTitle,
    tasks: pending.take(12),
    agenda: agenda.take(12),
    habits: habitRows.take(12),
    totalHabits: habitRows.length,
    completedHabits: habitRows.where((habit) => habit.completed).length,
    completedTasks: productivity.completedTasks,
    week: [
      for (var i = 0; i < 7; i++)
        _widgetDay(
          DateTime(monday.year, monday.month, monday.day + i),
          day,
          productivity.lastSevenDays,
        ),
    ],
  );
}

ProductivityDaySummary _widgetDay(
  DateTime date,
  DateTime today,
  Iterable<ProductivityDaySummary> days,
) {
  if (!date.isAfter(today)) {
    final existing = days
        .where((day) => habitDate(day.localDate) == date)
        .firstOrNull;
    if (existing != null) return existing;
  }
  return ProductivityDaySummary(
    localDate: date,
    completedTasks: 0,
    completedFocusIntervals: 0,
    totalFocusSeconds: 0,
  );
}
