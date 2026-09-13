import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/core/sync/sync_queue_repository.dart';
import 'package:pomodoist/features/planning/data/quick_add_service.dart';
import 'package:pomodoist/features/planning/domain/quick_add_parser.dart';
import 'package:pomodoist/features/tasks/data/kanban_repository_impl.dart';
import 'package:pomodoist/features/tasks/data/kanban_transition_coordinator.dart';
import 'package:pomodoist/features/tasks/data/task_repository_impl.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';

void main() {
  group('Kanban lifecycle', () {
    late AppDatabase db;
    late DriftSyncQueueRepository syncQueue;
    late KanbanTransitionCoordinator transitions;
    late DriftTaskRepository tasks;
    late DriftKanbanRepository kanban;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.ensureSeedData();
      syncQueue = DriftSyncQueueRepository(db);
      transitions = KanbanTransitionCoordinator(db, syncQueue);
      tasks = DriftTaskRepository(
        db,
        syncQueue,
        kanbanTransitions: transitions,
      );
      kanban = DriftKanbanRepository(
        db,
        syncQueue: syncQueue,
        kanbanTransitions: transitions,
      );
    });

    tearDown(() => db.close());

    test(
      'creation assigns Backlog unless an active non-Done status is valid',
      () async {
        final defaultId = await tasks.createTask(
          const CreateTaskInput(content: 'Default'),
        );
        final explicitId = await tasks.createTask(
          const CreateTaskInput(
            content: 'Explicit',
            kanbanStatusId: kanbanStatusTodoId,
          ),
        );
        final doneId = await tasks.createTask(
          const CreateTaskInput(
            content: 'Done is invalid for create',
            kanbanStatusId: kanbanStatusDoneId,
          ),
        );
        final unknownId = await tasks.createTask(
          const CreateTaskInput(
            content: 'Unknown is invalid for create',
            kanbanStatusId: 'missing-status',
          ),
        );

        expect(await _statusId(db, defaultId), kanbanStatusBacklogId);
        expect(await _statusId(db, explicitId), kanbanStatusTodoId);
        expect(await _statusId(db, doneId), kanbanStatusBacklogId);
        expect(await _statusId(db, unknownId), kanbanStatusBacklogId);

        final commands = await syncQueue.watchPending().first;
        for (final taskId in [defaultId, explicitId, doneId, unknownId]) {
          final taskCommands = commands
              .where((command) => command.clientId == taskId)
              .toList();
          expect(taskCommands.map((command) => command.type), [
            'task.create',
            'task.kanbanStatus.set',
          ]);
          final assignment = jsonDecode(taskCommands.last.payloadJson) as Map;
          expect(assignment['taskId'], taskId);
          expect(assignment['labelId'], await _statusId(db, taskId));
          expect(
            DateTime.tryParse(assignment['changedAt']! as String),
            isNotNull,
          );
        }
      },
    );

    test(
      'checkbox completion snapshots and restores every subtree status',
      () async {
        final rootId = await tasks.createTask(
          const CreateTaskInput(
            content: 'Root',
            kanbanStatusId: kanbanStatusTodoId,
          ),
        );
        final childId = await tasks.createTask(
          CreateTaskInput(
            content: 'Child',
            parentId: rootId,
            kanbanStatusId: kanbanStatusInProgressId,
          ),
        );
        final grandchildId = await tasks.createTask(
          CreateTaskInput(content: 'Grandchild', parentId: childId),
        );
        await db.delete(db.syncCommands).go();

        await tasks.completeTask(rootId);

        for (final id in [rootId, childId, grandchildId]) {
          final task = await _task(db, id);
          expect(task.status, 'completed');
          expect(await _statusId(db, id), kanbanStatusDoneId);
        }
        expect(await _snapshot(db, rootId), _snapshotJson(kanbanStatusTodoId));
        expect(
          await _snapshot(db, childId),
          _snapshotJson(kanbanStatusInProgressId),
        );
        expect(
          await _snapshot(db, grandchildId),
          _snapshotJson(kanbanStatusBacklogId),
        );
        var commands = await syncQueue.watchPending().first;
        expect(commands.map((command) => command.type), [
          'task.complete',
          'task.kanbanStatus.set',
          'task.complete',
          'task.kanbanStatus.set',
          'task.complete',
          'task.kanbanStatus.set',
        ]);

        await db.delete(db.syncCommands).go();
        await tasks.uncompleteTask(rootId);

        expect(await _statusId(db, rootId), kanbanStatusTodoId);
        expect(await _statusId(db, childId), kanbanStatusInProgressId);
        expect(await _statusId(db, grandchildId), kanbanStatusBacklogId);
        expect((await _task(db, rootId)).status, 'open');
        expect((await _task(db, childId)).status, 'open');
        expect((await _task(db, grandchildId)).status, 'open');
        commands = await syncQueue.watchPending().first;
        expect(commands.map((command) => command.type), [
          'task.uncomplete',
          'task.kanbanStatus.set',
          'task.uncomplete',
          'task.kanbanStatus.set',
          'task.uncomplete',
          'task.kanbanStatus.set',
        ]);
      },
    );

    test(
      'Kanban Done transition completes and explicit target restores root',
      () async {
        final rootId = await tasks.createTask(
          const CreateTaskInput(
            content: 'Root',
            kanbanStatusId: kanbanStatusInProgressId,
          ),
        );
        final childId = await tasks.createTask(
          CreateTaskInput(
            content: 'Child',
            parentId: rootId,
            kanbanStatusId: kanbanStatusTodoId,
          ),
        );

        await kanban.moveTask(rootId, statusId: kanbanStatusDoneId);
        expect((await _task(db, rootId)).status, 'completed');
        expect((await _task(db, childId)).status, 'completed');

        await kanban.moveTask(rootId, statusId: kanbanStatusBacklogId);

        expect((await _task(db, rootId)).status, 'open');
        expect((await _task(db, childId)).status, 'open');
        expect(await _statusId(db, rootId), kanbanStatusBacklogId);
        expect(await _statusId(db, childId), kanbanStatusTodoId);
      },
    );

    test(
      'recurring copies inherit each source workflow status, never Done',
      () async {
        final rootId = await tasks.createTask(
          CreateTaskInput(
            content: 'Recurring root',
            kanbanStatusId: kanbanStatusInProgressId,
            schedule: TaskSchedule.allDay(
              DateTime(2026, 7, 1),
              recurrence: const TaskRecurrence(
                interval: 1,
                unit: TaskRecurrenceUnit.day,
                seriesId: 'lifecycle-copy',
              ),
            ),
          ),
        );
        final childId = await tasks.createTask(
          CreateTaskInput(
            content: 'Recurring child',
            parentId: rootId,
            kanbanStatusId: kanbanStatusTodoId,
          ),
        );
        await tasks.completeTask(rootId);
        await db.delete(db.syncCommands).go();

        await tasks.materializeDueRecurringTasks(now: DateTime(2026, 7, 2, 9));

        final copiedRoot = (await db.select(db.tasks).get()).singleWhere(
          (row) => row.content == 'Recurring root' && row.id != rootId,
        );
        final copiedChild = (await db.select(db.tasks).get()).singleWhere(
          (row) => row.content == 'Recurring child' && row.id != childId,
        );
        expect(copiedRoot.status, 'open');
        expect(copiedChild.status, 'open');
        expect(await _statusId(db, copiedRoot.id), kanbanStatusInProgressId);
        expect(await _statusId(db, copiedChild.id), kanbanStatusTodoId);

        final commands = await syncQueue.watchPending().first;
        for (final copiedId in [copiedRoot.id, copiedChild.id]) {
          expect(
            commands
                .where((command) => command.clientId == copiedId)
                .map((command) => command.type),
            ['task.create', 'task.kanbanStatus.set'],
          );
        }
      },
    );

    test(
      'Calendar creation uses Backlog and snapshots it when completed',
      () async {
        final timestamp = DateTime.utc(2026, 7, 10, 9);
        final openId = await tasks.createTaskFromCalendar(
          RemoteCalendarTaskInput(
            content: 'Open event',
            schedule: TaskSchedule.allDay(DateTime(2026, 7, 11)),
            updatedAt: timestamp,
          ),
        );
        final completedId = await tasks.createTaskFromCalendar(
          RemoteCalendarTaskInput(
            content: 'Completed event',
            schedule: TaskSchedule.allDay(DateTime(2026, 7, 12)),
            isCompleted: true,
            updatedAt: timestamp.add(const Duration(minutes: 1)),
          ),
        );

        expect((await _task(db, openId)).status, 'open');
        expect(await _statusId(db, openId), kanbanStatusBacklogId);
        expect((await _task(db, completedId)).status, 'completed');
        expect(await _statusId(db, completedId), kanbanStatusDoneId);
        expect(
          await _snapshot(db, completedId),
          _snapshotJson(kanbanStatusBacklogId),
        );

        final commands = await syncQueue.watchPending().first;
        expect(
          commands
              .where((command) => command.clientId == openId)
              .map((command) => command.type),
          ['task.create', 'task.kanbanStatus.set'],
        );
        expect(
          commands
              .where((command) => command.clientId == completedId)
              .map((command) => command.type),
          [
            'task.create',
            'task.kanbanStatus.set',
            'task.complete',
            'task.kanbanStatus.set',
          ],
        );
      },
    );

    test(
      'Calendar completion edges create events and restore snapshots',
      () async {
        final taskId = await tasks.createTask(
          const CreateTaskInput(
            content: 'Calendar linked',
            kanbanStatusId: kanbanStatusTodoId,
          ),
        );

        await tasks.applyRemoteCalendarPatch(
          taskId,
          RemoteCalendarTaskPatch(
            isCompleted: true,
            updatedAt: DateTime.utc(2026, 7, 10, 10),
          ),
        );
        await tasks.applyRemoteCalendarPatch(
          taskId,
          RemoteCalendarTaskPatch(
            isCompleted: false,
            updatedAt: DateTime.utc(2026, 7, 10, 11),
          ),
        );
        expect((await _task(db, taskId)).status, 'open');
        expect(await _statusId(db, taskId), kanbanStatusTodoId);

        await tasks.applyRemoteCalendarPatch(
          taskId,
          RemoteCalendarTaskPatch(
            isCompleted: true,
            updatedAt: DateTime.utc(2026, 7, 10, 12),
          ),
        );
        await tasks.applyRemoteCalendarPatch(
          taskId,
          RemoteCalendarTaskPatch(
            isCompleted: true,
            updatedAt: DateTime.utc(2026, 7, 10, 13),
          ),
        );

        final completions =
            await (db.select(db.taskCompletions)
                  ..where((row) => row.taskId.equals(taskId))
                  ..orderBy([(row) => OrderingTerm.asc(row.completedAt)]))
                .get();
        expect(completions, hasLength(2));
        expect(
          completions.map((row) => row.snapshotJson),
          everyElement(_snapshotJson(kanbanStatusTodoId)),
        );
        expect((await _task(db, taskId)).status, 'completed');
        expect(await _statusId(db, taskId), kanbanStatusDoneId);
      },
    );

    test(
      'Quick Add propagates a column status independently of project parsing',
      () async {
        final quickAdd = QuickAddService(
          parser: const QuickAddParser(),
          taskRepository: tasks,
          projectRepository: DriftProjectRepository(db, syncQueue),
        );

        final globalId = await quickAdd.createTask('Global task');
        final columnId = await quickAdd.createTask(
          'Column task #Work',
          projectId: 'ignored-project',
          kanbanStatusId: kanbanStatusTodoId,
        );

        expect(await _statusId(db, globalId), kanbanStatusBacklogId);
        expect(await _statusId(db, columnId), kanbanStatusTodoId);
        expect((await _task(db, columnId)).projectId, isNot('ignored-project'));
      },
    );

    test(
      'restore skips malformed newer snapshots and uses latest valid status',
      () async {
        final taskId = await tasks.createTask(
          const CreateTaskInput(
            content: 'Malformed snapshot',
            kanbanStatusId: kanbanStatusTodoId,
          ),
        );
        await tasks.completeTask(taskId);
        final invalidSnapshots = [
          '{"version":1,"kanban":{"previousStatusLabelId":42}}',
          '{"version":1,"kanban":{"previousStatusLabelId":[]}}',
          '{"version":1,"kanban":[]}',
        ];
        for (var index = 0; index < invalidSnapshots.length; index++) {
          final later = DateTime.utc(2030, 1, index + 1);
          await db
              .into(db.taskCompletions)
              .insert(
                TaskCompletionsCompanion.insert(
                  id: 'malformed-completion-$index',
                  taskId: taskId,
                  userId: localUserId,
                  completedAt: later,
                  snapshotJson: Value(invalidSnapshots[index]),
                  createdAt: later,
                ),
              );
        }

        await tasks.uncompleteTask(taskId);

        expect(await _statusId(db, taskId), kanbanStatusTodoId);
        expect((await _task(db, taskId)).status, 'open');
      },
    );

    test(
      'offline completion cycles capture distinct immutable completion IDs',
      () async {
        final taskId = await tasks.createTask(
          const CreateTaskInput(
            content: 'Complete twice',
            kanbanStatusId: kanbanStatusTodoId,
          ),
        );

        await tasks.completeTask(taskId);
        await tasks.uncompleteTask(taskId);
        await kanban.moveTask(taskId, statusId: kanbanStatusInProgressId);
        await tasks.completeTask(taskId);

        final rows =
            await (db.select(db.taskCompletions)
                  ..where((row) => row.taskId.equals(taskId))
                  ..orderBy([(row) => OrderingTerm.asc(row.completedAt)]))
                .get();
        expect(rows, hasLength(2));
        expect(rows.map((row) => row.snapshotJson), [
          _snapshotJson(kanbanStatusTodoId),
          _snapshotJson(kanbanStatusInProgressId),
        ]);
        final commands = await syncQueue.watchPending().first;
        final capturedIds = commands
            .where((command) => command.type == 'task.complete')
            .map(
              (command) =>
                  (jsonDecode(command.payloadJson) as Map)['completionId'],
            )
            .toList();
        expect(capturedIds, hasLength(2));
        expect(capturedIds.toSet(), hasLength(2));
        expect(capturedIds.toSet(), rows.map((row) => row.id).toSet());
      },
    );
  });
}

Future<TaskRow> _task(AppDatabase db, String id) {
  return (db.select(db.tasks)..where((row) => row.id.equals(id))).getSingle();
}

Future<String> _statusId(AppDatabase db, String taskId) async {
  final row =
      await (db.select(db.taskLabels)..where(
            (row) =>
                row.taskId.equals(taskId) &
                row.kind.equals(labelKindKanbanStatus),
          ))
          .getSingle();
  return row.labelId;
}

Future<String?> _snapshot(AppDatabase db, String taskId) async {
  final row =
      await (db.select(db.taskCompletions)
            ..where((row) => row.taskId.equals(taskId))
            ..orderBy([(row) => OrderingTerm.desc(row.completedAt)])
            ..limit(1))
          .getSingle();
  return row.snapshotJson;
}

String _snapshotJson(String statusId) =>
    '{"version":1,"kanban":{"previousStatusLabelId":"$statusId"}}';
