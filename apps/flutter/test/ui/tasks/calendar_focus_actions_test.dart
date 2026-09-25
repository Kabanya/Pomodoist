import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/focus/focus_repository.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/view_models/calendar_view_model.dart';
import 'package:pomodoist/utils/result.dart';
import 'calendar_view_model_test.dart' show FakeTasks, FakePreferences, task;

final now = DateTime(2026, 9, 25);
FocusRunItem run(String taskId) => FocusRunItem(
  id: 'run-$taskId',
  userId: 'u',
  taskId: taskId,
  presetId: 'p',
  status: 'active',
  startedAt: now,
  targetWorkIntervals: 4,
  completedWorkIntervals: 0,
  createdAt: now,
  updatedAt: now,
);
FocusIntervalItem interval(String status, {String taskId = 'a'}) =>
    FocusIntervalItem(
      id: 'interval-$status',
      runId: 'run-$taskId',
      type: 'work',
      status: status,
      plannedSeconds: 1500,
      startedAt: now,
      pausedTotalSeconds: 0,
      sequenceNumber: 1,
      createdAt: now,
      updatedAt: now,
    );
FocusPresetItem preset({bool allowPause = true}) => FocusPresetItem(
  id: 'p',
  userId: 'u',
  name: 'Preset',
  workSeconds: 1500,
  shortBreakSeconds: 300,
  longBreakSeconds: 900,
  intervalsBeforeLongBreak: 4,
  autoStartBreaks: false,
  autoStartWork: false,
  allowPause: allowPause,
  strictMode: false,
  isDefault: true,
  createdAt: now,
  updatedAt: now,
);

class FakeFocus implements FocusRepository {
  FocusRunItem? active;
  FocusIntervalItem? current;
  final calls = <String>[];
  StartFocusRunInput? started;
  Completer<void>? gate;
  bool fail = false;
  @override
  Stream<FocusRunItem?> watchActiveRun() => Stream.value(active);
  @override
  Stream<FocusIntervalItem?> watchActiveInterval() => Stream.value(current);
  @override
  Stream<List<FocusPresetItem>> watchPresets() => Stream.value([preset()]);
  Future<Result<void>> perform(String name) async {
    calls.add(name);
    await gate?.future;
    return fail
        ? Result.error(StateError('offline'), StackTrace.current)
        : const Result.ok(null);
  }

  @override
  Future<Result<String>> startRun(
    StartFocusRunInput input, {
    DateTime? now,
  }) async {
    started = input;
    calls.add('start');
    return const Result.ok('new-run');
  }

