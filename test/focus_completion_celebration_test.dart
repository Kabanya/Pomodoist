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
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(focusRunCompletionControllerProvider.notifier)
        .present(_completion());

    await _pumpCelebration(tester, container: container);

    expect(find.byKey(const Key('focus-completion-overlay')), findsOneWidget);
    expect(find.byKey(const Key('focus-completion-done')), findsOneWidget);
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
    final container = ProviderContainer(
      overrides: [taskRepositoryProvider.overrideWithValue(taskRepository)],
    );
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
    final container = ProviderContainer(
      overrides: [taskRepositoryProvider.overrideWithValue(taskRepository)],
    );
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
    final container = ProviderContainer(
      overrides: [taskRepositoryProvider.overrideWithValue(taskRepository)],
    );
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
      final container = ProviderContainer(
        overrides: [
          taskRepositoryProvider.overrideWithValue(_TaskRepository(task)),
        ],
      );
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

  testWidgets('celebration stages particles and content entrance', (
    tester,
  ) async {
    final container = ProviderContainer();
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
      final container = ProviderContainer();
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
    final container = ProviderContainer();
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

    final overlay = find.byKey(const Key('focus-completion-overlay'));
    expect(Directionality.of(tester.element(overlay)), TextDirection.rtl);
    expect(tester.takeException(), isNull);
    final announcement = tester.getSemantics(
      find.byKey(const Key('focus-completion-announcement')),
    );
    expect(announcement.label, 'عمل رائع! اكتملت دورة التركيز.');
    expect(announcement.textDirection, TextDirection.rtl);
    expect(announcement.flagsCollection.isLiveRegion, isTrue);

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
    final container = ProviderContainer(
      overrides: [taskRepositoryProvider.overrideWithValue(taskRepository)],
    );
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
}) {
  return FocusRunCompletionEvent(
    runId: runId,
    taskId: taskId,
    taskTitle: taskTitle,
    completedWorkIntervals: 4,
    targetWorkIntervals: 4,
    completedAt: DateTime.utc(2026, 8, 19, 12),
  );
}

TaskItem _task({String status = 'open', bool isDeleted = false}) {
  final now = DateTime.utc(2026, 8, 19, 12);
  return TaskItem(
    id: 'task-1',
    userId: 'local',
    content: 'Ship celebration',
    projectId: 'project-1',
    priority: 1,
    status: status,
    completedFocusIntervals: 4,
    totalFocusSeconds: 6000,
    orderKey: '1',
    isDeleted: isDeleted,
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
