import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/habit_dependencies.dart';
import 'package:pomodoist/config/habit_notification_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/habits/habit_models.dart';
import 'package:pomodoist/domain/models/notifications/habit_reminder_status.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/ui/habits/view_models/habits_view_model.dart';
import 'package:pomodoist/utils/clock.dart';

final _today = DateTime(2026, 10, 31);

Habit _habit(String id, {Map<HabitDayPeriod, int> targets = const {}}) => Habit(
  id: id,
  userId: 'local-user',
  title: id,
  scheduleHistory: [
    HabitDraft(
      title: id,
      startDate: DateTime(2026, 10, 1),
      periodTargets: targets,
    ).schedule(DateTime(2026, 10, 1)),
  ],
  createdAt: _today,
  updatedAt: _today,
);

HabitCheckIn _mark(String id, String habit, {HabitDayPeriod? period}) =>
    HabitCheckIn(
      id: id,
      userId: 'local-user',
      habitId: habit,
      day: _today,
      createdAt: _today,
      updatedAt: _today,
      dayPeriod: period,
    );

void main() {
  test(
    'selection waits for marks, preserves completion and falls back on removal',
    () async {
      final habits = StreamController<List<Habit>>();
      final marks = StreamController<List<HabitCheckIn>>();
      final db = AppDatabase(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(FixedClock(_today)),
          habitsProvider.overrideWith((_) => habits.stream),
          habitCheckInsProvider.overrideWith((_) => marks.stream),
          projectsProvider.overrideWith((_) => Stream.value([])),
          habitReminderStatusProvider.overrideWith(_Status.new),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await habits.close();
        await marks.close();
        await db.close();
      });
      container.listen(habitsViewModelProvider, (_, _) {});
      final vm = container.read(habitsViewModelProvider.notifier);
      final read = _habit('read'), water = _habit('water');
      habits.add([read, water]);
      await pumpEventQueue();
      marks.add([_mark('read-1', 'read')]);
      await pumpEventQueue();
      expect(
        container.read(habitsViewModelProvider).selectedRow?.habit.id,
        'water',
      );
      vm.selectHabit('water', period: HabitDayPeriod.anytime);
      marks.add([_mark('read-1', 'read'), _mark('water-1', 'water')]);
      await pumpEventQueue();
      expect(
        container.read(habitsViewModelProvider).selectedRow?.habit.id,
        'water',
      );
      expect(
        container.read(habitsViewModelProvider).selectedRow?.complete,
        isTrue,
      );
      habits.add([read]);
      await pumpEventQueue();
      expect(
        container.read(habitsViewModelProvider).selectedRow?.habit.id,
        'read',
      );
      habits.add([]);
      await pumpEventQueue();
      expect(container.read(habitsViewModelProvider).selectedRow, isNull);
      expect(container.read(habitsViewModelProvider).overviewOpen, isFalse);
    },
  );

  test(
    'period selection survives date changes while the overview remains a daily total',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final habit = _habit(
        'water',
        targets: {HabitDayPeriod.morning: 1, HabitDayPeriod.evening: 2},
      );
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(FixedClock(_today)),
          habitsProvider.overrideWith((_) => Stream.value([habit])),
          habitCheckInsProvider.overrideWith(
            (_) => Stream.value([
              _mark('morning', 'water', period: HabitDayPeriod.morning),
              _mark('evening', 'water', period: HabitDayPeriod.evening),
            ]),
          ),
          projectsProvider.overrideWith((_) => Stream.value([])),
          habitReminderStatusProvider.overrideWith(_Status.new),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      container.listen(habitsViewModelProvider, (_, _) {});
      await pumpEventQueue();
      final vm = container.read(habitsViewModelProvider.notifier);
      vm.selectHabit('water', period: HabitDayPeriod.evening);
      var state = container.read(habitsViewModelProvider);
      expect(state.selectedRow?.count, 2);
      expect(state.selectedRow?.target, 3);
      expect(state.selectedPeriod, HabitDayPeriod.evening);
      expect(state.overviewOpen, isTrue);
      expect(state.selectedRow!.history.map((e) => e.day), [
        for (var i = 26; i <= 31; i++) DateTime(2026, 10, i),
        DateTime(2026, 11, 1),
      ]);
      vm.closeOverview();
      vm.selectDay(DateTime(2026, 10, 30));
      state = container.read(habitsViewModelProvider);
      expect(state.selectedRow?.habit.id, 'water');
      expect(state.selectedPeriod, HabitDayPeriod.evening);
      expect(state.overviewOpen, isFalse);
      vm.selectDay(DateTime(2026, 11, 1));
      expect(
        container.read(habitsViewModelProvider).selectedRow?.canAdd,
        isFalse,
      );
    },
  );
}

class _Status extends HabitNotificationCoordinator {
  @override
  HabitReminderStatus build() => HabitReminderStatus.available;
}
