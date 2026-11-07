import 'package:pomodoist/routing/task_detail_navigation.dart';
import 'package:pomodoist/utils/result.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/widgets/task_list_item.dart';
import 'package:pomodoist/ui/tasks/widgets/task_selection_region.dart';
import 'package:pomodoist/ui/tasks/view_models/task_subtask_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../testing/fakes/fake_task_repository.dart';
import '../upcoming_screen_test.dart' show pumpUpcomingForTest;
import '../support/test_app.dart';
import 'task_performance_test.dart' show CountedTask, now;

void main() {
  setUpAll(loadTestAppResources);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  for (final query in [
    const TaskQuery.inbox(),
    TaskQuery(kind: TaskQueryKind.today, now: now),
  ]) {
    testWidgets('${query.kind} title update leaves other cards unchanged', (
      tester,
    ) async {
      final stream = StreamController<List<TaskItem>>.broadcast();
      addTearDown(stream.close);
      final tasks = List.generate(40, (i) => CountedTask('$i'));
      await pumpUpcomingForTest(
        tester,
        today: now,
        tasks: tasks,
        listQuery: query,
        allStream: stream.stream,
        settle: false,
      );
      stream.add(tasks);
      await tester.pumpAndSettle();
      final rebuilt = <String>[];
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, built) {
        previous?.call(element, built);
        if (element.widget case TaskListItem(:final task)) rebuilt.add(task.id);
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      stream.add([_rename(tasks.first, 'New title'), ...tasks.skip(1)]);
      await tester.pumpAndSettle();
      expect(find.text('New title'), findsOneWidget);
      expect(rebuilt.where((id) => id != '0'), isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in [390.0, 760.0, 1280.0]) {
    for (final dark in [false, true]) {
      testWidgets('agenda $width dark=$dark 200% RTL Reduce Motion', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final task = _rename(
          CountedTask('long'),
          List.filled(12, 'عنوان مهمة طويل').join(' '),
        );
        await pumpUpcomingForTest(
          tester,
          today: now,
          tasks: [task],
          locale: const Locale('ar'),
          textScale: 2,
          reduceMotion: true,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('long')),
          400,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('upcoming-scroll-view')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.text(task.content), findsOneWidget);
        expect(
          Directionality.of(tester.element(find.text(task.content))),
          TextDirection.rtl,
        );
        expect(
          MediaQuery.disableAnimationsOf(
            tester.element(find.text(task.content)),
          ),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('offscreen rows stay selectable and bulk priority targets them', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final tasks = List.generate(1000, (i) => CountedTask('$i'));
    final repository = FakeTaskRepository()..tasks = tasks;
    await pumpUpcomingForTest(
      tester,
      today: now,
      tasks: tasks,
      repository: repository,
    );
    final controller = TaskSelectionScope.maybeOf(
      tester.element(find.byType(TaskListItem).first),
    )!;
    expect(controller.visibleTasks.length, 1000);
    expect(find.byType(TaskListItem).evaluate().length, lessThanOrEqualTo(40));
    controller.begin('0');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-selection-toggle-all')));
    await tester.pumpAndSettle();
    expect(controller.selectedCount, 1000);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TaskListItem).first),
    );
    expect(container.read(taskRepositoryProvider), same(repository));
    final action = controller.showPriority(
      tester.element(find.byType(TaskListItem).first),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Priority 1').last);
    await tester.pumpAndSettle();
    await action;
    expect(repository.updatedIds.toSet(), tasks.map((t) => t.id).toSet());
    expect(repository.updatedPatches.every((p) => p.priority == 1), isTrue);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('Quick Add draft and focus survive task refresh and scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final stream = StreamController<List<TaskItem>>();
    addTearDown(stream.close);
    final tasks = List.generate(40, (i) => CountedTask('$i'));
    await pumpUpcomingForTest(
      tester,
      today: now,
      tasks: tasks,
      allStream: stream.stream,
      settle: false,
    );
    stream.add(tasks);
    await tester.pumpAndSettle();
    final input = find.byType(EditableText).first;
    await tester.enterText(input, 'Unsubmitted draft');
    await tester.pump();
    final before = tester.widget<EditableText>(input);
    expect(before.focusNode.hasFocus, isTrue);
    stream.add([_rename(tasks.first, 'Changed'), ...tasks.skip(1)]);
    await tester.pumpAndSettle();
    final scroll = tester.widget<CustomScrollView>(
      find.byKey(const ValueKey('upcoming-scroll-view')),
    );
    scroll.controller!.jumpTo(scroll.controller!.position.maxScrollExtent);
    await tester.pumpAndSettle();
    scroll.controller!.jumpTo(0);
    await tester.pumpAndSettle();
    final after = tester.widget<EditableText>(find.byType(EditableText).first);
    expect(after.controller.text, 'Unsubmitted draft');
    expect(after.focusNode, same(before.focusNode));
    expect(after.focusNode.hasFocus, isTrue);
  });
  testWidgets('completion and Undo keep the lazy task and available actions', (
    tester,
  ) async {
    final tasks = List.generate(40, (i) => CountedTask('$i'));
    final repository = _ChangingRepository(tasks);
    addTearDown(repository.open.close);
    addTearDown(repository.done.close);
    await pumpUpcomingForTest(
      tester,
      today: now,
      tasks: tasks,
      repository: repository,
      allStream: repository.open.stream,
      completedStream: repository.done.stream,
      settle: false,
    );
    repository.emit();
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();

    expect(find.byTooltip('Mark complete'), findsWidgets);
    await tester.tap(find.byKey(const Key('task-completion-control-0')));
    await tester.pumpAndSettle();
    expect(repository.completed, ['0']);
    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(repository.uncompleted, ['0']);
    expect(find.byKey(const ValueKey('0')), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('branch collapse excludes descendants from logical selection', (
    tester,
  ) async {
    final parent = CountedTask('parent');
    final child = CountedTask('child', parent: 'parent');
    await pumpUpcomingForTest(tester, today: now, tasks: [parent, child]);
    expect(find.byKey(const ValueKey('child')), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TaskListItem).first),
    );
    await container
        .read(taskPreferencesRepositoryProvider)
        .setBranchExpanded('upcoming', 'parent', false);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('child')), findsNothing);
    final selection = TaskSelectionScope.maybeOf(
      tester.element(find.byType(TaskListItem).first),
    )!;
    expect(selection.visibleTasks.map((t) => t.id), ['parent']);
    await tester.tap(find.byKey(const ValueKey('task-branch-toggle-parent')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('child')), findsOneWidget);
  });
  testWidgets('opening and closing details preserves a scrolled agenda', (
    tester,
  ) async {
    final tasks = List.generate(
      40,
      (i) => CountedTask('$i', day: now.add(Duration(days: i))),
    );
    final harness = await pumpUpcomingForTest(tester, today: now, tasks: tasks);
    final scrollable = find
        .descendant(
          of: find.byKey(const ValueKey('upcoming-scroll-view')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('39')),
      400,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    final scroll = tester.widget<CustomScrollView>(
      find.byKey(const ValueKey('upcoming-scroll-view')),
    );
    final position = scroll.controller!.offset;
    await tester.tap(find.text('39'));
    await tester.pumpAndSettle();
    expect(
      harness.router.routeInformationProvider.value.uri.queryParameters['task'],
      '39',
    );
    expect(scroll.controller!.offset, closeTo(position, 1));
    closeTaskDetails(tester.element(find.byKey(const ValueKey('39'))));
    await tester.pumpAndSettle();
    expect(
      harness.router.routeInformationProvider.value.uri.queryParameters['task'],
      isNull,
    );
    expect(scroll.controller!.offset, closeTo(position, 1));
  });
  testWidgets('removing the last unscheduled child clears progress', (
    tester,
  ) async {
    final stream = StreamController<List<TaskItem>>();
    addTearDown(stream.close);
    final parent = CountedTask('parent');
    final child = TaskItem(
      id: 'child',
      userId: 'u',
      content: 'child',
      projectId: inboxProjectId,
      parentId: 'parent',
      priority: 4,
      status: 'open',
      completedFocusIntervals: 0,
      totalFocusSeconds: 0,
      orderKey: 'child',
      isDeleted: false,
      createdAt: now,
      updatedAt: now,
    );
    await pumpUpcomingForTest(
      tester,
      today: now,
      tasks: [parent, child],
      allStream: stream.stream,
      settle: false,
    );
    stream.add([parent, child]);
    await tester.pumpAndSettle();
    expect(find.text('0/1'), findsOneWidget);
    stream.add([parent]);
    await tester.pumpAndSettle();
    expect(find.text('0/1'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test(
    'bottom-up progress matches cycle-safe traversal for corrupt graphs',
    () {
      final random = Random(17);
      for (var sample = 0; sample < 100; sample++) {
        final tasks = List.generate(
          40,
          (i) => CountedTask(
            '$i',
            parent: random.nextBool() ? '${random.nextInt(45)}' : null,
            completed: random.nextBool(),
          ),
        );
        final actual = taskSubtaskProgressById(tasks);
        final byId = {for (final t in tasks) t.id: t};
        final expected = <String, TaskSubtaskProgress>{};
        for (final task in tasks) {
          final visited = {task.id};
          final pending = [
            for (final t in tasks)
              if (t.parentId == task.id) t.id,
          ];
          var completed = 0;
          while (pending.isNotEmpty) {
            final id = pending.removeLast();
            if (!visited.add(id)) continue;
            if (byId[id]!.isCompleted) completed++;
            pending.addAll(
              tasks.where((t) => t.parentId == id).map((t) => t.id),
            );
          }
          if (visited.length > 1) {
            expected[task.id] = TaskSubtaskProgress(
              completed: completed,
              total: visited.length - 1,
            );
          }
        }
        expect(actual, expected);
      }
    },
  );
}

TaskItem _rename(TaskItem task, String content) => TaskItem(
  id: task.id,
  userId: task.userId,
  content: content,
  projectId: task.projectId,
  priority: task.priority,
  dueJson: task.dueJson,
  status: task.status,
  completedFocusIntervals: 0,
  totalFocusSeconds: 0,
  orderKey: task.orderKey,
  isDeleted: false,
  createdAt: task.createdAt,
  updatedAt: task.updatedAt,
);

class _ChangingRepository extends FakeTaskRepository {
  _ChangingRepository(List<TaskItem> initial) {
    tasks = initial;
  }
  final open = StreamController<List<TaskItem>>.broadcast();
  final done = StreamController<List<TaskItem>>.broadcast();
  void emit() {
    open.add(tasks.where((t) => !t.isCompleted).toList());
    done.add(tasks.where((t) => t.isCompleted).toList());
  }

  @override
  Stream<TaskItem?> watchTask(String id) =>
      Stream.value(tasks.firstWhere((t) => t.id == id));
  void change(String id, String status) {
    tasks = [
      for (final t in tasks)
        if (t.id == id)
          TaskItem(
            id: t.id,
            userId: t.userId,
            content: t.content,
            projectId: t.projectId,
            priority: t.priority,
            dueJson: t.dueJson,
            status: status,
            completedFocusIntervals: 0,
            totalFocusSeconds: 0,
            orderKey: t.orderKey,
            isDeleted: false,
            createdAt: t.createdAt,
            updatedAt: t.updatedAt,
          )
        else
          t,
    ];
    emit();
  }

  @override
  Future<Result<void>> completeTask(String id) async {
    change(id, 'completed');
    return super.completeTask(id);
  }

  @override
  Future<Result<void>> uncompleteTask(String id) async {
    change(id, 'open');
    return super.uncompleteTask(id);
  }
}
