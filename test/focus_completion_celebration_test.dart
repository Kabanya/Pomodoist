import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/app/theme/app_theme.dart';
import 'package:pomodoist/features/focus/domain/focus_models.dart';
import 'package:pomodoist/features/focus/presentation/focus_completion_celebration.dart';
import 'package:pomodoist/features/focus/presentation/focus_completion_celebration_controller.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';
import 'package:pomodoist/l10n/app_localizations.dart';

void main() {
  testWidgets('standalone completion stays visible until Done', (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    container
        .read(focusRunCompletionControllerProvider.notifier)
        .present(_completion());

    await _pumpCelebration(tester, container: container);

    expect(find.byKey(const Key('focus-completion-overlay')), findsOneWidget);
    expect(find.byKey(const Key('focus-completion-done')), findsOneWidget);
    expect(find.byKey(const Key('focus-completion-next-task')), findsNothing);
    expect(find.text('Beautiful work!'), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    expect(find.byKey(const Key('focus-completion-overlay')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byKey(const Key('focus-completion-overlay')), findsOneWidget);

    await tester.tap(find.byKey(const Key('focus-completion-done')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('focus-completion-overlay')), findsNothing);
  });

  testWidgets('linked completion can leave the task open', (tester) async {
    final taskRepository = _TaskRepository(_task());
    final container = _container(taskRepository: taskRepository);
    addTearDown(container.dispose);
    container
        .read(focusRunCompletionControllerProvider.notifier)
        .present(_completion(taskId: 'task-1', taskTitle: 'Ship celebration'));

    await _pumpCelebration(tester, container: container);
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Ship celebration'), findsOneWidget);
    expect(
      find.byKey(const Key('focus-completion-complete-task')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('focus-completion-keep-open')), findsOneWidget);
    expect(find.byKey(const Key('focus-completion-done')), findsNothing);

    final keepOpen = find.byKey(const Key('focus-completion-keep-open'));
    await tester.ensureVisible(keepOpen);
    await tester.tap(keepOpen);
    await tester.pumpAndSettle();

    expect(taskRepository.completeCount, 0);
    expect(find.byKey(const Key('focus-completion-overlay')), findsNothing);
  });

  testWidgets('linked completion completes the task with undo feedback', (
    tester,
  ) async {
    final taskRepository = _TaskRepository(_task());
    final container = _container(taskRepository: taskRepository);
    addTearDown(container.dispose);
    container
        .read(focusRunCompletionControllerProvider.notifier)
        .present(_completion(taskId: 'task-1', taskTitle: 'Ship celebration'));
    await _pumpCelebration(tester, container: container);
    await tester.pump(const Duration(seconds: 2));

    final completeTask = find.byKey(
      const Key('focus-completion-complete-task'),
    );
    await tester.ensureVisible(completeTask);
    await tester.tap(completeTask);
    await tester.pumpAndSettle();

    expect(taskRepository.completeCount, 1);
    expect(find.byKey(const Key('focus-completion-overlay')), findsNothing);
    expect(find.text('Task completed'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(taskRepository.uncompleteCount, 1);
  });

  testWidgets('task completion failure keeps the celebration open', (
    tester,
  ) async {
    final taskRepository = _TaskRepository(
      _task(),
      completeError: StateError('write failed'),
    );
    final container = _container(taskRepository: taskRepository);
    addTearDown(container.dispose);
    container
        .read(focusRunCompletionControllerProvider.notifier)
        .present(_completion(taskId: 'task-1', taskTitle: 'Ship celebration'));
    await _pumpCelebration(tester, container: container);
    await tester.pump(const Duration(seconds: 2));

    final completeTask = find.byKey(
      const Key('focus-completion-complete-task'),
    );
    await tester.ensureVisible(completeTask);
    await tester.tap(completeTask);
    await tester.pumpAndSettle();

    expect(taskRepository.completeCount, 1);
    expect(find.byKey(const Key('focus-completion-overlay')), findsOneWidget);
    expect(
      find.text('Could not complete task: Bad state: write failed'),
      findsOneWidget,
    );
  });

  testWidgets('unavailable linked tasks fall back to Done', (tester) async {
    for (final task in [_task(status: 'completed'), _task(isDeleted: true)]) {
      final container = _container(taskRepository: _TaskRepository(task));
      container
          .read(focusRunCompletionControllerProvider.notifier)
          .present(
            _completion(
              runId: 'run-${task.status}-${task.isDeleted}',
              taskId: task.id,
              taskTitle: task.content,
            ),
          );

      await _pumpCelebration(tester, container: container);
      await tester.pump();

      expect(
        find.byKey(const Key('focus-completion-complete-task')),
        findsNothing,
      );
      expect(find.byKey(const Key('focus-completion-done')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    }
  });

  testWidgets('suggests the next task by start time relative to current task', (
    tester,
  ) async {
    final currentStart = DateTime(2026, 8, 19, 9);
    final current = _task(
      id: 'current',
      content: 'Current task',
      orderKey: '1',
      schedule: TaskSchedule.timed(
        start: currentStart,
        end: currentStart.add(const Duration(hours: 3)),
      ),
    );
    final container = _container(
      taskRepository: _TaskRepository(current),
      tasks: [
        current,
        _task(
          id: 'earlier',
          content: 'Earlier task',
          schedule: _timed(currentStart.subtract(const Duration(minutes: 30))),
        ),
        _task(
          id: 'equal',
          content: 'Same-time task',
          orderKey: '2',
          schedule: _timed(currentStart),
        ),
        _task(
          id: 'completed',
          content: 'Completed task',
          status: 'completed',
          schedule: _timed(currentStart.add(const Duration(minutes: 10))),
        ),
        _task(
          id: 'deleted',
          content: 'Deleted task',
          isDeleted: true,
          schedule: _timed(currentStart.add(const Duration(minutes: 20))),
        ),
        _task(
          id: 'all-day',
          content: 'All-day task',
          schedule: TaskSchedule.allDay(DateTime(2026, 8, 20)),
        ),
        _task(id: 'unscheduled', content: 'Unscheduled task'),
        _task(
          id: 'later',
          content: 'Later task',
          schedule: _timed(currentStart.add(const Duration(hours: 1))),
        ),
        _task(
          id: 'next',
          content: 'Next task',
          orderKey: '3',
          schedule: _timed(currentStart.add(const Duration(minutes: 30))),
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(focusRunCompletionControllerProvider.notifier)
        .present(
          _completion(
            taskId: 'current',
            taskTitle: 'Current task',
            completedAt: DateTime(2026, 8, 19, 17, 42),
          ),
        );

    await _pumpCelebration(tester, container: container);
    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const Key('focus-completion-next-task')), findsOneWidget);
    expect(find.text('Same-time task'), findsOneWidget);
    expect(find.text('Earlier task'), findsNothing);
    expect(find.text('Next task'), findsNothing);
    expect(find.text('Later task'), findsNothing);
    expect(find.text('Today 9:00 AM'), findsOneWidget);
  });

  testWidgets('suggested task starts focus and dismisses celebration', (
    tester,
  ) async {
    final focusRepository = _FocusRepository();
    final currentTask = _task(
      id: 'current',
      content: 'Current task',
      schedule: _timed(DateTime(2026, 8, 19, 12)),
    );
    final taskRepository = _TaskRepository(currentTask);
    final nextTask = _task(
      id: 'next',
      content: 'Start next task',
      projectId: 'project-next',
      schedule: TaskSchedule.timed(
        start: DateTime(2026, 8, 19, 13),
        end: DateTime(2026, 8, 19, 14),
      ),
    );
    final container = _container(
      taskRepository: taskRepository,
      tasks: [currentTask, nextTask],
      focusRepository: focusRepository,
      presets: [_preset()],
    );
    addTearDown(container.dispose);
    container
        .read(focusRunCompletionControllerProvider.notifier)
        .present(
          _completion(
            taskId: 'current',
            taskTitle: 'Current task',
            completedAt: DateTime(2026, 8, 19, 17),
          ),
        );

    await _pumpCelebration(tester, container: container);
    await tester.pump(const Duration(seconds: 2));
    final start = find.byKey(const Key('focus-completion-start-next-task'));
    expect(start, findsOneWidget);
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pumpAndSettle();

    expect(focusRepository.startInputs, hasLength(1));
    final input = focusRepository.startInputs.single;
    expect(input.taskId, 'next');
    expect(input.projectId, 'project-next');
    expect(input.presetId, 'preset-1');
    expect(input.targetWorkIntervals, 2);
    expect(taskRepository.completeCount, 1);
    expect(taskRepository.uncompleteCount, 0);
    expect(find.byKey(const Key('focus-completion-overlay')), findsNothing);
  });

  testWidgets('suggested task start failure keeps celebration open', (
    tester,
  ) async {
    final focusRepository = _FocusRepository(
      startError: StateError('start failed'),
    );
    final currentTask = _task(
      id: 'current',
      content: 'Current task',
      schedule: _timed(DateTime(2026, 8, 19, 12)),
    );
    final taskRepository = _TaskRepository(currentTask);
    final container = _container(
      taskRepository: taskRepository,
      tasks: [
        currentTask,
        _task(
          id: 'next',
          content: 'Start next task',
          schedule: _timed(DateTime(2026, 8, 19, 13)),
        ),
      ],
      focusRepository: focusRepository,
    );
    addTearDown(container.dispose);
    container
        .read(focusRunCompletionControllerProvider.notifier)
        .present(
          _completion(
            taskId: 'current',
            taskTitle: 'Current task',
            completedAt: DateTime(2026, 8, 19, 17),
          ),
        );

    await _pumpCelebration(tester, container: container);
    await tester.pump(const Duration(seconds: 2));
    final start = find.byKey(const Key('focus-completion-start-next-task'));
    expect(start, findsOneWidget);
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pumpAndSettle();

    expect(taskRepository.completeCount, 1);
    expect(taskRepository.uncompleteCount, 1);
    expect(find.byKey(const Key('focus-completion-overlay')), findsOneWidget);
    expect(
      find.text('Could not start Focus: Bad state: start failed'),
      findsOneWidget,
    );
  });

  testWidgets('celebration stages particles and content entrance', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    container
        .read(focusRunCompletionControllerProvider.notifier)
        .present(_completion());

    await _pumpCelebration(tester, container: container);

    expect(find.byKey(const Key('focus-completion-particles')), findsOneWidget);
    final initial = tester.widget<FadeTransition>(
      find.byKey(const Key('focus-completion-content-entrance')),
    );
    expect(initial.opacity.value, 0);

    await tester.pump(const Duration(milliseconds: 900));
    final midway = tester.widget<FadeTransition>(
      find.byKey(const Key('focus-completion-content-entrance')),
    );
    expect(midway.opacity.value, greaterThan(0));
    expect(midway.opacity.value, lessThan(1));

    await tester.pumpAndSettle();
    final finished = tester.widget<FadeTransition>(
      find.byKey(const Key('focus-completion-content-entrance')),
    );
    expect(finished.opacity.value, 1);
  });

  testWidgets(
    'reduced motion presents a static celebration without particles',
    (tester) async {
      final container = _container();
      addTearDown(container.dispose);
      container
          .read(focusRunCompletionControllerProvider.notifier)
          .present(_completion());

      await _pumpCelebration(
        tester,
        container: container,
        disableAnimations: true,
      );

      expect(find.byKey(const Key('focus-completion-particles')), findsNothing);
      final content = tester.widget<FadeTransition>(
        find.byKey(const Key('focus-completion-content-entrance')),
      );
      expect(content.opacity.value, 1);
    },
  );

  testWidgets('compact dark RTL layout stays scrollable and announces result', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = _container(
      tasks: [
        _task(
          id: 'next',
          content: 'Next compact task',
          schedule: _timed(DateTime.utc(2026, 8, 19, 13)),
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(focusRunCompletionControllerProvider.notifier)
        .present(_completion());

    await _pumpCelebration(
      tester,
      container: container,
      disableAnimations: true,
      locale: const Locale('ar'),
      darkMode: true,
    );
    await tester.pump();

    final overlay = find.byKey(const Key('focus-completion-overlay'));
    expect(Directionality.of(tester.element(overlay)), TextDirection.rtl);
    expect(tester.takeException(), isNull);
    final announcement = tester.getSemantics(
      find.byKey(const Key('focus-completion-announcement')),
    );
    expect(announcement.label, 'عمل رائع! اكتملت دورة التركيز.');
    expect(announcement.textDirection, TextDirection.rtl);
    expect(announcement.flagsCollection.isLiveRegion, isTrue);

    final startNext = find.byKey(const Key('focus-completion-start-next-task'));
    expect(startNext, findsOneWidget);
    await tester.ensureVisible(startNext);
    expect(tester.takeException(), isNull);

    final done = find.byKey(const Key('focus-completion-done'));
    expect(
      tester.getSemantics(done),
      matchesSemantics(
        label: 'تم',
        textDirection: TextDirection.rtl,
        hasEnabledState: true,
        isEnabled: true,
        isButton: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    await tester.ensureVisible(done);
    await tester.tap(done);
    await tester.pumpAndSettle();
    expect(overlay, findsNothing);
    semantics.dispose();
  });

  testWidgets('linked completion waits for task resolution before actions', (
    tester,
  ) async {
    final taskRepository = _DelayedTaskRepository();
    addTearDown(taskRepository.dispose);
    final container = _container(taskRepository: taskRepository);
    addTearDown(container.dispose);
    container
        .read(focusRunCompletionControllerProvider.notifier)
        .present(_completion(taskId: 'task-1', taskTitle: 'Ship celebration'));

    await _pumpCelebration(tester, container: container);
    await tester.pump(const Duration(seconds: 2));

    expect(
      find.byKey(const Key('focus-completion-task-loading')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('focus-completion-done')), findsNothing);
    expect(
      find.byKey(const Key('focus-completion-complete-task')),
      findsNothing,
    );

    taskRepository.add(_task());
    await tester.pump();

    expect(
      find.byKey(const Key('focus-completion-complete-task')),
      findsOneWidget,
    );
  });
}

ProviderContainer _container({
  TaskRepository? taskRepository,
  List<TaskItem> tasks = const [],
  FocusRepository? focusRepository,
  List<FocusPresetItem> presets = const [],
}) {
  return ProviderContainer(
    overrides: [
      taskRepositoryProvider.overrideWithValue(
        taskRepository ?? _TaskRepository(null),
      ),
      tasksByQueryProvider.overrideWith((ref, query) => Stream.value(tasks)),
      focusPresetsProvider.overrideWith((ref) => Stream.value(presets)),
      if (focusRepository != null)
        focusRepositoryProvider.overrideWithValue(focusRepository),
    ],
  );
}

Future<void> _pumpCelebration(
  WidgetTester tester, {
  required ProviderContainer container,
  bool disableAnimations = false,
  Locale? locale,
  bool darkMode = false,
}) {
  return tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: darkMode ? AppTheme.dark() : AppTheme.light(),
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: Colors.blue),
              FocusRunCompletionCelebrationSlot(),
            ],
          ),
        ),
      ),
    ),
  );
}

FocusRunCompletionEvent _completion({
  String runId = 'run-1',
  String? taskId,
  String? taskTitle,
  DateTime? completedAt,
}) {
  return FocusRunCompletionEvent(
    runId: runId,
    taskId: taskId,
    taskTitle: taskTitle,
    completedWorkIntervals: 4,
    targetWorkIntervals: 4,
    completedAt: completedAt ?? DateTime.utc(2026, 8, 19, 12),
  );
}

TaskItem _task({
  String id = 'task-1',
  String content = 'Ship celebration',
  String projectId = 'project-1',
  String status = 'open',
  bool isDeleted = false,
  String orderKey = '1',
  TaskSchedule? schedule,
}) {
  final now = DateTime.utc(2026, 8, 19, 12);
  return TaskItem(
    id: id,
    userId: 'local',
    content: content,
    projectId: projectId,
    priority: 1,
    dueJson: schedule?.toJsonString(),
    status: status,
    completedFocusIntervals: 4,
    totalFocusSeconds: 6000,
    orderKey: orderKey,
    isDeleted: isDeleted,
    createdAt: now,
    updatedAt: now,
  );
}

TaskSchedule _timed(DateTime start) => TaskSchedule.timed(
  start: start,
  end: start.add(const Duration(minutes: 30)),
);

FocusPresetItem _preset() {
  final now = DateTime.utc(2026, 8, 19, 12);
  return FocusPresetItem(
    id: 'preset-1',
    userId: 'local',
    name: 'Pomodoro',
    workSeconds: 25 * 60,
    shortBreakSeconds: 5 * 60,
    longBreakSeconds: 15 * 60,
    intervalsBeforeLongBreak: 4,
    autoStartBreaks: false,
    autoStartWork: false,
    allowPause: true,
    strictMode: false,
    isDefault: true,
    createdAt: now,
    updatedAt: now,
  );
}

class _TaskRepository implements TaskRepository {
  _TaskRepository(this.task, {this.completeError});

  final TaskItem? task;
  final Object? completeError;
  int completeCount = 0;
  int uncompleteCount = 0;

  @override
  Stream<TaskItem?> watchTask(String id) => Stream.value(task);

  @override
  Future<void> completeTask(String id) async {
    completeCount++;
    if (completeError case final error?) {
      throw error;
    }
  }

  @override
  Future<void> uncompleteTask(String id) async {
    uncompleteCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedTaskRepository implements TaskRepository {
  final StreamController<TaskItem?> _controller =
      StreamController<TaskItem?>.broadcast();

  void add(TaskItem? task) => _controller.add(task);

  Future<void> dispose() => _controller.close();

  @override
  Stream<TaskItem?> watchTask(String id) => _controller.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FocusRepository implements FocusRepository {
  _FocusRepository({this.startError});

  final Object? startError;
  final List<StartFocusRunInput> startInputs = [];

  @override
  Future<String> startRun(StartFocusRunInput input, {DateTime? now}) async {
    startInputs.add(input);
    if (startError case final error?) {
      throw error;
    }
    return 'new-run';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