  @override
  Future<Result<void>> pauseActiveInterval({DateTime? now}) => perform('pause');
  @override
  Future<Result<void>> resumeActiveInterval({DateTime? now}) =>
      perform('resume');
  @override
  Future<Result<void>> startReadyInterval() => perform('ready');
  @override
  Future<Result<void>> stopActiveRun({
    required StopFocusReason reason,
    DateTime? now,
  }) => perform('stop');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'menu provider updates from live Focus streams without a timer',
    () async {
      final runs = StreamController<FocusRunItem?>();
      final intervals = StreamController<FocusIntervalItem?>();
      addTearDown(runs.close);
      addTearDown(intervals.close);
      final c = ProviderContainer(
        overrides: [
          activeFocusRunProvider.overrideWith((_) => runs.stream),
          activeFocusIntervalProvider.overrideWith((_) => intervals.stream),
          focusPresetsProvider.overrideWith((_) => Stream.value([preset()])),
        ],
      );
      addTearDown(c.dispose);
      final provider = calendarTaskFocusActionsProvider(task('a'));
      final subscription = c.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      expect(c.read(provider), isEmpty);
      runs.add(null);
      intervals.add(null);
      await pumpEventQueue();
      expect(c.read(provider), [CalendarFocusAction.start]);
      runs.add(run('a'));
      intervals.add(interval('running'));
      await pumpEventQueue();
      expect(c.read(provider), [
        CalendarFocusAction.pause,
        CalendarFocusAction.stop,
      ]);
      intervals.add(interval('paused'));
      await pumpEventQueue();
      expect(c.read(provider), [
        CalendarFocusAction.resume,
        CalendarFocusAction.stop,
      ]);
      runs.add(null);
      intervals.add(null);
      await pumpEventQueue();
      expect(c.read(provider), [CalendarFocusAction.start]);
      intervals.addError(StateError('unavailable'));
      await pumpEventQueue();
      expect(c.read(provider), isEmpty);
    },
  );

  test('menu follows task session, pause restrictions and interval state', () {
    List<CalendarFocusAction> actions({
      FocusRunItem? active,
      FocusIntervalItem? current,
      bool allowPause = true,
    }) => calendarFocusActions(
      task('a'),
      run: active,
      interval: current,
      preset: preset(allowPause: allowPause),
    );
    expect(actions(), [CalendarFocusAction.start]);
    expect(
      actions(
        active: run('other'),
        current: interval('running', taskId: 'other'),
      ),
      [CalendarFocusAction.start],
    );
    expect(actions(active: run('a'), current: interval('running')), [
      CalendarFocusAction.pause,
      CalendarFocusAction.stop,
    ]);
    expect(actions(active: run('a'), current: interval('paused')), [
      CalendarFocusAction.resume,
      CalendarFocusAction.stop,
    ]);
    expect(actions(active: run('a'), current: interval('ready')), [
      CalendarFocusAction.startInterval,
      CalendarFocusAction.stop,
    ]);
    expect(
      actions(
        active: run('a'),
        current: interval('running'),
        allowPause: false,
      ),
      [CalendarFocusAction.stop],
    );
    expect(
      actions(
        active: run('a'),
        current: interval('running', taskId: 'other'),
      ),
      [CalendarFocusAction.stop],
    );
  });
  for (final action in [
    CalendarFocusAction.pause,
    CalendarFocusAction.resume,
    CalendarFocusAction.startInterval,
    CalendarFocusAction.stop,
  ]) {
    test(
      '$action controls only the matching session and revalidates stale menus',
      () async {
        final focus = FakeFocus()
          ..active = run('a')
          ..current = interval(switch (action) {
            CalendarFocusAction.resume => 'paused',
            CalendarFocusAction.startInterval => 'ready',
            _ => 'running',
          });
        final c = makeContainer(focus);
        addTearDown(c.dispose);
        final keepAlive = c.listen(calendarViewModelProvider, (_, _) {});
        addTearDown(keepAlive.close);
        final vm = c.read(calendarViewModelProvider.notifier);
        await vm.focusTask('a', action, confirmSwitch: () async => true);
        expect(focus.calls, [
          switch (action) {
            CalendarFocusAction.pause => 'pause',
            CalendarFocusAction.resume => 'resume',
            CalendarFocusAction.startInterval => 'ready',
            _ => 'stop',
          },
        ]);
        focus.active = run('other');
        focus.current = interval('running', taskId: 'other');
        await vm.focusTask('a', action, confirmSwitch: () async => true);
        expect(focus.calls.length, 1);
      },
    );
  }
  test(
    'starting focus reuses launcher and respects canceled switching',
    () async {
      final focus = FakeFocus()
        ..active = run('other')
        ..current = interval('running', taskId: 'other');
      final c = makeContainer(focus);
      addTearDown(c.dispose);
      final keepAlive = c.listen(calendarViewModelProvider, (_, _) {});
      addTearDown(keepAlive.close);
      final vm = c.read(calendarViewModelProvider.notifier);
      await vm.focusTask(
        'a',
        CalendarFocusAction.start,
        confirmSwitch: () async => false,
      );
      expect(focus.calls, isEmpty);
      await vm.focusTask(
        'a',
        CalendarFocusAction.start,
        confirmSwitch: () async => true,
      );
      expect(focus.started?.taskId, 'a');
      expect(focus.started?.presetId, 'p');
    },
  );
  test('pending actions are deduplicated and failures permit retry', () async {
    final focus = FakeFocus()
      ..active = run('a')
      ..current = interval('running')
      ..gate = Completer<void>()
      ..fail = true;
    final c = makeContainer(focus);
    addTearDown(c.dispose);
    final keepAlive = c.listen(calendarViewModelProvider, (_, _) {});
    addTearDown(keepAlive.close);
    final vm = c.read(calendarViewModelProvider.notifier);
    final first = vm.focusTask(
      'a',
      CalendarFocusAction.pause,
      confirmSwitch: () async => true,
    );
    await pumpEventQueue();
    await vm.focusTask(
      'a',
      CalendarFocusAction.pause,
      confirmSwitch: () async => true,
    );
    expect(focus.calls, ['pause']);
    final failed = expectLater(first, throwsStateError);
    focus.gate!.complete();
    await failed;
    focus.fail = false;
    await vm.focusTask(
      'a',
      CalendarFocusAction.pause,
      confirmSwitch: () async => true,
    );
    expect(focus.calls, ['pause', 'pause']);
  });
}

ProviderContainer makeContainer(FakeFocus focus) => ProviderContainer(
  overrides: [
    taskRepositoryProvider.overrideWithValue(FakeTasks()..current = task('a')),
    preferencesRepositoryProvider.overrideWithValue(FakePreferences()),
    focusRepositoryProvider.overrideWithValue(focus),
    lastFocusPresetIdProvider.overrideWithValue('p'),
    tasksByQueryProvider(
      const TaskQuery.all(),
    ).overrideWith((_) => Stream.value([])),
    projectsProvider.overrideWith((_) => Stream.value([])),
  ],
);
