import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/settings/preferences_repository.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository.dart';
import 'package:pomodoist/domain/models/tasks/calendar_models.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/view_models/calendar_view_model.dart';
import 'package:pomodoist/utils/clock.dart';
import 'package:pomodoist/utils/result.dart';

TaskItem task(String id, {TaskSchedule? schedule, bool canEdit = true}) =>
    TaskItem(
      id: id,
      userId: 'u',
      content: id,
      projectId: 'p',
      priority: 1,
      status: 'open',
      completedFocusIntervals: 0,
      totalFocusSeconds: 0,
      orderKey: id,
      isDeleted: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      dueJson: schedule?.toJsonString(),
      canEdit: canEdit,
      parentId: 'parent',
    );

class FakeTasks implements TaskRepository {
  TaskItem? current;
  UpdateTaskPatch? patch;
  int updates = 0;
  @override
  Stream<TaskItem?> watchTask(String id) => Stream.value(current);
  @override
  Future<Result<void>> updateTask(String id, UpdateTaskPatch value) async {
    updates++;
    patch = value;
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> completeTask(String id) async => const Result.ok(null);
  @override
  Future<Result<void>> uncompleteTask(String id) async => const Result.ok(null);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePreferences implements PreferencesRepository {
  String? stored;
  bool failWrite = false;
  bool failNextRead = false;
  Completer<Result<Map<String, Object>>>? pendingRead;
  Completer<void>? firstWriteGate;
  final writes = <String>[];
  int reads = 0;
  @override
  Future<Result<Map<String, Object>>> read(
    Iterable<String> keys, {
    bool reload = false,
  }) async {
    reads++;
    if (failNextRead) {
      failNextRead = false;
      return Result.error(StateError('read failure'), StackTrace.current);
    }
    return pendingRead?.future ??
        Result.ok({if (stored != null) calendarSettingsKey: stored!});
  }

  @override
  Future<Result<void>> write(Map<String, Object?> values) async {
    final value = values[calendarSettingsKey] as String;
    writes.add(value);
    if (writes.length == 1) await firstWriteGate?.future;
    if (failWrite)
      return Result.error(StateError('disk failure'), StackTrace.current);
    stored = value;
    return const Result.ok(null);
  }
}

ProviderContainer container(
  FakeTasks tasks,
  FakePreferences preferences, {
  Stream<List<ProjectItem>>? projectStream,
  Stream<List<TaskItem>>? taskStream,
}) => ProviderContainer(
  overrides: [
    taskRepositoryProvider.overrideWithValue(tasks),
    preferencesRepositoryProvider.overrideWithValue(preferences),
    tasksByQueryProvider(
      const TaskQuery.all(),
    ).overrideWith((_) => taskStream ?? Stream.value(const <TaskItem>[])),
    projectsProvider.overrideWith(
      (_) => projectStream ?? Stream.value(const <ProjectItem>[]),
    ),
    clockProvider.overrideWithValue(FixedClock(DateTime(2026, 9, 25))),
    quickAddDefaultTimedBlockMinutesProvider.overrideWithValue(45),
  ],
);

void main() {
  test(
    'timed drag and resize retain recurrence and duration across midnight',
    () async {
      final source = TaskSchedule.timed(
        start: DateTime(2026, 9, 25, 10),
        end: DateTime(2026, 9, 25, 11, 30),
        timeZone: 'Europe/Moscow',
        recurrenceSeriesId: 'series',
      );
      final tasks = FakeTasks()..current = task('a', schedule: source);
      final c = container(tasks, FakePreferences());
      addTearDown(c.dispose);
      final sub = c.listen(calendarViewModelProvider, (_, _) {});
      addTearDown(sub.close);
      final vm = c.read(calendarViewModelProvider.notifier);
      await vm.moveTask('a', DateTime(2026, 9, 26), minutes: 1410);
      final moved = tasks.patch!.schedule!;
      expect(moved.start!.toLocal(), DateTime(2026, 9, 26, 23, 30));
      expect(moved.end!.toLocal(), DateTime(2026, 9, 27, 1));
      expect(moved.timeZone, source.timeZone);
      expect(moved.recurrenceSeriesId, 'series');
      tasks.current = task('a', schedule: moved);
      await vm.resizeTask('a', DateTime(2026, 9, 27, 2));
      expect(tasks.patch!.schedule!.duration, const Duration(minutes: 150));
      expect(tasks.patch!.schedule!.recurrenceSeriesId, 'series');
      expect(tasks.patch!.schedule!.timeZone, source.timeZone);
      await expectLater(vm.resizeTask('a', moved.start!), throwsArgumentError);
      expect(tasks.updates, 2);
    },
  );

  test(
    'calendar clock refreshes by minute without rebuilding task layout each second',
    () async {
      final ticks = StreamController<DateTime>();
      addTearDown(ticks.close);
      final c = ProviderContainer(
        overrides: [
          taskRepositoryProvider.overrideWithValue(FakeTasks()),
          preferencesRepositoryProvider.overrideWithValue(FakePreferences()),
          tasksByQueryProvider(
            const TaskQuery.all(),
          ).overrideWith((_) => Stream.value(const <TaskItem>[])),
          projectsProvider.overrideWith(
            (_) => Stream.value(const <ProjectItem>[]),
          ),
          clockProvider.overrideWithValue(FixedClock(DateTime(2026, 9, 25))),
          quickAddDefaultTimedBlockMinutesProvider.overrideWithValue(45),
          taskTimeTickerProvider.overrideWith((_) => ticks.stream),
        ],
      );
      addTearDown(c.dispose);
      final sub = c.listen(calendarViewModelProvider, (_, _) {});
      addTearDown(sub.close);
      ticks.add(DateTime(2026, 9, 25, 12, 30, 1));
      await pumpEventQueue();
      final first = c.read(calendarViewModelProvider);
      ticks.add(DateTime(2026, 9, 25, 12, 30, 2));
      await pumpEventQueue();
      expect(identical(first, c.read(calendarViewModelProvider)), isTrue);
      ticks.add(DateTime(2026, 9, 25, 12, 31));
      await pumpEventQueue();
      expect(
        c.read(calendarViewModelProvider).now,
        DateTime(2026, 9, 25, 12, 31),
      );
    },
  );

  test(
    'date-only move keeps timed duration, recurrence and timezone',
    () async {
      final repeat = TaskRecurrence(
        interval: 1,
        unit: TaskRecurrenceUnit.week,
        seriesId: 'series',
      );
      final tasks = FakeTasks()
        ..current = task(
          'a',
          schedule: TaskSchedule.timed(
            start: DateTime(2026, 9, 25, 10),
            end: DateTime(2026, 9, 25, 11, 30),
            recurrence: repeat,
            timeZone: 'Europe/Moscow',
          ),
        );
      final c = container(tasks, FakePreferences());
      addTearDown(c.dispose);
      final sub = c.listen(calendarViewModelProvider, (_, _) {});
      addTearDown(sub.close);
      await c
          .read(calendarViewModelProvider.notifier)
          .moveTask('a', DateTime(2026, 9, 28));
      final moved = tasks.patch!.schedule!;
      expect(moved.start!.toLocal(), DateTime(2026, 9, 28, 10));
      expect(moved.duration, const Duration(minutes: 90));
      expect(moved.recurrence, repeat);
      expect(moved.timeZone, 'Europe/Moscow');
    },
  );

  test(
    'new timed move uses preference duration and read-only task is rejected',
    () async {
      final tasks = FakeTasks()..current = task('a');
      final c = container(tasks, FakePreferences());
      addTearDown(c.dispose);
      final sub = c.listen(calendarViewModelProvider, (_, _) {});
      addTearDown(sub.close);
      final vm = c.read(calendarViewModelProvider.notifier);
      await vm.moveTask('a', DateTime(2026, 9, 25), minutes: 600);
      expect(tasks.patch!.schedule!.duration, const Duration(minutes: 45));
      tasks.current = task('a', canEdit: false);
      await expectLater(vm.unscheduleTask('a'), throwsStateError);
      expect(tasks.updates, 1);
    },
  );

  test(
    'failed preference write retains routine draft and reports error',
    () async {
      final preferences = FakePreferences()..failWrite = true;
      final c = container(FakeTasks(), preferences);
      addTearDown(c.dispose);
      final sub = c.listen(calendarViewModelProvider, (_, _) {});
      addTearDown(sub.close);
      final vm = c.read(calendarViewModelProvider.notifier);
      await expectLater(
        vm.saveRoutine('Draft', [
          CalendarPeriod(name: 'Work', startMinutes: 540, endMinutes: 720),
        ]),
        throwsStateError,
      );
      final state = c.read(calendarViewModelProvider);
      expect(state.settings.routineName, isEmpty);
      expect(state.settingsError, isA<StateError>());
    },
  );

  test('late preference load does not erase edited mode', () async {
    final preferences = FakePreferences()..pendingRead = Completer();
    final c = container(FakeTasks(), preferences);
    addTearDown(c.dispose);
    final sub = c.listen(calendarViewModelProvider, (_, _) {});
    addTearDown(sub.close);
    final vm = c.read(calendarViewModelProvider.notifier);
    final save = vm.setMode(CalendarMode.day);
    preferences.pendingRead!.complete(
      Result.ok({
        calendarSettingsKey: CalendarSettings(
          mode: CalendarMode.month,
        ).toJsonString(),
      }),
    );
    await save;
    await pumpEventQueue();
    expect(c.read(calendarViewModelProvider).settings.mode, CalendarMode.day);
  });

  test('concurrent settings writes persist the last combined action', () async {
    final preferences = FakePreferences()..firstWriteGate = Completer<void>();
    final c = container(FakeTasks(), preferences);
    addTearDown(c.dispose);
    final sub = c.listen(calendarViewModelProvider, (_, _) {});
    addTearDown(sub.close);
    final vm = c.read(calendarViewModelProvider.notifier);
    final mode = vm.setMode(CalendarMode.day);
    await pumpEventQueue();
    final routine = vm.saveRoutine('Mine', [
      CalendarPeriod(name: 'Work', startMinutes: 540, endMinutes: 720),
    ]);
    preferences.firstWriteGate!.complete();
    await Future.wait([mode, routine]);
    final persisted = CalendarSettings.fromJsonString(preferences.stored);
    expect(persisted.mode, CalendarMode.day);
    expect(persisted.routineName, 'Mine');
    expect(c.read(calendarViewModelProvider).settings.mode, CalendarMode.day);
  });

  test('invalid routine is rejected before persistence', () async {
    final preferences = FakePreferences();
    final c = container(FakeTasks(), preferences);
    addTearDown(c.dispose);
    final sub = c.listen(calendarViewModelProvider, (_, _) {});
    addTearDown(sub.close);
    expect(
      () => c.read(calendarViewModelProvider.notifier).saveRoutine('', []),
      throwsArgumentError,
    );
    expect(preferences.writes, isEmpty);
  });

  test('retry reloads preferences after read failure', () async {
    final preferences = FakePreferences()
      ..failNextRead = true
      ..stored = CalendarSettings(mode: CalendarMode.month).toJsonString();
    final c = container(FakeTasks(), preferences);
    addTearDown(c.dispose);
    final sub = c.listen(calendarViewModelProvider, (_, _) {});
    addTearDown(sub.close);
    await pumpEventQueue();
    expect(c.read(calendarViewModelProvider).settingsError, isA<StateError>());
    preferences.stored = CalendarSettings(
      mode: CalendarMode.day,
    ).toJsonString();
    await c.read(calendarViewModelProvider.notifier).retry();
    expect(preferences.reads, 2);
    expect(c.read(calendarViewModelProvider).settings.mode, CalendarMode.day);
  });

  test('removed project clears the active project filter', () async {
    final projects = StreamController<List<ProjectItem>>();
    addTearDown(projects.close);
    final c = container(
      FakeTasks(),
      FakePreferences(),
      projectStream: projects.stream,
    );
    addTearDown(c.dispose);
    final sub = c.listen(calendarViewModelProvider, (_, _) {});
    addTearDown(sub.close);
    projects.add([
      ProjectItem(
        id: 'p',
        userId: 'u',
        name: 'P',
        orderKey: 'p',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    ]);
    await pumpEventQueue();
    c.read(calendarViewModelProvider.notifier).setProject('p');
    expect(c.read(calendarViewModelProvider).projectId, 'p');
    projects.add([]);
    await pumpEventQueue();
    expect(c.read(calendarViewModelProvider).projectId, isNull);
  });

  test('retry refreshes task and project stream sources', () async {
    var taskSubscriptions = 0;
    var projectSubscriptions = 0;
    final c = container(
      FakeTasks(),
      FakePreferences(),
      taskStream: Stream.multi((sink) {
        taskSubscriptions++;
        sink.add([]);
      }),
      projectStream: Stream.multi((sink) {
        projectSubscriptions++;
        sink.add([]);
      }),
    );
    addTearDown(c.dispose);
    final sub = c.listen(calendarViewModelProvider, (_, _) {});
    addTearDown(sub.close);
    await pumpEventQueue();
    await c.read(calendarViewModelProvider.notifier).retry();
    await pumpEventQueue();
    expect(taskSubscriptions, 2);
    expect(projectSubscriptions, 2);
  });
}
