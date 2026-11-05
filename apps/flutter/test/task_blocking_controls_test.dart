import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'support/test_app.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository.dart';
import 'package:pomodoist/data/repositories/tasks/task_blocking_repository.dart';
import 'package:pomodoist/utils/result.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/task_blocking_dependencies.dart';
import 'package:pomodoist/domain/models/tasks/task_blocking.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/widgets/task_blocking_controls.dart';

TaskItem item(String id, {List<String> needs = const []}) => TaskItem(
  id: id,
  userId: 'me',
  content: id,
  projectId: 'inbox',
  priority: 4,
  status: 'open',
  completedFocusIntervals: 0,
  totalFocusSeconds: 0,
  orderKey: id,
  isDeleted: false,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  prerequisiteIds: needs,
);
void main() {
  setUpAll(loadTestAppResources);
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.macOS,
  ]) {
    for (final urgent in [false, true]) {
      testWidgets('task menu toggles urgency on $platform from $urgent', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          final task = item('Task');
          final blocking = _Blocking();
          await _pumpTaskMenu(tester, task, blocking, urgent: urgent);

          expect(
            find.byKey(const ValueKey('task-blocking-expand-Task')),
            findsNothing,
          );
          expect(find.byIcon(LucideIcons.flame), findsNothing);
          await _openTaskMenu(tester, platform);
          expect(find.text('Existing action'), findsOneWidget);
          expect(
            find.byIcon(LucideIcons.check),
            urgent ? findsOneWidget : findsNothing,
          );
          await tester.tap(find.text('Urgent for me'));
          await tester.pumpAndSettle();
          expect(blocking.urgentId, urgent ? null : task.id);
          expect(blocking.urgentWrites, 1);
          expect(tester.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }
  testWidgets('existing task menu remains available while policy loads', (
    tester,
  ) async {
    await _pumpTaskMenu(
      tester,
      item('Task'),
      _Blocking(),
      policies: const Stream.empty(),
    );
    await _openTaskMenu(tester, TargetPlatform.macOS);
    expect(find.text('Existing action'), findsOneWidget);
    expect(find.text('Urgent for me'), findsNothing);
  });
  testWidgets('task menu stays open when blocking policy finishes loading', (
    tester,
  ) async {
    final task = item('Task');
    final policy = Completer<TaskBlockingPolicy>();
    await _pumpTaskMenu(
      tester,
      task,
      _Blocking(),
      policies: policy.future.asStream(),
    );
    await _openTaskMenu(tester, TargetPlatform.macOS);
    policy.complete(TaskBlockingPolicy(tasks: [task], actorId: 'me'));
    await tester.pumpAndSettle();
    expect(find.text('Existing action'), findsOneWidget);
    expect(find.text('Urgent for me'), findsOneWidget);
  });
  testWidgets('urgency failure remains visible after the menu closes', (
    tester,
  ) async {
    await _pumpTaskMenu(tester, item('Task'), _Blocking()..failUrgent = true);
    await _openTaskMenu(tester, TargetPlatform.macOS);
    await tester.tap(find.text('Urgent for me'));
    await tester.pumpAndSettle();
    expect(find.text('Existing action'), findsNothing);
    expect(find.textContaining('unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'inline dependency, urgency and cascade controls dispatch changes',
    (tester) async {
      final first = item('First');
      final second = item('Second');
      final tasks = _Tasks();
      final blocking = _Blocking();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            taskRepositoryProvider.overrideWithValue(tasks),
            taskBlockingRepositoryProvider.overrideWithValue(blocking),
            taskBlockingPolicyProvider.overrideWith(
              (ref) => Stream.value(
                TaskBlockingPolicy(tasks: [first, second], actorId: 'me'),
              ),
            ),
            taskBlockingConflictsProvider.overrideWith(
              (ref) => Stream.value(<String>{}),
            ),
          ],
          child: MaterialApp(
            builder: testAppBuilder,
            home: Scaffold(
              body: Column(
                children: [
                  const TaskPriorityCascadeControl(),
                  TaskBlockingControls(task: second, initiallyExpanded: true),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), 'First');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();
      expect(tasks.needs, ['First']);
      await tester.tap(find.text('Urgent for me'));
      await tester.pumpAndSettle();
      expect(blocking.urgentId, 'Second');
      await tester.tap(find.byKey(const ValueKey('task-priority-cascade')));
      await tester.pumpAndSettle();
      expect(blocking.cascade, isTrue);
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'inline disclosure supports keyboard and labeled controls in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final task = item('First');
        final dependent = item('Affected ' * 20, needs: ['First']);
        final policy = TaskBlockingPolicy(
          tasks: [task, dependent],
          actorId: 'me',
        );
        final container = ProviderContainer(
          overrides: [
            taskBlockingConflictsProvider.overrideWith(
              (ref) => Stream.value(<String>{'First'}),
            ),
            taskBlockingPolicyProvider.overrideWith(
              (ref) => Stream.value(policy),
            ),
          ],
        );
        addTearDown(container.dispose);
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              builder: testAppBuilder,
              theme: ThemeData(brightness: brightness),
              home: Scaffold(body: TaskBlockingControls(task: task)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('task-dependency-search-First')),
          findsOneWidget,
        );
        expect(
          find.textContaining('accumulated Focus is preserved'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        expect(tester, meetsGuideline(labeledTapTargetGuideline));
        container
            .read(inlineTaskDeleteRequestsProvider.notifier)
            .request(task.id, () async {});
        await tester.pumpAndSettle();
        expect(find.text(dependent.content), findsOneWidget);
        expect(find.byType(Dialog), findsNothing);
        semantics.dispose();
      },
    );
  }
  testWidgets(
    'inline controls expose blocker navigation and editable dependencies without a dialog',
    (tester) async {
      final a = item('First');
      final b = item('Second', needs: ['First']);
      final policy = TaskBlockingPolicy(tasks: [a, b], actorId: 'me');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            taskBlockingConflictsProvider.overrideWith(
              (ref) => Stream.value(<String>{}),
            ),
            taskBlockingPolicyProvider.overrideWith(
              (ref) => Stream.value(policy),
            ),
          ],
          child: MaterialApp(
            builder: testAppBuilder,
            home: Scaffold(body: TaskBlockingControls(task: b)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(LucideIcons.lockKeyhole), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('task-blocking-expand-Second')),
      );
      await tester.pumpAndSettle();
      expect(find.text('First'), findsWidgets);
      expect(
        find.byKey(const ValueKey('task-dependency-search-Second')),
        findsOneWidget,
      );
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Urgent for me'), findsOneWidget);
    },
  );
}

Future<void> _pumpTaskMenu(
  WidgetTester tester,
  TaskItem task,
  _Blocking blocking, {
  bool urgent = false,
  Stream<TaskBlockingPolicy>? policies,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        taskBlockingRepositoryProvider.overrideWithValue(blocking),
        taskBlockingConflictsProvider.overrideWith(
          (_) => Stream.value(<String>{}),
        ),
        taskBlockingPolicyProvider.overrideWith(
          (_) =>
              policies ??
              Stream.value(
                TaskBlockingPolicy(
                  tasks: [task],
                  actorId: 'me',
                  urgentSelections: {
                    if (urgent)
                      'personal': UrgentTaskSelection(taskId: task.id),
                  },
                ),
              ),
        ),
      ],
      child: MaterialApp(
        builder: testAppBuilder,
        home: Scaffold(
          body: TaskBlockingControls(
            task: task,
            menuItems: [
              ShadContextMenuItem(
                onPressed: () {},
                child: const Text('Existing action'),
              ),
            ],
            child: const SizedBox(width: 300, height: 48, child: Text('Task')),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openTaskMenu(WidgetTester tester, TargetPlatform platform) async {
  if (platform == TargetPlatform.android || platform == TargetPlatform.iOS) {
    await tester.longPress(find.text('Task'));
  } else {
    await tester.tap(find.text('Task'), buttons: kSecondaryMouseButton);
  }
  await tester.pumpAndSettle();
}

class _Tasks extends Fake implements TaskRepository {
  List<String>? needs;
  @override
  Future<Result<void>> updateTask(String id, UpdateTaskPatch patch) async {
    needs = patch.prerequisiteIds;
    return const Result.ok(null);
  }
}

class _Blocking extends Fake implements DriftTaskBlockingRepository {
  bool cascade = false;
  String? urgentId;
  int urgentWrites = 0;
  bool failUrgent = false;
  @override
  Future<Result<void>> setCascade(bool enabled) async {
    cascade = enabled;
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> setUrgent(
    TaskItem task, {
    required bool urgent,
    bool repeatWithSeries = true,
  }) async {
    urgentWrites++;
    if (failUrgent) throw StateError('offline');
    urgentId = urgent ? task.id : null;
    return const Result.ok(null);
  }
}
