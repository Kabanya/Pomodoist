import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/app/theme/app_theme.dart';
import 'package:pomodoist/core/db/app_database.dart' hide KanbanSettings;
import 'package:pomodoist/features/focus/domain/focus_models.dart';
import 'package:pomodoist/features/planning/data/quick_add_service.dart';
import 'package:pomodoist/features/planning/domain/quick_add_parser.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';
import 'package:pomodoist/features/tasks/presentation/kanban/kanban_board_controller.dart';
import 'package:pomodoist/features/tasks/presentation/kanban/kanban_screen.dart';
import 'package:pomodoist/l10n/app_localizations.dart';

void main() {
  testWidgets('820 uses independent fixed-width desktop columns', (
    tester,
  ) async {
    final harness = await _pumpKanban(tester, width: 820);

    expect(find.byKey(const Key('kanban-desktop-board')), findsOneWidget);
    expect(find.byKey(const Key('kanban-mobile-board')), findsNothing);
    expect(
      tester
          .getSize(find.byKey(const Key('kanban-column-kanban-status-todo-v1')))
          .width,
      288,
    );
    expect(
      tester
          .getSize(
            find.byKey(const Key('kanban-column-kanban-status-in-progress-v1')),
          )
          .width,
      360,
    );
    expect(
      find.byKey(const Key('kanban-drag-handle-task-focus')),
      findsOneWidget,
    );
    expect(harness.kanban.moves, isEmpty);
  });

  testWidgets('819 uses one-open mobile accordion with focus expanded', (
    tester,
  ) async {
    await _pumpKanban(tester, width: 819);

    expect(find.byKey(const Key('kanban-mobile-board')), findsOneWidget);
    expect(find.byKey(const Key('kanban-desktop-board')), findsNothing);
    expect(find.byKey(const Key('kanban-section-expanded')), findsOneWidget);
    expect(
      find.byKey(const Key('kanban-long-press-task-focus')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('kanban-section-header-kanban-status-todo-v1')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('kanban-section-expanded')), findsOneWidget);
    expect(find.byKey(const Key('kanban-long-press-task-focus')), findsNothing);
    expect(
      find.byKey(const Key('kanban-add-kanban-status-todo-v1')),
      findsOneWidget,
    );
  });

  testWidgets('menu move and column add inherit the selected status', (
    tester,
  ) async {
    final harness = await _pumpKanban(tester, width: 1200);

    await tester.tap(find.byKey(const Key('kanban-card-menu-task-focus')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to To do'));
    await tester.pump();

    expect(harness.kanban.moves.single.statusId, kanbanStatusTodoId);

    await tester.tap(find.byKey(const Key('kanban-add-kanban-status-todo-v1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kanban-add-voice')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('kanban-add-input')),
      'Added in Todo',
    );
    await tester.tap(find.byKey(const Key('kanban-add-submit')));
    await tester.pumpAndSettle();

    expect(harness.tasks.created.single.content, 'Added in Todo');
    expect(harness.tasks.created.single.kanbanStatusId, kanbanStatusTodoId);
    expect(harness.tasks.created.single.projectId, inboxProjectId);
  });

  testWidgets('hiding Done keeps card completion available', (tester) async {
    final harness = await _pumpKanban(tester, width: 1200);

    await tester.tap(find.byKey(const Key('kanban-filter-toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('kanban-column-$kanbanStatusDoneId')), findsNothing);
    expect(find.byKey(const Key('kanban-card-task-focus')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('kanban-card-menu-task-focus')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark complete'));
    await tester.pump();

    expect(harness.kanban.moves.single.statusId, kanbanStatusDoneId);
  });

  testWidgets('desktop project selector shows all available projects', (
    tester,
  ) async {
    const importantProjectId = 'project-important';
    await _pumpKanban(
      tester,
      width: 1200,
      snapshot: _snapshot(
        availableProjects: [
          _project(inboxProjectId, 'Inbox'),
          _project(importantProjectId, 'Important'),
          _project('project-work', 'Work'),
        ],
        selectedProjectIds: const [inboxProjectId, importantProjectId],
      ),
    );

    await tester.tap(find.byKey(const Key('kanban-project-selector')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('kanban-project-option-project-important')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px Arabic large text stays RTL and overflow-free', (
    tester,
  ) async {
    await _pumpKanban(
      tester,
      width: 320,
      locale: const Locale('ar'),
      textScale: 1.45,
    );

    expect(
      Directionality.of(tester.element(find.byType(KanbanScreen))),
      TextDirection.rtl,
    );
    expect(find.text('كانبان'), findsOneWidget);
    expect(find.text('قيد التنفيذ'), findsOneWidget);
    expect(find.byKey(const Key('kanban-mobile-board')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('390px large text preserves one expanded section', (
    tester,
  ) async {
    await _pumpKanban(tester, width: 390, textScale: 1.8);

    expect(find.byKey(const Key('kanban-section-expanded')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active focus card shows progress and a stop control', (
    tester,
  ) async {
    await _pumpKanban(tester, width: 390, activeFocus: true);

    expect(
      find.byKey(const Key('kanban-active-focus-progress')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('kanban-stop-focus')), findsOneWidget);
    expect(find.text('20:00 / 25:00'), findsOneWidget);
  });

  test(
    'an older failed move cannot roll back a newer optimistic move',
    () async {
      final repository = _ControlledKanbanRepository();
      final controller = KanbanBoardController(repository);
      addTearDown(controller.dispose);

      final first = controller.moveTask('task', statusId: kanbanStatusTodoId);
      final second = controller.moveTask(
        'task',
        statusId: kanbanStatusInProgressId,
      );
      repository.completers.first.completeError(StateError('old failure'));
      await expectLater(first, throwsStateError);

      expect(controller.overrides['task']?.statusId, kanbanStatusInProgressId);

      repository.completers.last.complete();
      await second;
    },
  );
}

Future<_KanbanHarness> _pumpKanban(
  WidgetTester tester, {
  required double width,
  Locale locale = const Locale('en'),
  double textScale = 1,
  bool activeFocus = false,
  KanbanBoardSnapshot? snapshot,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final board = snapshot ?? _snapshot();
  final kanban = _FakeKanbanRepository(board);
  final tasks = _FakeTaskRepository();
  final projects = _FakeProjectRepository(board.availableProjects);
  final quickAdd = QuickAddService(
    parser: const QuickAddParser(),
    taskRepository: tasks,
    projectRepository: projects,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        kanbanRepositoryProvider.overrideWithValue(kanban),
        quickAddServiceProvider.overrideWithValue(quickAdd),
        activeFocusRunProvider.overrideWith(
          (ref) =>
              Stream<FocusRunItem?>.value(activeFocus ? _activeRun() : null),
        ),
        activeFocusIntervalProvider.overrideWith(
          (ref) => Stream<FocusIntervalItem?>.value(
            activeFocus ? _activeInterval() : null,
          ),
        ),
        activeFocusRemainingProvider.overrideWith(
          (ref) => activeFocus ? const Duration(minutes: 20) : null,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: KanbanScreen()),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _KanbanHarness(kanban: kanban, tasks: tasks);
}

FocusRunItem _activeRun() {
  final now = DateTime.utc(2026, 7, 10, 10);
  return FocusRunItem(
    id: 'run-active',
    userId: localUserId,
    taskId: 'task-focus',
    projectId: inboxProjectId,
    presetId: 'preset',
    status: 'active',
    startedAt: now,
    targetWorkIntervals: 3,
    completedWorkIntervals: 0,
    createdAt: now,
    updatedAt: now,
  );
}

FocusIntervalItem _activeInterval() {
  final now = DateTime.utc(2026, 7, 10, 10);
  return FocusIntervalItem(
    id: 'interval-active',
    runId: 'run-active',
    taskId: 'task-focus',
    projectId: inboxProjectId,
    type: 'work',
    status: 'running',
    plannedSeconds: 1500,
    startedAt: now,
    pausedTotalSeconds: 0,
    sequenceNumber: 1,
    createdAt: now,
    updatedAt: now,
  );
}

KanbanBoardSnapshot _snapshot({
  List<ProjectItem>? availableProjects,
  List<String>? selectedProjectIds,
}) {
  final now = DateTime.utc(2026, 7, 10);
  final inbox = _project(inboxProjectId, 'Inbox');
  final projects = availableProjects ?? [inbox];
  final statuses = [
    _status(
      kanbanStatusBacklogId,
      'Backlog',
      KanbanSystemKey.backlog,
      'a',
      now,
    ),
    _status(kanbanStatusTodoId, 'To do', KanbanSystemKey.todo, 'b', now),
    _status(
      kanbanStatusInProgressId,
      'In progress',
      KanbanSystemKey.inProgress,
      'c',
      now,
    ),
    _status(kanbanStatusDoneId, 'Done', KanbanSystemKey.done, 'd', now),
  ];
  final task = TaskItem(
    id: 'task-focus',
    userId: localUserId,
    content: 'Polish Today screen',
    projectId: inboxProjectId,
    priority: 1,
    status: 'open',
    estimatedFocusIntervals: 3,
    completedFocusIntervals: 1,
    totalFocusSeconds: 1500,
    orderKey: 'a',
    isDeleted: false,
    createdAt: now,
    updatedAt: now,
  );
  return KanbanBoardSnapshot(
    statuses: statuses,
    settings: KanbanSettings(
      id: kanbanSettingsPrimaryId,
      userId: localUserId,
      selectedProjectIds: selectedProjectIds ?? const [inboxProjectId],
      focusStatusLabelId: kanbanStatusInProgressId,
      createdAt: now,
      updatedAt: now,
    ),
    availableProjects: projects,
    cardsByStatusId: {
      kanbanStatusBacklogId: const [],
      kanbanStatusTodoId: const [],
      kanbanStatusInProgressId: [
        KanbanCard(
          task: task,
          project: inbox,
          statusId: kanbanStatusInProgressId,
          totalSubtasks: 2,
          completedSubtasks: 1,
        ),
      ],
      kanbanStatusDoneId: const [],
    },
  );
}

ProjectItem _project(String id, String name) {
  final now = DateTime.utc(2026, 7, 10);
  return ProjectItem(
    id: id,
    userId: localUserId,
    name: name,
    orderKey: id,
    createdAt: now,
    updatedAt: now,
  );
}

KanbanStatus _status(
  String id,
  String name,
  KanbanSystemKey systemKey,
  String orderKey,
  DateTime now,
) {
  return KanbanStatus(
    id: id,
    userId: localUserId,
    name: name,
    systemKey: systemKey,
    orderKey: orderKey,
    createdAt: now,
    updatedAt: now,
  );
}

class _KanbanHarness {
  const _KanbanHarness({required this.kanban, required this.tasks});

  final _FakeKanbanRepository kanban;
  final _FakeTaskRepository tasks;
}

class _Move {
  const _Move(this.taskId, this.statusId, this.targetIndex);

  final String taskId;
  final String statusId;
  final int? targetIndex;
}

class _FakeKanbanRepository implements KanbanRepository {
  _FakeKanbanRepository(this.snapshot);

  final KanbanBoardSnapshot snapshot;
  final moves = <_Move>[];

  @override
  Stream<KanbanBoardSnapshot> watchBoard() => Stream.value(snapshot);

  @override
  Future<void> moveTask(
    String taskId, {
    required String statusId,
    int? targetIndex,
  }) async {
    moves.add(_Move(taskId, statusId, targetIndex));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ControlledKanbanRepository implements KanbanRepository {
  final completers = <Completer<void>>[];

  @override
  Future<void> moveTask(
    String taskId, {
    required String statusId,
    int? targetIndex,
  }) {
    final completer = Completer<void>();
    completers.add(completer);
    return completer.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTaskRepository implements TaskRepository {
  final created = <CreateTaskInput>[];

  @override
  Future<String> createTask(CreateTaskInput input) async {
    created.add(input);
    return 'created-${created.length}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProjectRepository implements ProjectRepository {
  _FakeProjectRepository(this.projects);

  final List<ProjectItem> projects;

  @override
  Stream<List<ProjectItem>> watchProjects() => Stream.value(projects);

  @override
  Future<String> createProject(String name, {String? color}) async {
    return projects.first.id;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
