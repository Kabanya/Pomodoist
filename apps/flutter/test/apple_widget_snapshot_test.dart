import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/habits/habit_models.dart';
import 'package:pomodoist/domain/models/platform/apple_widget_snapshot.dart';
import 'package:pomodoist/domain/models/productivity/productivity_models.dart';

void main() {
  test('calendar week excludes the previous week and future focus totals', () {
    for (final today in [
      DateTime(2026, 5, 1),
      DateTime(2026, 5, 3),
      DateTime(2026, 5, 4),
    ]) {
      final snapshot = buildAppleWidgetSnapshot(
        now: today,
        tasks: [],
        habits: [],
        checkIns: [],
        productivity: _summary([
          for (var offset = -7; offset <= 7; offset++)
            ProductivityDaySummary(
              localDate: DateTime(today.year, today.month, today.day + offset),
              completedTasks: 0,
              completedFocusIntervals: 1,
              totalFocusSeconds: 60,
            ),
        ]),
      );
      expect(snapshot.week, hasLength(7));
      expect(snapshot.week.first.localDate.weekday, DateTime.monday);
      expect(snapshot.week.last.localDate.weekday, DateTime.sunday);
      expect(snapshot.week.map((day) => day.localDate).toSet(), hasLength(7));
      expect(
        snapshot.week.fold(0, (sum, day) => sum + day.totalFocusSeconds),
        today.weekday * 60,
      );
      expect(snapshot.completedTasks, 8);
    }
  });

  test('overflow in one habit period cannot complete a different period', () {
    final day = DateTime(2026, 5, 1);
    final habits = [
      for (var i = 0; i < 13; i++)
        Habit(
          id: '$i',
          userId: 'user',
          title: 'Habit $i',
          createdAt: day,
          updatedAt: day,
          scheduleHistory: [
            HabitSchedule(
              effectiveFrom: day,
              startDate: day,
              weekdays: [1, 2, 3, 4, 5, 6, 7],
              targetPerDay: 2,
              periodTargets: {
                HabitDayPeriod.morning: 1,
                HabitDayPeriod.evening: 1,
              },
            ),
          ],
        ),
    ];
    final snapshot = buildAppleWidgetSnapshot(
      now: day,
      tasks: [],
      habits: habits,
      checkIns: [
        for (var i = 0; i < 2; i++)
          HabitCheckIn(
            id: '$i',
            userId: 'user',
            habitId: '0',
            day: day,
            createdAt: day,
            updatedAt: day,
            dayPeriod: HabitDayPeriod.morning,
          ),
        HabitCheckIn(
          id: 'old',
          userId: 'user',
          habitId: '0',
          day: DateTime(2026, 4, 30),
          createdAt: day,
          updatedAt: day,
          dayPeriod: HabitDayPeriod.evening,
        ),
      ],
      productivity: _summary([]),
    );
    expect(snapshot.totalHabits, 13);
    expect(snapshot.habits, hasLength(12));
    expect(snapshot.habits.first.count, 1);
    expect(snapshot.habits.first.completed, isFalse);
    expect(snapshot.completedHabits, 0);
  });
}

ProductivitySummary _summary(List<ProductivityDaySummary> days) =>
    ProductivitySummary(
      completedTasks: 8,
      completedFocusIntervals: 0,
      totalFocusSeconds: 0,
      plannedFocusIntervals: 0,
      openTasks: 0,
      allTimeCompletedTasks: 8,
      allTimeCompletedFocusIntervals: 0,
      lastSevenDays: days,
    );
