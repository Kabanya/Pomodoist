import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/config/habit_dependencies.dart';
import 'package:pomodoist/config/habit_notification_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/habits/habit_models.dart';
import 'package:pomodoist/domain/models/notifications/habit_reminder_status.dart';
import 'package:pomodoist/ui/habits/view_models/habits_view_model.dart';
import 'package:pomodoist/utils/clock.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/settings/preferences_repository.dart';
import 'package:pomodoist/utils/result.dart';

void main() {
  test(
    'sign edits retain the selected day and surface failure without losing the sign',
    () async {
      final now = DateTime(2026, 10, 6, 12);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(FixedClock(now)),
          preferencesRepositoryProvider.overrideWithValue(_Preferences()),
          projectsProvider.overrideWith((_) => Stream.value([])),
          habitReminderStatusProvider.overrideWith(_Status.new),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(habitsViewModelProvider, (_, _) {});
      addTearDown(sub.close);
      final vm = container.read(habitsViewModelProvider.notifier);
      expect(
        await vm.save(
          title: 'Read',
          startDate: now,
          weekdays: [1, 2, 3, 4, 5, 6, 7],
          target: '1',
          icon: '📚',
        ),
        isTrue,
      );
      final habits = await container.read(habitsProvider.future);
      final id = habits.single.id;
      vm.selectDay(DateTime(2026, 10, 5));
      expect(await vm.updateIcon(id, 'bookOpen'), isTrue);
      expect(
        container.read(habitsViewModelProvider).selectedDay,
        DateTime(2026, 10, 5),
      );
      expect(await vm.updateIcon(id, 'bad icon'), isFalse);
      expect(container.read(habitsViewModelProvider).actionError, isTrue);
      expect(
        (await container.read(habitRepositoryProvider).watchHabits().first)
            .single
            .icon,
        'bookOpen',
      );
      expect(await vm.updateIcon(id, null), isTrue);
      expect(container.read(habitsViewModelProvider).actionError, isFalse);
      expect(
        (await container.read(habitRepositoryProvider).watchHabits().first)
            .single
            .icon,
        isNull,
      );
    },
  );
  test(
    'independent morning and night goals regroup and undo without duplicate summary',
    () async {
      final now = DateTime(2026, 10, 3, 12);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(FixedClock(now)),
          preferencesRepositoryProvider.overrideWithValue(_Preferences()),
          projectsProvider.overrideWith((_) => Stream.value([])),
          habitReminderStatusProvider.overrideWith(_Status.new),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(habitsViewModelProvider, (_, _) {});
      addTearDown(sub.close);
      final vm = container.read(habitsViewModelProvider.notifier);
      expect(
        await vm.save(
          title: 'Water',
          startDate: DateTime(2026, 10, 2),
          weekdays: [1, 2, 3, 4, 5, 6, 7],
          target: 'ignored',
          periodTargets: {HabitDayPeriod.morning: 2, HabitDayPeriod.night: 1},
        ),
        isTrue,
      );
      await pumpEventQueue();
      final id = container.read(habitsViewModelProvider).rows.single.habit.id;
      expect(await vm.addCheckIn(id), isFalse);
      expect(await vm.addCheckIn(id, period: HabitDayPeriod.night), isTrue);
      await pumpEventQueue();
      var state = container.read(habitsViewModelProvider);
      expect(state.planned, 1);
      expect(state.completed, 0);
      expect(state.rows.single.count, 1);
      expect(state.rhythmGroups.last.rows.single.complete, isTrue);
      expect(state.rhythmGroups.first.rows.single.canUndo, isFalse);
      expect(await vm.addCheckIn(id, period: HabitDayPeriod.night), isFalse);
      for (var i = 0; i < 2; i++) {
        expect(await vm.addCheckIn(id, period: HabitDayPeriod.morning), isTrue);
        await pumpEventQueue();
      }
      state = container.read(habitsViewModelProvider);
      expect(state.completed, 1);
      expect(state.completedRows, hasLength(1));
      expect(state.rhythmGroups, hasLength(2));
      expect(await vm.undoCheckIn(id, period: HabitDayPeriod.night), isTrue);
      await pumpEventQueue();
      state = container.read(habitsViewModelProvider);
      expect(state.completed, 0);
      expect(state.rows.single.periodCounts, {
        HabitDayPeriod.morning: 2,
        HabitDayPeriod.night: 0,
      });
      expect(state.rhythmGroups.first.rows.single.complete, isTrue);
      expect(state.rhythmGroups.last.rows.single.canUndo, isFalse);
      expect(
        await vm.save(
          id: id,
          title: 'Water',
          startDate: DateTime(2026, 10, 2),
          weekdays: [1, 2, 3, 4, 5, 6, 7],
          target: '1',
          periodTargets: {HabitDayPeriod.evening: 3},
        ),
        isTrue,
      );
      await pumpEventQueue();
      vm.selectDay(DateTime(2026, 10, 2));
      expect(container.read(habitsViewModelProvider).rows.single.targets, {
        HabitDayPeriod.morning: 2,
        HabitDayPeriod.night: 1,
      });
      vm.selectDay(DateTime(2026, 10, 4));
      expect(
        container
            .read(habitsViewModelProvider)
            .rhythmGroups
            .single
            .rows
            .single
            .canAdd,
        isFalse,
      );
      expect(await vm.addCheckIn(id, period: HabitDayPeriod.evening), isFalse);
    },
  );
  test(
    'seven repetitions stay one row and completed/undo regroup both views',
    () async {
      final now = DateTime(2026, 10, 3, 12);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final preferences = _Preferences();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(FixedClock(now)),
          preferencesRepositoryProvider.overrideWithValue(preferences),
          projectsProvider.overrideWith((_) => Stream.value([])),
          habitReminderStatusProvider.overrideWith(_Status.new),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(habitsViewModelProvider, (_, _) {});
      addTearDown(sub.close);
      final vm = container.read(habitsViewModelProvider.notifier);
      await vm.save(
        title: 'Water',
        startDate: DateTime(2026, 10, 2),
        weekdays: [1, 2, 3, 4, 5, 6, 7],
        target: '7',
        reminderMinutes: 480,
      );
      await pumpEventQueue();
      final id = container.read(habitsViewModelProvider).rows.single.habit.id;
      expect(
        container.read(habitsViewModelProvider).rows.single.dayPeriod,
        HabitDayPeriod.anytime,
      );
      for (var i = 0; i < 7; i++) {
        expect(await vm.addCheckIn(id), isTrue);
        await pumpEventQueue();
        final state = container.read(habitsViewModelProvider);
        expect(state.planned, 1);
        expect(state.completed, i == 6 ? 1 : 0);
        expect(state.rows.single.count, i + 1);
        expect(state.rhythmGroups.single.rows, hasLength(1));
      }
      expect(container.read(habitsViewModelProvider).remainingRows, isEmpty);
      expect(
        container.read(habitsViewModelProvider).completedRows,
        hasLength(1),
      );
      await vm.setViewMode(HabitViewMode.rhythm);
      expect(await vm.undoCheckIn(id), isTrue);
      await pumpEventQueue();
      expect(
        container.read(habitsViewModelProvider).remainingRows.single.count,
        6,
      );
      expect(container.read(habitsViewModelProvider).completedRows, isEmpty);
      expect(container.read(habitsViewModelProvider).completed, 0);
      expect(
        await vm.save(
          id: id,
          title: 'Water',
          startDate: DateTime(2026, 10, 2),
          weekdays: [1, 2, 3, 4, 5, 6, 7],
          target: '7',
          reminderMinutes: 480,
          dayPeriod: HabitDayPeriod.morning,
        ),
        isTrue,
      );
      await pumpEventQueue();
      expect(
        container.read(habitsViewModelProvider).rhythmGroups.single.period,
        HabitDayPeriod.morning,
      );
      expect(container.read(habitsViewModelProvider).rows.single.count, 6);
      vm.selectDay(DateTime(2026, 10, 2));
      expect(
        container.read(habitsViewModelProvider).rows.single.dayPeriod,
        HabitDayPeriod.anytime,
      );
      expect(container.read(habitsViewModelProvider).rows.single.target, 7);
      vm.selectDay(DateTime(2026, 10, 4));
      expect(
        container.read(habitsViewModelProvider).rows.single.canAdd,
        isFalse,
      );
      vm.selectDay(DateTime(2026, 10, 1));
      final beforeStart = container.read(habitsViewModelProvider);
      expect(beforeStart.rows, isEmpty);
      expect(beforeStart.habits.single.id, id);
    },
  );

  test(
    'retry cannot overwrite a view selected while its read is pending',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final preferences = _Preferences();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          preferencesRepositoryProvider.overrideWithValue(preferences),
          habitsProvider.overrideWith((_) => Stream.value([])),
          habitCheckInsProvider.overrideWith((_) => Stream.value([])),
          projectsProvider.overrideWith((_) => Stream.value([])),
          habitReminderStatusProvider.overrideWith(_Status.new),
        ],
      );
      addTearDown(container.dispose);
      container.listen(habitsViewModelProvider, (_, _) {});
      await pumpEventQueue();
      final vm = container.read(habitsViewModelProvider.notifier);
      preferences.readGate = Completer<void>();
      final retry = vm.retryViewMode();
      final change = vm.setViewMode(HabitViewMode.rhythm);
      await pumpEventQueue();
      preferences.readGate!.complete();
      await Future.wait([retry, change]);
      expect(
        container.read(habitsViewModelProvider).viewMode,
        HabitViewMode.rhythm,
      );
      expect(preferences.values[habitsViewModeKey], 'rhythm');
    },
  );

  test(
    'view preference restores and failed writes retain the previous mode',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final preferences = _Preferences();
      ProviderContainer open() {
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            preferencesRepositoryProvider.overrideWithValue(preferences),
            habitsProvider.overrideWith((_) => Stream.value([])),
            habitCheckInsProvider.overrideWith((_) => Stream.value([])),
            projectsProvider.overrideWith((_) => Stream.value([])),
            habitReminderStatusProvider.overrideWith(_Status.new),
          ],
        );
        container.listen(habitsViewModelProvider, (_, _) {});
        addTearDown(container.dispose);
        return container;
      }

      final first = open();
      await pumpEventQueue();
      expect(first.read(habitsViewModelProvider).viewMode, HabitViewMode.list);
      await first
          .read(habitsViewModelProvider.notifier)
          .setViewMode(HabitViewMode.rhythm);
      expect(preferences.values[habitsViewModeKey], 'rhythm');
      final second = open();
      await pumpEventQueue();
      expect(
        second.read(habitsViewModelProvider).viewMode,
        HabitViewMode.rhythm,
      );
      preferences.failWrite = true;
      await second
          .read(habitsViewModelProvider.notifier)
          .setViewMode(HabitViewMode.list);
      expect(
        second.read(habitsViewModelProvider).viewMode,
        HabitViewMode.rhythm,
      );
      expect(second.read(habitsViewModelProvider).viewError, isTrue);
      preferences.failWrite = false;
      await second
          .read(habitsViewModelProvider.notifier)
          .setViewMode(HabitViewMode.list);
      expect(second.read(habitsViewModelProvider).viewError, isFalse);
      preferences.failRead = true;
      final failed = open();
      await pumpEventQueue();
      expect(failed.read(habitsViewModelProvider).viewMode, HabitViewMode.list);
      expect(failed.read(habitsViewModelProvider).viewError, isTrue);
      preferences.failRead = false;
      preferences.values[habitsViewModeKey] = 'unknown';
      await failed.read(habitsViewModelProvider.notifier).retryViewMode();
      expect(failed.read(habitsViewModelProvider).viewMode, HabitViewMode.list);
      expect(failed.read(habitsViewModelProvider).viewError, isFalse);
    },
  );

  test(
    'row history respects past schedules, partial goals and future days',
    () async {
      final now = DateTime(2026, 10, 2, 12);
      final habit = Habit(
        id: 'h',
        userId: 'local-user',
        title: 'Water',
        scheduleHistory: [
          HabitDraft(
            title: 'Water',
            startDate: DateTime(2026, 9, 28),
            weekdays: [1, 3, 5],
            targetPerDay: 2,
          ).schedule(DateTime(2026, 9, 28)),
          HabitDraft(
            title: 'Water',
            startDate: DateTime(2026, 9, 28),
            targetPerDay: 4,
          ).schedule(DateTime(2026, 10, 2)),
        ],
        createdAt: now,
        updatedAt: now,
      );
      HabitCheckIn check(
        String id,
        DateTime day, {
        bool deleted = false,
        String habitId = 'h',
      }) => HabitCheckIn(
        id: id,
        userId: 'local-user',
        habitId: habitId,
        day: day,
        createdAt: now,
        updatedAt: now,
        isDeleted: deleted,
      );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(FixedClock(now)),
          habitsProvider.overrideWith((_) => Stream.value([habit])),
          habitCheckInsProvider.overrideWith(
            (_) => Stream.value([
              check('past-1', DateTime(2026, 9, 30)),
              check('past-2', DateTime(2026, 9, 30)),
              check('past-excess', DateTime(2026, 9, 30)),
              check('today', now),
              check('deleted', now, deleted: true),
              check('other', now, habitId: 'other'),
            ]),
          ),
          projectsProvider.overrideWith((_) => Stream.value([])),
          habitReminderStatusProvider.overrideWith(_Status.new),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(habitsViewModelProvider, (_, _) {});
      addTearDown(sub.close);
      await container.read(habitsProvider.future);
      await container.read(habitCheckInsProvider.future);
      await container.read(projectsProvider.future);
      final row = container.read(habitsViewModelProvider).rows.single;
      final history = row.history;
      expect(history.map((day) => (day.day, day.count, day.target)), [
        (DateTime(2026, 9, 28), 0, 2),
        (DateTime(2026, 9, 29), 0, null),
        (DateTime(2026, 9, 30), 2, 2),
        (DateTime(2026, 10, 1), 0, null),
        (DateTime(2026, 10, 2), 1, 4),
      ]);
      expect(row.count, 1);
      container
          .read(habitsViewModelProvider.notifier)
          .selectDay(DateTime(2026, 10, 3));
      final future = container.read(habitsViewModelProvider).rows.single;
      final futureHistory = future.history;
      expect(futureHistory.last.day, DateTime(2026, 10, 3));
      expect(futureHistory.last.count, 0);
      expect(futureHistory.last.target, 4);
      expect(future.canAdd, isFalse);
      container
          .read(habitsViewModelProvider.notifier)
          .selectDay(DateTime(2026, 9, 30));
      final past = container.read(habitsViewModelProvider).rows.single;
      expect(past.history.first.day, DateTime(2026, 9, 26));
      expect(past.history.first.target, isNull);
      expect(past.history.last.target, 2);
      expect(past.count, 2);
    },
  );
  test('UTC clock selects the device calendar day around midnight', () async {
    final utc = DateTime.utc(2026, 9, 30, 22, 30);
    final local = utc.toLocal();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(FixedClock(utc)),
        habitsProvider.overrideWith((_) => Stream.value([])),
        habitCheckInsProvider.overrideWith((_) => Stream.value([])),
        projectsProvider.overrideWith((_) => Stream.value([])),
        habitReminderStatusProvider.overrideWith(_Status.new),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(habitsViewModelProvider, (_, _) {});
    addTearDown(subscription.close);
    expect(
      container.read(habitsViewModelProvider).today,
      DateTime(local.year, local.month, local.day),
    );
  });
  final now = DateTime(2026, 9, 30, 12);
  test(
    'daily summary counts fully reached goals and future days stay readonly',
    () async {
      final habit = Habit(
        id: 'h',
        userId: 'local-user',
        title: 'Read',
        scheduleHistory: [
          HabitDraft(
            title: 'Read',
            startDate: DateTime(2026, 9, 28),
            targetPerDay: 2,
          ).schedule(DateTime(2026, 9, 28)),
        ],
        createdAt: now,
        updatedAt: now,
      );
      final check = HabitCheckIn(
        id: 'c',
        userId: 'local-user',
        habitId: 'h',
        day: now,
        createdAt: now,
        updatedAt: now,
      );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(FixedClock(now)),
          habitsProvider.overrideWith((_) => Stream.value([habit])),
          habitCheckInsProvider.overrideWith((_) => Stream.value([check])),
          projectsProvider.overrideWith((_) => Stream.value([])),
          habitReminderStatusProvider.overrideWith(_Status.new),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(habitsViewModelProvider, (_, _) {});
      addTearDown(sub.close);
      await container.read(habitsProvider.future);
      await container.read(habitCheckInsProvider.future);
      await container.read(projectsProvider.future);
      var state = container.read(habitsViewModelProvider);
      expect(state.planned, 1);
      expect(state.completed, 0);
      expect(state.rows.single.count, 1);
      expect(state.rows.single.canAdd, isTrue);
      container
          .read(habitsViewModelProvider.notifier)
          .selectDay(DateTime(2026, 10, 1));
      state = container.read(habitsViewModelProvider);
      expect(state.rows.single.canAdd, isFalse);
      expect(state.futureDay, isTrue);
      container.read(habitsViewModelProvider.notifier).moveWeek(-1);
      expect(
        container.read(habitsViewModelProvider).selectedDay,
        DateTime(2026, 9, 24),
      );
      container.read(habitsViewModelProvider.notifier).selectToday();
      expect(
        container.read(habitsViewModelProvider).selectedDay,
        DateTime(2026, 9, 30),
      );
    },
  );
  test(
    'ended habits retain historic editing and removed project has no label',
    () async {
      final habit = Habit(
        id: 'h',
        userId: 'local-user',
        title: 'Read',
        projectId: 'missing',
        scheduleHistory: [
          HabitDraft(
            title: 'Read',
            startDate: DateTime(2026, 9, 28),
            endDate: DateTime(2026, 9, 29),
          ).schedule(DateTime(2026, 9, 28)),
        ],
        createdAt: now,
        updatedAt: now,
      );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(FixedClock(now)),
          habitsProvider.overrideWith((_) => Stream.value([habit])),
          habitCheckInsProvider.overrideWith((_) => Stream.value([])),
          projectsProvider.overrideWith((_) => Stream.value([])),
          habitReminderStatusProvider.overrideWith(_Status.new),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(habitsViewModelProvider, (_, _) {});
      addTearDown(sub.close);
      await container.read(habitsProvider.future);
      await container.read(habitCheckInsProvider.future);
      await container.read(projectsProvider.future);
      final vm = container.read(habitsViewModelProvider.notifier);
      vm.showFinished(true);
      expect(
        container.read(habitsViewModelProvider).rows.single.canAdd,
        isFalse,
      );
      vm.selectDay(DateTime(2026, 9, 29));
      final row = container.read(habitsViewModelProvider).rows.single;
      expect(row.canAdd, isTrue);
      expect(row.project, isNull);
      expect(row.history.last.target, 1);
      vm.selectToday();
      expect(
        container.read(habitsViewModelProvider).rows.single.history.last.target,
        isNull,
      );
    },
  );
}

class _Status extends HabitNotificationCoordinator {
  @override
  HabitReminderStatus build() => HabitReminderStatus.available;
}

class _Preferences implements PreferencesRepository {
  final values = <String, Object>{};
  bool failWrite = false, failRead = false;
  Completer<void>? readGate;
  @override
  Future<Result<Map<String, Object>>> read(
    Iterable<String> keys, {
    bool reload = false,
  }) => Result.capture(() async {
    if (failRead) throw StateError('Read failed');
    final snapshot = {
      for (final key in keys)
        if (values.containsKey(key)) key: values[key]!,
    };
    await readGate?.future;
    return snapshot;
  });
  @override
  Future<Result<void>> write(Map<String, Object?> changes) =>
      Result.capture(() {
        if (failWrite) throw StateError('Write failed');
        for (final entry in changes.entries) {
          if (entry.value == null) {
            values.remove(entry.key);
          } else {
            values[entry.key] = entry.value!;
          }
        }
      });
}
