import 'package:flutter/material.dart';
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
    urgentId = urgent ? task.id : null;
    return const Result.ok(null);
  }
}
