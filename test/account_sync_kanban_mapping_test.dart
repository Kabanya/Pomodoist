import 'dart:collection';
import 'dart:convert';

import 'package:app_account/app_account.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/core/sync/account_sync_engine.dart';
import 'package:pomodoist/core/sync/sync_queue_repository.dart';
import 'package:pomodoist/features/tasks/data/kanban_repository_impl.dart';
import 'package:pomodoist/features/tasks/data/task_repository_impl.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';
import 'package:uuid/uuid.dart';

void main() {
  group('Kanban account sync mapping', () {
    late AppDatabase db;
    late DriftSyncQueueRepository queue;
    late DriftTaskRepository tasks;
    late DriftKanbanRepository kanban;
    late _RecordingAccountClient account;
    late AccountSyncEngine engine;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.ensureSeedData();
      queue = DriftSyncQueueRepository(db);
      tasks = DriftTaskRepository(db, queue);
      kanban = DriftKanbanRepository(db, syncQueue: queue);
      account = _RecordingAccountClient();
      engine = AccountSyncEngine(
        db: db,
        account: account,
        uuid: const Uuid(),
        localPaidEntitlementLoader: () async => true,
      );
    });

    tearDown(() => db.close());

    test(
      'snapshot separates user labels, stable status assignment, and settings',
      () async {
        final taskId = await tasks.createTask(
          const CreateTaskInput(
            content: 'Snapshot task',
            kanbanStatusId: kanbanStatusTodoId,
          ),
        );
        final now = DateTime.utc(2026, 7, 10, 9);
        await db
            .into(db.labels)
            .insert(
              LabelsCompanion.insert(
                id: 'user-label',
                userId: localUserId,
                name: 'User label',
                orderKey: 'user-label',
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db
            .into(db.taskLabels)
            .insert(
              TaskLabelsCompanion.insert(
                taskId: taskId,
                labelId: 'user-label',
                createdAt: now,
              ),
            );

        await engine.importLocalSnapshotIfNeeded();

        final operations = account.pushed;
        expect(
          operations
              .where(
                (operation) =>
                    operation.entityType == 'task_kanban_status' &&
                    operation.entityId == taskId,
              )
              .single
              .payload['labelId'],
          kanbanStatusTodoId,
        );
        expect(
          operations
              .where(
                (operation) =>
                    operation.entityType == 'task_label' &&
                    operation.entityId == '$taskId:user-label',
              )
              .single
              .payload['kind'],
          labelKindUser,
        );
        expect(
          operations.where(
            (operation) =>
                operation.entityType == 'kanban_settings' &&
                operation.entityId == kanbanSettingsPrimaryId,
          ),
          hasLength(1),
        );
        expect(
          operations
              .where(
                (operation) =>
                    operation.entityType == 'label' &&
                    operation.entityId == kanbanStatusTodoId,
              )
              .single
              .payload['kind'],
          labelKindKanbanStatus,
        );
      },
    );

    test('mutation commands emit stable patch-specific operations', () async {
      final taskId = await tasks.createTask(
        const CreateTaskInput(content: 'Patch task'),
      );
      await db.delete(db.syncCommands).go();

      await kanban.renameStatus(kanbanStatusTodoId, 'Ready');
      await kanban.reorderStatus(kanbanStatusTodoId, 2);
      await kanban.setFocusStatus(kanbanStatusTodoId);
      await kanban.moveTask(taskId, statusId: kanbanStatusTodoId);

      await engine.pushPending();

      AccountSyncOperation byCommand(String commandType, {String? entityId}) =>
          account.pushed.singleWhere(
            (operation) =>
                operation.payload['commandType'] == commandType &&
                (entityId == null || operation.entityId == entityId),
          );

      final rename = byCommand('kanban.status.rename');
      expect(rename.entityType, 'label');
      expect(rename.entityId, kanbanStatusTodoId);
      expect(rename.payload['name'], 'Ready');
      expect(rename.payload, isNot(contains('orderKey')));

      final reorder = byCommand(
        'kanban.status.reorder',
        entityId: kanbanStatusTodoId,
      );
      expect(reorder.entityType, 'label');
      expect(reorder.payload, contains('orderKey'));
      expect(reorder.payload, isNot(contains('name')));

      final settings = byCommand('kanban.settings.focus.set');
      expect(settings.entityType, 'kanban_settings');
      expect(settings.entityId, kanbanSettingsPrimaryId);
      expect(settings.payload['focusStatusLabelId'], kanbanStatusTodoId);
      expect(settings.payload, isNot(contains('selectedProjectIdsJson')));

      final assignment = byCommand('task.kanbanStatus.set');
      expect(assignment.entityType, 'task_kanban_status');
      expect(assignment.entityId, taskId);
      expect(assignment.payload['taskId'], taskId);
      expect(assignment.payload['labelId'], kanbanStatusTodoId);

      final taskOrder = byCommand('task.reorder');
      expect(taskOrder.entityType, 'task');
      expect(taskOrder.payload, contains('orderKey'));
      expect(taskOrder.payload, isNot(contains('content')));
    });

    test('compacts never-attempted task edits and reorders', () async {
      final taskId = await tasks.createTask(
        const CreateTaskInput(content: 'Initial'),
      );
      await db.delete(db.syncCommands).go();
      await tasks.updateTask(
        taskId,
        const UpdateTaskPatch(content: 'First edit'),
      );
      await tasks.updateTask(
        taskId,
        const UpdateTaskPatch(content: 'Final edit'),
      );
      await queue.enqueue(
        type: 'task.reorder',
        clientId: taskId,
        payload: {'id': taskId, 'orderKey': '100'},
      );
      await queue.enqueue(
        type: 'task.reorder',
        clientId: taskId,
        payload: {'id': taskId, 'orderKey': '200'},
      );
      final pending = await queue.watchPending().first;
      final retainedIds = {
        pending.where((row) => row.type == 'task.update').last.uuid,
        pending.where((row) => row.type == 'task.reorder').last.uuid,
      };

      await engine.pushPending();

      final taskOperations = account.pushed
          .where((operation) => operation.entityId == taskId)
          .toList();
      expect(taskOperations, hasLength(2));
      expect(
        taskOperations.map((operation) => operation.opId).toSet(),
        retainedIds,
      );
      expect(
        taskOperations
            .singleWhere(
              (operation) => operation.payload['commandType'] == 'task.update',
            )
            .payload['content'],
        'Final edit',
      );
      expect(
        taskOperations
            .singleWhere(
              (operation) => operation.payload['commandType'] == 'task.reorder',
            )
            .payload['orderKey'],
        '200',
      );
      final stored = await db.select(db.syncCommands).get();
      expect(stored, isEmpty);
    });

    test(
      'syncNow reports locally pushed task entities and prunes finished commands',
      () async {
        await engine.prepareLocalAccountData();
        await engine.importLocalSnapshotIfNeeded();
        account.pushed.clear();

        await queue.enqueue(
          type: 'google_calendar.connection.upsert',
          clientId: 'old-synced',
          payload: const {'id': 'old-synced'},
        );
        await (db.update(db.syncCommands)
              ..where((row) => row.clientId.equals('old-synced')))
            .write(const SyncCommandsCompanion(status: Value('synced')));
        await queue.enqueue(
          type: 'google_calendar.connection.upsert',
          clientId: 'old-compacted',
          payload: const {'id': 'old-compacted'},
        );
        await (db.update(db.syncCommands)
              ..where((row) => row.clientId.equals('old-compacted')))
            .write(const SyncCommandsCompanion(status: Value('compacted')));
        final taskId = await tasks.createTask(
          const CreateTaskInput(content: 'Sync me once'),
        );

        final entityTypes = await engine.syncNow();

        expect(entityTypes, contains('task'));
        expect(
          account.pushed.where(
            (operation) =>
                operation.entityType == 'task' && operation.entityId == taskId,
          ),
          hasLength(1),
        );
        expect(await db.select(db.syncCommands).get(), isEmpty);
        expect(
          await (db.select(
            db.tasks,
          )..where((row) => row.id.equals(taskId))).getSingleOrNull(),
          isNotNull,
        );
      },
    );

    test('elides a never-attempted task create followed by delete', () async {
      final taskId = await tasks.createTask(
        const CreateTaskInput(content: 'Never uploaded'),
      );
      await tasks.deleteTask(taskId);
      await (db.update(
        db.syncCommands,
      )..where((row) => row.type.equals('task.delete'))).write(
        SyncCommandsCompanion(
          availableAt: Value(
            DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
          ),
        ),
      );

      await engine.pushPending();

      expect(account.pushed, isEmpty);
      expect(await queue.watchPending().first, isEmpty);
    });

    test('keeps a tombstone after an attempted task create', () async {
      final taskId = await tasks.createTask(
        const CreateTaskInput(content: 'Possibly uploaded'),
      );
      await (db.update(db.syncCommands)
            ..where((row) => row.clientId.equals(taskId)))
          .write(const SyncCommandsCompanion(attempts: Value(1)));
      await tasks.deleteTask(taskId);
      await (db.update(
        db.syncCommands,
      )..where((row) => row.type.equals('task.delete'))).write(
        SyncCommandsCompanion(
          availableAt: Value(
            DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
          ),
        ),
      );

      await engine.pushPending();

      expect(
        account.pushed.where(
          (operation) =>
              operation.entityId == taskId && operation.operation == 'delete',
        ),
        hasLength(1),
      );
    });

    test('pushes ready commands while a delete is deferred', () async {
      final availableAt = DateTime.now().toUtc().add(const Duration(hours: 1));
      await queue.enqueue(
        type: 'task.delete',
        clientId: 'deferred-task',
        payload: const {'id': 'deferred-task'},
        availableAt: availableAt,
      );
      await queue.enqueue(
        type: 'task.update',
        clientId: 'ready-task',
        payload: const {'id': 'ready-task'},
      );

      await engine.pushPending();

      expect(
        account.pushed.map((operation) => operation.entityId),
        contains('ready-task'),
      );
      expect(
        account.pushed.map((operation) => operation.entityId),
        isNot(contains('deferred-task')),
      );
      final pending = await queue.watchPending().first;
      expect(pending.single.clientId, 'deferred-task');
      expect(
        pending.single.availableAt?.toUtc(),
        DateTime.fromMillisecondsSinceEpoch(
          (availableAt.millisecondsSinceEpoch ~/ 1000) * 1000,
          isUtc: true,
        ),
      );
    });

    test('remote upsert preserves a pending local delete', () async {
      final taskId = await tasks.createTask(
        const CreateTaskInput(content: 'Delete locally'),
      );
      await db.delete(db.syncCommands).go();
      final batch = await tasks.deleteTask(taskId);
      final stored = await (db.select(
        db.tasks,
      )..where((row) => row.id.equals(taskId))).getSingle();
      final remoteData = stored.toJson()
        ..['content'] = 'Updated remotely'
        ..['isDeleted'] = false
        ..['updatedAt'] = DateTime.now().toUtc().toIso8601String();
      account.pullResults.add(
        AccountSyncPullResult(
          nextCursor: 1,
          hasMore: false,
          changes: [
            AccountSyncEntity(
              entityType: 'task',
              entityId: taskId,
              serverRevision: 1,
              data: remoteData,
            ),
          ],
        ),
      );

      await engine.pullLatest();

      final updated = await (db.select(
        db.tasks,
      )..where((row) => row.id.equals(taskId))).getSingle();
      expect(updated.content, 'Updated remotely');
      expect(updated.isDeleted, isTrue);
      expect(await tasks.restoreDeletedTasks(batch), isTrue);
    });

    test(
      'stale task pulls cannot roll back repeated local schedules',
      () async {
        final day = DateTime.utc(2026, 9, 3);
        TaskSchedule scheduleAt(int hour) => TaskSchedule.timed(
          start: day.add(Duration(hours: hour)),
          end: day.add(Duration(hours: hour + 1)),
        );

        final taskId = await tasks.createTask(
          CreateTaskInput(content: 'Keep latest time', schedule: scheduleAt(9)),
        );
        await db.delete(db.syncCommands).go();

        final firstLocal = scheduleAt(11);
        await tasks.updateTask(taskId, UpdateTaskPatch(schedule: firstLocal));
        final firstLocalUpdatedAt = DateTime.utc(2026, 9, 3, 12);
        await (db.update(db.tasks)..where((row) => row.id.equals(taskId)))
            .write(TasksCompanion(updatedAt: Value(firstLocalUpdatedAt)));
        final firstStaleData =
            (await (db.select(
                db.tasks,
              )..where((row) => row.id.equals(taskId))).getSingle()).toJson()
              ..['dueJson'] = scheduleAt(9).toJsonString()
              ..['durationSeconds'] = const Duration(hours: 1).inSeconds
              ..['updatedAt'] = DateTime.utc(2026, 9, 3, 10).toIso8601String();
        account.pullResults.add(
          AccountSyncPullResult(
            nextCursor: 1,
            hasMore: false,
            changes: [
              AccountSyncEntity(
                entityType: 'task',
                entityId: taskId,
                serverRevision: 1,
                data: firstStaleData,
              ),
            ],
          ),
        );

        await engine.pullLatest();

        expect((await tasks.watchTask(taskId).first)!.schedule, firstLocal);
        expect(
          (await queue.watchPending().first).map((command) => command.type),
          contains('task.update'),
        );
        await engine.pushPending();
        expect(
          TaskSchedule.fromJsonString(
            account.pushed
                    .lastWhere((operation) => operation.entityId == taskId)
                    .payload['dueJson']
                as String?,
          ),
          firstLocal,
        );

        final secondLocal = scheduleAt(14);
        await tasks.updateTask(taskId, UpdateTaskPatch(schedule: secondLocal));
        await (db.update(
          db.tasks,
        )..where((row) => row.id.equals(taskId))).write(
          TasksCompanion(updatedAt: Value(DateTime.utc(2026, 9, 3, 15))),
        );
        final secondStaleData =
            (await (db.select(
                db.tasks,
              )..where((row) => row.id.equals(taskId))).getSingle()).toJson()
              ..['dueJson'] = firstLocal.toJsonString()
              ..['updatedAt'] = firstLocalUpdatedAt.toIso8601String();
        account.pullResults.add(
          AccountSyncPullResult(
            nextCursor: 2,
            hasMore: false,
            changes: [
              AccountSyncEntity(
                entityType: 'task',
                entityId: taskId,
                serverRevision: 2,
                data: secondStaleData,
              ),
            ],
          ),
        );

        await engine.pullLatest();

        expect(account.pullSinceRevisions, [0, 1]);
        expect((await tasks.watchTask(taskId).first)!.schedule, secondLocal);
        await engine.pushPending();
        expect(
          TaskSchedule.fromJsonString(
            account.pushed
                    .lastWhere((operation) => operation.entityId == taskId)
                    .payload['dueJson']
                as String?,
          ),
          secondLocal,
        );
      },
    );

    test('newer and equal task pulls apply in server revision order', () async {
      final day = DateTime.utc(2026, 9, 3);
      TaskSchedule scheduleAt(int hour) => TaskSchedule.timed(
        start: day.add(Duration(hours: hour)),
        end: day.add(Duration(hours: hour + 1)),
      );

      final taskId = await tasks.createTask(
        CreateTaskInput(content: 'Accept server time', schedule: scheduleAt(9)),
      );
      await db.delete(db.syncCommands).go();
      final localUpdatedAt = DateTime.utc(2026, 9, 3, 10);
      await (db.update(db.tasks)..where((row) => row.id.equals(taskId))).write(
        TasksCompanion(updatedAt: Value(localUpdatedAt)),
      );

      final newerUpdatedAt = DateTime.utc(2026, 9, 3, 12);
      final newerData =
          (await (db.select(
              db.tasks,
            )..where((row) => row.id.equals(taskId))).getSingle()).toJson()
            ..['dueJson'] = scheduleAt(11).toJsonString()
            ..['updatedAt'] = newerUpdatedAt.toIso8601String();
      account.pullResults.add(
        AccountSyncPullResult(
          nextCursor: 1,
          hasMore: false,
          changes: [
            AccountSyncEntity(
              entityType: 'task',
              entityId: taskId,
              serverRevision: 1,
              data: newerData,
            ),
          ],
        ),
      );
      await engine.pullLatest();
      expect((await tasks.watchTask(taskId).first)!.schedule, scheduleAt(11));

      final equalData =
          (await (db.select(
              db.tasks,
            )..where((row) => row.id.equals(taskId))).getSingle()).toJson()
            ..['dueJson'] = scheduleAt(13).toJsonString()
            ..['updatedAt'] = newerUpdatedAt.toIso8601String();
      account.pullResults.add(
        AccountSyncPullResult(
          nextCursor: 2,
          hasMore: false,
          changes: [
            AccountSyncEntity(
              entityType: 'task',
              entityId: taskId,
              serverRevision: 2,
              data: equalData,
            ),
          ],
        ),
      );
      await engine.pullLatest();

      expect((await tasks.watchTask(taskId).first)!.schedule, scheduleAt(13));
    });

    test('remote delete cancels local Undo', () async {
      final taskId = await tasks.createTask(
        const CreateTaskInput(content: 'Deleted everywhere'),
      );
      await db.delete(db.syncCommands).go();
      final batch = await tasks.deleteTask(taskId);
      account.pullResults.add(
        AccountSyncPullResult(
          nextCursor: 1,
          hasMore: false,
          changes: [
            AccountSyncEntity(
              entityType: 'task',
              entityId: taskId,
              serverRevision: 1,
              data: const {},
              deletedAt: DateTime.now().toUtc(),
            ),
          ],
        ),
      );

      await engine.pullLatest();

      expect(await queue.watchPending().first, isEmpty);
      expect(await tasks.restoreDeletedTasks(batch), isFalse);
    });

    test(
      'offline completion commands retain their captured completion',
      () async {
        final taskId = await tasks.createTask(
          const CreateTaskInput(
            content: 'Complete twice',
            kanbanStatusId: kanbanStatusTodoId,
          ),
        );
        await db.delete(db.syncCommands).go();

        await tasks.completeTask(taskId);
        await tasks.uncompleteTask(taskId);
        await kanban.moveTask(taskId, statusId: kanbanStatusInProgressId);
        await tasks.completeTask(taskId);

        await engine.pushPending();

        final completionOperations = account.pushed
            .where((operation) => operation.entityType == 'task_completion')
            .toList();
        expect(completionOperations, hasLength(2));
        expect(
          completionOperations.map((operation) => operation.entityId).toSet(),
          hasLength(2),
        );
        expect(
          completionOperations
              .map((operation) => operation.payload['snapshotJson'])
              .toSet(),
          {
            _snapshotJson(kanbanStatusTodoId),
            _snapshotJson(kanbanStatusInProgressId),
          },
        );
      },
    );

    test(
      'final pull imports Kanban entities and repairs invariants once',
      () async {
        final assignedTaskId = await tasks.createTask(
          const CreateTaskInput(content: 'Remote assignment'),
        );
        final completedTaskId = await tasks.createTask(
          const CreateTaskInput(
            content: 'Repair completed',
            kanbanStatusId: kanbanStatusTodoId,
          ),
        );
        final now = DateTime.utc(2026, 7, 10, 10);
        await (db.update(
          db.tasks,
        )..where((row) => row.id.equals(completedTaskId))).write(
          TasksCompanion(
            status: const Value('completed'),
            completedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
        await db.delete(db.syncCommands).go();

        account.pullResults.add(
          AccountSyncPullResult(
            nextCursor: 4,
            hasMore: false,
            changes: [
              AccountSyncEntity(
                entityType: 'task_kanban_status',
                entityId: assignedTaskId,
                serverRevision: 1,
                data: {
                  'taskId': assignedTaskId,
                  'labelId': kanbanStatusTodoId,
                  'changedAt': now.toIso8601String(),
                },
              ),
              AccountSyncEntity(
                entityType: 'kanban_settings',
                entityId: kanbanSettingsPrimaryId,
                serverRevision: 2,
                data: {
                  'id': kanbanSettingsPrimaryId,
                  'selectedProjectIdsJson': jsonEncode([inboxProjectId]),
                  'focusStatusLabelId': kanbanStatusTodoId,
                  'updatedAt': now.millisecondsSinceEpoch,
                },
              ),
              AccountSyncEntity(
                entityType: 'label',
                entityId: kanbanStatusDoneId,
                serverRevision: 3,
                data: const {},
                deletedAt: now,
              ),
            ],
          ),
        );

        await engine.pullLatest();

        expect(await _statusId(db, assignedTaskId), kanbanStatusTodoId);
        expect(await _statusId(db, completedTaskId), kanbanStatusDoneId);
        final settings = await (db.select(
          db.kanbanSettings,
        )..where((row) => row.id.equals(kanbanSettingsPrimaryId))).getSingle();
        expect(settings.focusStatusLabelId, kanbanStatusTodoId);
        expect(jsonDecode(settings.selectedProjectIdsJson), [inboxProjectId]);
        final done = await (db.select(
          db.labels,
        )..where((row) => row.id.equals(kanbanStatusDoneId))).getSingle();
        expect(done.isDeleted, isFalse);
        final commands = await queue.watchPending().first;
        expect(
          commands.where(
            (command) =>
                command.type == 'task.kanbanStatus.set' &&
                command.clientId == completedTaskId,
          ),
          hasLength(1),
        );
      },
    );

    test('repair waits for the final pull page', () async {
      final taskId = await tasks.createTask(
        const CreateTaskInput(content: 'Paged assignment'),
      );
      await db.delete(db.syncCommands).go();
      final now = DateTime.utc(2026, 7, 10, 11);
      const customStatusId = 'custom-status';
      account.pullResults.addAll([
        AccountSyncPullResult(
          nextCursor: 1,
          hasMore: true,
          changes: [
            AccountSyncEntity(
              entityType: 'task_kanban_status',
              entityId: taskId,
              serverRevision: 1,
              data: {
                'taskId': taskId,
                'labelId': customStatusId,
                'changedAt': now.toIso8601String(),
              },
            ),
          ],
        ),
        AccountSyncPullResult(
          nextCursor: 2,
          hasMore: false,
          changes: [
            AccountSyncEntity(
              entityType: 'label',
              entityId: customStatusId,
              serverRevision: 2,
              data: {
                'id': customStatusId,
                'userId': localUserId,
                'name': 'Review',
                'color': null,
                'kind': labelKindKanbanStatus,
                'systemKey': null,
                'orderKey': '00000000000000002500',
                'isFavorite': false,
                'isDeleted': false,
                'createdAt': now.toIso8601String(),
                'updatedAt': now.toIso8601String(),
              },
            ),
          ],
        ),
      ]);

      await engine.pullLatest();

      expect(await _statusId(db, taskId), customStatusId);
    });
  });
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

String _snapshotJson(String statusId) =>
    '{"version":1,"kanban":{"previousStatusLabelId":"$statusId"}}';

class _RecordingAccountClient implements AccountClient {
  final pushed = <AccountSyncOperation>[];
  final pullResults = Queue<AccountSyncPullResult>();
  final pullSinceRevisions = <int>[];

  @override
  String? get currentUserId => 'account-user';

  @override
  Future<AccountSyncPushResult> pushChanges({
    required String appId,
    required String deviceId,
    required List<AccountSyncOperation> operations,
  }) async {
    pushed.addAll(operations);
    return const AccountSyncPushResult(serverRevision: 0, applied: []);
  }

  @override
  Future<AccountSyncPullResult> pullChanges({
    required String appId,
    required String deviceId,
    required int sinceRevision,
    int limit = 500,
  }) async {
    pullSinceRevisions.add(sinceRevision);
    if (pullResults.isNotEmpty) {
      return pullResults.removeFirst();
    }
    return AccountSyncPullResult(
      nextCursor: sinceRevision,
      hasMore: false,
      changes: const [],
    );
  }

  @override
  Future<void> broadcastSyncHint({
    required String appId,
    required String deviceId,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
