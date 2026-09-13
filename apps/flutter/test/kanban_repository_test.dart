import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/core/sync/sync_queue_repository.dart';
import 'package:pomodoist/features/tasks/data/kanban_repository_impl.dart';
import 'package:pomodoist/features/tasks/data/kanban_transition_coordinator.dart';
import 'package:pomodoist/features/tasks/data/task_repository_impl.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';

void main() {
  group('DriftKanbanRepository', () {
    late AppDatabase db;
    late DriftKanbanRepository repository;
    late _SelectRecorder recorder;

    setUp(() async {
      recorder = _SelectRecorder();
      db = AppDatabase(NativeDatabase.memory().interceptWith(recorder));
      await db.ensureSeedData();
      repository = DriftKanbanRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('watching the board does not repair missing assignments', () async {
      await _insertTask(
        db,
        id: 'unassigned-task',
        content: 'Unassigned',
        projectId: inboxProjectId,
        orderKey: '1',
      );
      await db.customStatement('PRAGMA query_only = ON');

      final snapshot = await repository.watchBoard().first;

      final links =
          await (db.select(db.taskLabels)..where(
                (row) =>
                    row.taskId.equals('unassigned-task') &
                    row.kind.equals(labelKindKanbanStatus),
              ))
              .get();
      expect(links, isEmpty);
      expect(
        snapshot.cardsByStatusId.values
            .expand((cards) => cards)
            .map((card) => card.task.id),
        isNot(contains('unassigned-task')),
      );
    });

    test(
      'watches selected projects together and emits root cards only',
      () async {
        await _insertProject(db, id: 'project-a', name: 'Alpha', orderKey: '1');
        await _insertProject(db, id: 'project-b', name: 'Beta', orderKey: '2');
        await _insertProject(db, id: 'project-c', name: 'Gamma', orderKey: '3');
        await _insertTask(
          db,
          id: 'task-a',
          content: 'Alpha root',
          projectId: 'project-a',
          orderKey: '1',
        );
        await _insertTask(
          db,
          id: 'task-a-child',
          content: 'Alpha child',
          projectId: 'project-a',
          parentId: 'task-a',
          status: 'completed',
          orderKey: '2',
        );
        await _insertTask(
          db,
          id: 'task-b',
          content: 'Beta root',
          projectId: 'project-b',
          orderKey: '3',
        );
        await _insertTask(
          db,
          id: 'task-c',
          content: 'Gamma root',
          projectId: 'project-c',
          orderKey: '4',
        );

        await repository.setSelectedProjectIds({'project-b', 'project-a'});
        final snapshot = await repository.watchBoard().first;
        final backlogCards = snapshot.cardsForStatus(kanbanStatusBacklogId);

        expect(snapshot.settings.selectedProjectIds, [
          'project-a',
          'project-b',
        ]);
        expect(backlogCards.map((card) => card.task.id).toList(), [
          'task-a',
          'task-b',
        ]);
        expect(backlogCards.first.project.name, 'Alpha');
        expect(backlogCards.first.totalSubtasks, 1);
        expect(backlogCards.first.completedSubtasks, 1);
        expect(
          snapshot.cardsByStatusId.values
              .expand((cards) => cards)
              .map((card) => card.task.id),
          isNot(contains(anyOf('task-a-child', 'task-c'))),
        );

        final settingsRow = await db.select(db.kanbanSettings).getSingle();
        expect(settingsRow.selectedProjectIdsJson, '["project-a","project-b"]');
      },
    );

    test('board SQL scopes roots, Done, links, and subtasks', () async {
      await _insertProject(
        db,
        id: 'project-selected',
        name: 'Selected',
        orderKey: '1',
      );
      await _insertProject(
        db,
        id: 'project-unselected',
        name: 'Unselected',
        orderKey: '2',
      );
      await _insertTask(
        db,
        id: 'selected-open',
        content: 'Selected open',
        projectId: 'project-selected',
        orderKey: '1',
      );
      await _insertTask(
        db,
        id: 'selected-child',
        content: 'Selected child',
        projectId: 'project-selected',
        parentId: 'selected-open',
        orderKey: '2',
      );
      await _insertTask(
        db,
        id: 'selected-done',
        content: 'Selected done',
        projectId: 'project-selected',
        status: 'completed',
        completedAt: DateTime.utc(2026, 7, 10, 12),
        orderKey: '3',
      );
      await _insertTask(
        db,
        id: 'unselected-open',
        content: 'Unselected open',
        projectId: 'project-unselected',
        orderKey: '4',
      );
      await repository.setSelectedProjectIds({'project-selected'});
      recorder.selects.clear();
      recorder.taskPlans.clear();

      final snapshot = await repository.watchBoard().first;

      expect(
        snapshot.cardsByStatusId.values
            .expand((cards) => cards)
            .map((card) => card.task.id)
            .toSet(),
        {'selected-open', 'selected-done'},
      );
      final taskSelects = recorder.selects
          .where((sql) => sql.contains('FROM "tasks"'))
          .toList();
      expect(
        taskSelects.where((sql) => !sql.contains('"parent_id" IN')),
        everyElement(contains('"project_id" IN')),
      );
      expect(
        taskSelects,
        contains(predicate<String>((sql) => sql.contains('LIMIT 20'))),
      );
      expect(
        taskSelects,
        contains(predicate<String>((sql) => sql.contains('"parent_id" IN'))),
      );
      expect(
        recorder.selects.where(
          (sql) =>
              sql.startsWith('SELECT * FROM "task_labels"') &&
              !sql.contains('"task_id" IN'),
        ),
        isEmpty,
      );
      final planDetails = recorder.taskPlans
          .expand((observation) => observation.details)
          .toList();
      expect(
        planDetails,
        isNot(
          contains(
            predicate<String>((detail) => detail.contains('SCAN tasks')),
          ),
        ),
      );
      expect(
        planDetails.join('\n'),
        allOf(
          contains('tasks_kanban_open_roots_by_project'),
          contains('tasks_kanban_done_roots_by_project'),
          contains('tasks_active_children_by_parent'),
        ),
      );
    });

    test(
      'supports status CRUD while protecting and preserving anchors',
      () async {
        await _insertTask(
          db,
          id: 'task-1',
          content: 'Task',
          projectId: inboxProjectId,
          orderKey: '1',
        );
        await db.ensureKanbanData();

        await repository.renameStatus(kanbanStatusBacklogId, 'Ideas');
        await repository.renameStatus(kanbanStatusTodoId, 'Ready');
        final reviewId = await repository.createStatus('Review');
        await repository.reorderStatus(reviewId, 1);
        await repository.moveTask('task-1', statusId: reviewId, targetIndex: 0);

        var snapshot = await repository.watchBoard().first;
        expect(snapshot.statuses.first.id, kanbanStatusBacklogId);
        expect(snapshot.statuses.first.name, 'Ideas');
        expect(snapshot.statuses[1].id, reviewId);
        expect(snapshot.statuses.last.id, kanbanStatusDoneId);
        expect(snapshot.cardsForStatus(reviewId).single.task.id, 'task-1');

        await expectLater(
          repository.deleteStatus(kanbanStatusBacklogId),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          repository.reorderStatus(kanbanStatusDoneId, 1),
          throwsA(isA<StateError>()),
        );

        await repository.deleteStatus(reviewId);
        snapshot = await repository.watchBoard().first;
        expect(
          snapshot.statuses.map((status) => status.id),
          isNot(contains(reviewId)),
        );
        expect(
          snapshot.cardsForStatus(kanbanStatusBacklogId).single.task.id,
          'task-1',
        );
        final deleted = await (db.select(
          db.labels,
        )..where((row) => row.id.equals(reviewId))).getSingle();
        expect(deleted.isDeleted, isTrue);
      },
    );

    test(
      'project deletion self-heals selection and preserves survivors',
      () async {
        await _insertProject(db, id: 'project-a', name: 'Alpha', orderKey: '1');
        await _insertProject(db, id: 'project-b', name: 'Beta', orderKey: '2');
        await _insertProject(
          db,
          id: 'project-fallback',
          name: 'Fallback',
          orderKey: '0',
        );
        await repository.setSelectedProjectIds({'project-b', 'project-a'});
        await repository.setSelectedProjectIds(const <String>{});
        final focusId = await repository.createStatus('Focus now');
        await repository.setFocusStatus(focusId);

        var snapshot = await repository.watchBoard().first;
        expect(snapshot.settings.selectedProjectIds, [
          'project-a',
          'project-b',
        ]);
        expect(snapshot.settings.focusStatusLabelId, focusId);

        final projectSyncQueue = DriftSyncQueueRepository(db);
        final projectRepository = DriftProjectRepository(db, projectSyncQueue);
        await db.delete(db.syncCommands).go();
        await projectRepository.deleteProject('project-a');

        var persistedSettings = await db.select(db.kanbanSettings).getSingle();
        expect(persistedSettings.selectedProjectIdsJson, '["project-b"]');
        snapshot = await repository.watchBoard().first;
        expect(snapshot.settings.selectedProjectIds, ['project-b']);
        expect(snapshot.settings.focusStatusLabelId, focusId);
        final deleteCommands = await projectSyncQueue.watchPending().first;
        expect(
          deleteCommands.map((command) => command.type),
          contains('kanban.settings.projects.set'),
        );

        await projectRepository.deleteProject('project-b');

        persistedSettings = await db.select(db.kanbanSettings).getSingle();
        expect(
          persistedSettings.selectedProjectIdsJson,
          '["project-fallback"]',
        );
        snapshot = await repository.watchBoard().first;
        expect(snapshot.settings.selectedProjectIds, ['project-fallback']);
        expect(snapshot.settings.focusStatusLabelId, focusId);

        await repository.deleteStatus(focusId);

        snapshot = await repository.watchBoard().first;
        expect(snapshot.settings.selectedProjectIds, ['project-fallback']);
        expect(snapshot.settings.focusStatusLabelId, kanbanStatusTodoId);
        await expectLater(
          repository.setFocusStatus(kanbanStatusDoneId),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test('Done contains only the 20 newest completed root cards', () async {
      final base = DateTime.utc(2026, 7, 1);
      for (var index = 0; index < 25; index++) {
        await _insertTask(
          db,
          id: 'task-$index',
          content: 'Task $index',
          projectId: inboxProjectId,
          status: 'completed',
          completedAt: base.add(Duration(hours: index)),
          orderKey: index.toString(),
        );
      }
      await _insertTask(
        db,
        id: 'completed-child',
        content: 'Completed child',
        projectId: inboxProjectId,
        parentId: 'task-24',
        status: 'completed',
        completedAt: base.add(const Duration(days: 30)),
        orderKey: 'child',
      );
      await _insertTask(
        db,
        id: 'completed-without-timestamp',
        content: 'Completed without timestamp',
        projectId: inboxProjectId,
        status: 'completed',
        updatedAt: base.add(const Duration(days: 60)),
        orderKey: 'fallback',
      );
      await db.ensureKanbanData();

      final snapshot = await repository.watchBoard().first;
      final doneCards = snapshot.cardsForStatus(kanbanStatusDoneId);

      expect(doneCards, hasLength(20));
      expect(doneCards.map((card) => card.task.id).toList(), [
        'completed-without-timestamp',
        ...List.generate(19, (index) => 'task-${24 - index}'),
      ]);
      expect(
        doneCards.map((card) => card.task.id),
        isNot(contains('completed-child')),
      );
    });

    test(
      'reorders cards and middle statuses with one assignment per task',
      () async {
        for (final id in const ['a', 'b', 'c']) {
          await _insertTask(
            db,
            id: 'task-$id',
            content: 'Task $id',
            projectId: inboxProjectId,
            orderKey: id,
          );
        }
        await db.ensureKanbanData();
        await repository.moveTask(
          'task-a',
          statusId: kanbanStatusTodoId,
          targetIndex: 0,
        );
        await repository.moveTask(
          'task-b',
          statusId: kanbanStatusTodoId,
          targetIndex: 1,
        );
        await repository.moveTask(
          'task-c',
          statusId: kanbanStatusTodoId,
          targetIndex: 2,
        );
        await repository.moveTask(
          'task-c',
          statusId: kanbanStatusTodoId,
          targetIndex: 0,
        );

        var snapshot = await repository.watchBoard().first;
        expect(
          snapshot
              .cardsForStatus(kanbanStatusTodoId)
              .map((card) => card.task.id)
              .toList(),
          ['task-c', 'task-a', 'task-b'],
        );
        final orderedRows =
            await (db.select(db.tasks)..where(
                  (row) => row.id.isIn(const ['task-a', 'task-b', 'task-c']),
                ))
                .get();
        expect(
          orderedRows.map((row) => row.orderKey),
          everyElement(matches(RegExp(r'^\d{20}$'))),
        );
        final numericOrderKeys = orderedRows
            .map((row) => int.parse(row.orderKey))
            .toList();
        expect(
          numericOrderKeys,
          everyElement(lessThanOrEqualTo(4503599627370496)),
        );

        await repository.moveTask(
          'task-b',
          statusId: kanbanStatusInProgressId,
          targetIndex: 0,
        );
        final reviewId = await repository.createStatus('Review');
        await repository.reorderStatus(reviewId, 1);
        snapshot = await repository.watchBoard().first;
        expect(snapshot.statuses.first.id, kanbanStatusBacklogId);
        expect(snapshot.statuses[1].id, reviewId);
        expect(snapshot.statuses.last.id, kanbanStatusDoneId);
        expect(
          snapshot.cardsForStatus(kanbanStatusInProgressId).single.task.id,
          'task-b',
        );

        final assignments =
            await (db.select(db.taskLabels)..where(
                  (row) =>
                      row.taskId.isIn(const ['task-a', 'task-b', 'task-c']) &
                      row.kind.equals(labelKindKanbanStatus),
                ))
                .get();
        expect(assignments, hasLength(3));
        expect(assignments.map((row) => row.taskId).toSet(), hasLength(3));
      },
    );

    test(
      'ordinary label APIs hide and cannot delete Kanban statuses',
      () async {
        final syncQueue = DriftSyncQueueRepository(db);
        final labels = DriftLabelRepository(db, syncQueue);
        final tasks = DriftTaskRepository(db, syncQueue);

        expect(await labels.watchLabels().first, isEmpty);
        expect(await labels.findByName('Backlog'), isNull);
        final userBacklogId = await labels.createLabel('Backlog');
        expect(userBacklogId, isNot(kanbanStatusBacklogId));

        await labels.deleteLabel(kanbanStatusBacklogId);
        final anchor = await (db.select(
          db.labels,
        )..where((row) => row.id.equals(kanbanStatusBacklogId))).getSingle();
        expect(anchor.isDeleted, isFalse);

        final taskId = await tasks.createTask(
          const CreateTaskInput(content: 'Task', labelNames: ['Backlog']),
        );
        final links = await (db.select(
          db.taskLabels,
        )..where((row) => row.taskId.equals(taskId))).get();
        expect(
          links.where((row) => row.kind == labelKindUser).single.labelId,
          userBacklogId,
        );
      },
    );

    test(
      'recurring ordinary-label copying excludes Kanban assignments',
      () async {
        final syncQueue = DriftSyncQueueRepository(db);
        final tasks = DriftTaskRepository(db, syncQueue);
        final sourceId = await tasks.createTask(
          CreateTaskInput(
            content: 'Recurring task',
            labelNames: const ['habit'],
            schedule: TaskSchedule.allDay(
              DateTime(2026, 7, 1),
              recurrence: const TaskRecurrence(
                interval: 1,
                unit: TaskRecurrenceUnit.day,
                seriesId: 'kanban-copy-filter',
              ),
            ),
          ),
        );
        await db.ensureKanbanData();
        final sourceStatus =
            await (db.select(db.taskLabels)..where(
                  (row) =>
                      row.taskId.equals(sourceId) &
                      row.kind.equals(labelKindKanbanStatus),
                ))
                .getSingle();

        await tasks.materializeDueRecurringTasks(now: DateTime(2026, 7, 2, 9));

        final copiedTask = (await db.select(db.tasks).get()).singleWhere(
          (row) => row.content == 'Recurring task' && row.id != sourceId,
        );
        final commands = await syncQueue.watchPending().first;
        expect(
          commands.where(
            (command) =>
                command.type == 'task.label.add' &&
                command.clientId == copiedTask.id &&
                command.payloadJson.contains(sourceStatus.labelId),
          ),
          isEmpty,
        );
        expect(
          commands.where(
            (command) =>
                command.type == 'task.kanbanStatus.set' &&
                command.clientId == copiedTask.id &&
                command.payloadJson.contains(sourceStatus.labelId),
          ),
          hasLength(1),
        );
      },
    );

    test(
      'queues Kanban status, settings, assignment, and order mutations',
      () async {
        final syncQueue = DriftSyncQueueRepository(db);
        final transitions = KanbanTransitionCoordinator(db, syncQueue);
        final syncedRepository = DriftKanbanRepository(
          db,
          syncQueue: syncQueue,
          kanbanTransitions: transitions,
        );
        await _insertProject(
          db,
          id: 'selected-project',
          name: 'Selected',
          orderKey: '1',
        );
        await _insertTask(
          db,
          id: 'ordered-task',
          content: 'Ordered',
          projectId: 'selected-project',
          orderKey: '1',
        );
        await db.ensureKanbanData();
        await db.delete(db.syncCommands).go();

        final statusId = await syncedRepository.createStatus('Review');
        await syncedRepository.renameStatus(statusId, 'Ready for review');
        await syncedRepository.reorderStatus(statusId, 1);
        await syncedRepository.setSelectedProjectIds({'selected-project'});
        await syncedRepository.setFocusStatus(statusId);
        await syncedRepository.moveTask(
          'ordered-task',
          statusId: statusId,
          targetIndex: 0,
        );
        await syncedRepository.deleteStatus(statusId);

        final commands = await syncQueue.watchPending().first;
        final types = commands.map((command) => command.type);
        expect(types, contains('kanban.status.create'));
        expect(types, contains('kanban.status.rename'));
        expect(types, contains('kanban.status.reorder'));
        expect(types, contains('kanban.settings.projects.set'));
        expect(types, contains('kanban.settings.focus.set'));
        expect(types, contains('task.kanbanStatus.set'));
        expect(types, contains('task.reorder'));
        expect(types, contains('kanban.status.delete'));
        expect(
          commands
              .where((command) => command.type == 'task.kanbanStatus.set')
              .last
              .payloadJson,
          contains(kanbanStatusBacklogId),
        );
      },
    );

    test('provider exposes the Kanban repository', () {
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      expect(
        container.read(kanbanRepositoryProvider),
        isA<DriftKanbanRepository>(),
      );
      expect(
        container.read(kanbanTransitionCoordinatorProvider),
        isA<KanbanTransitionCoordinator>(),
      );
    });
  });
}

class _SelectRecorder extends QueryInterceptor {
  final List<String> selects = [];
  final List<({String sql, List<Object?> args, List<String> details})>
  taskPlans = [];

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    selects.add(statement);
    if (statement.contains('FROM "tasks"') &&
        (statement.contains('"project_id" IN') ||
            statement.contains('"parent_id" IN'))) {
      final plan = await executor.runSelect(
        'EXPLAIN QUERY PLAN $statement',
        args,
      );
      taskPlans.add((
        sql: statement,
        args: List<Object?>.of(args),
        details: plan.map((row) => row['detail']! as String).toList(),
      ));
    }
    return super.runSelect(executor, statement, args);
  }
}

Future<void> _insertProject(
  AppDatabase db, {
  required String id,
  required String name,
  required String orderKey,
}) async {
  final now = DateTime.utc(2026, 7, 10, 9);
  await db
      .into(db.projects)
      .insert(
        ProjectsCompanion.insert(
          id: id,
          userId: localUserId,
          name: name,
          orderKey: orderKey,
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<void> _insertTask(
  AppDatabase db, {
  required String id,
  required String content,
  required String projectId,
  required String orderKey,
  String? parentId,
  String status = 'open',
  DateTime? completedAt,
  DateTime? updatedAt,
}) async {
  final now = DateTime.utc(2026, 7, 10, 9);
  await db
      .into(db.tasks)
      .insert(
        TasksCompanion.insert(
          id: id,
          userId: localUserId,
          content: content,
          projectId: projectId,
          parentId: Value(parentId),
          status: Value(status),
          orderKey: orderKey,
          createdAt: now,
          updatedAt: updatedAt ?? now,
          completedAt: Value(completedAt),
        ),
      );
}
