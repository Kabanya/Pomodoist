import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../../core/db/app_database.dart';
import '../../../core/sync/sync_queue_repository.dart';
import '../domain/collaboration_models.dart';
import 'collaboration_api.dart';
import 'shared_access.dart';

class CollaborationRepository {
  CollaborationRepository({
    required this.db,
    required this.api,
    required this.queue,
    required this.synchronize,
  });
  final AppDatabase db;
  final CollaborationApi api;
  final SyncQueueRepository queue;
  final Future<void> Function() synchronize;

  Stream<List<SharedScope>> watchScopes() => db
      .select(db.sharedScopes)
      .watch()
      .map(
        (rows) => rows
            .map((row) => SharedScope.fromJson(jsonDecode(row.dataJson)))
            .toList(),
      );

  Stream<List<Map<String, dynamic>>> watchEntities(
    String scopeId,
    String type, {
    String? taskId,
  }) =>
      (db.select(db.sharedEntities)..where(
            (row) =>
                row.scopeId.equals(scopeId) &
                row.entityType.equals(type) &
                row.isDeleted.equals(false),
          ))
          .watch()
          .map((rows) {
            final result = rows
                .map(
                  (row) => <String, dynamic>{
                    ...jsonDecode(row.dataJson) as Map<String, dynamic>,
                    'id': row.entityId,
                    'serverRevision': row.serverRevision,
                  },
                )
                .where((row) => taskId == null || row['taskId'] == taskId)
                .toList();
            result.sort(
              (a, b) => (a['createdAt'] ?? '').toString().compareTo(
                (b['createdAt'] ?? '').toString(),
              ),
            );
            return result;
          });

  Future<Map<String, dynamic>> action(
    String action, [
    Map<String, dynamic> args = const {},
  ]) async {
    final result = await api.call(action, args);
    await synchronize();
    return result;
  }

  // Reads the collaboration state without touching the local database, which
  // may not be open yet while the invitation screen loads.
  Future<Map<String, dynamic>> state() => api.call('state');

  // The server already applied the change, so a failing local synchronization
  // must not turn it into an error reported to the user.
  Future<Map<String, dynamic>> mutate(
    String action,
    Map<String, dynamic> args,
  ) async {
    final result = await api.call(action, args);
    try {
      await synchronize();
    } catch (_) {
      /* The server has already applied the change. */
    }
    return result;
  }

  Future<Map<String, dynamic>> acceptInvitation(String token) =>
      mutate('accept', {'token': token});

  Future<Map<String, dynamic>> share(String projectId) async {
    final subtreeIds = await _shareEntityIds(projectId);
    var outstanding = await _outstandingPersonalCommands();
    while (true) {
      final previousIds = outstanding.map((row) => row.id).toSet();
      await synchronize();
      outstanding = await _outstandingPersonalCommands();
      if (previousIds
          .difference(outstanding.map((row) => row.id).toSet())
          .isEmpty) {
        break;
      }
      if (outstanding.isEmpty) break;
    }
    subtreeIds.addAll(await _shareEntityIds(projectId));
    if (outstanding.any((command) {
      final payload = jsonDecode(command.payloadJson) as Map<String, dynamic>;
      return subtreeIds.contains(command.clientId) ||
          [
            'id',
            'taskId',
            'projectId',
            'parentId',
            'sectionId',
            'labelId',
            'runId',
          ].any((key) => subtreeIds.contains(payload[key]));
    })) {
      throw const CollaborationException(
        'personal_sync_pending',
        'Finish synchronizing this project and resolve pending or deferred changes before sharing.',
      );
    }
    final state = await api.call('state');
    final revision = state['personalRevision'];
    return action('share', {
      'rootProjectId': projectId,
      'expectedRevision': revision is num
          ? revision.toInt()
          : int.tryParse('$revision') ?? 0,
    });
  }

  Future<List<SyncCommandRow>> _outstandingPersonalCommands() =>
      (db.select(db.syncCommands)..where(
            (row) =>
                row.scopeId.isNull() &
                row.status.isNotIn(['synced', 'compacted']),
          ))
          .get();

  Future<Set<String>> _shareEntityIds(String rootId) async {
    final rows = await db
        .customSelect(
          '''
      WITH RECURSIVE tree(id) AS (
        SELECT ? UNION SELECT p.id FROM projects p JOIN tree t ON p.parent_id = t.id
      ), project_tasks(id) AS (SELECT id FROM tasks WHERE project_id IN (SELECT id FROM tree))
      SELECT id FROM tree
      UNION SELECT id FROM project_tasks
      UNION SELECT id FROM sections WHERE project_id IN (SELECT id FROM tree)
      UNION SELECT id FROM task_completions WHERE task_id IN (SELECT id FROM project_tasks)
      UNION SELECT id FROM focus_intervals WHERE task_id IN (SELECT id FROM project_tasks)
      UNION SELECT run_id FROM focus_intervals WHERE task_id IN (SELECT id FROM project_tasks)
      UNION SELECT label_id FROM task_labels WHERE task_id IN (SELECT id FROM project_tasks)
      UNION SELECT id FROM labels WHERE scope_id IS NULL AND kind = 'kanbanStatus'
    ''',
          variables: [Variable.withString(rootId)],
        )
        .get();
    return rows.map((row) => row.read<String>('id')).toSet();
  }

  Future<void> setAssignees(String taskId, Set<String> ids) async {
    final access = SharedAccess(db);
    await access.task(taskId);
    await db.transaction(() async {
      final task = await (db.select(
        db.tasks,
      )..where((row) => row.id.equals(taskId))).getSingle();
      if (task.scopeId == null) {
        throw const CollaborationException('shared_task_required');
      }
      final scope = await access.scope(task.scopeId);
      final editors = scope!.members
          .where((m) => m['role'] != 'observer')
          .map((m) => m['userId'])
          .toSet();
      final previous = collaborationIds(task.assigneeIdsJson).toSet();
      final add = ids.difference(previous).toList();
      final remove = previous.difference(ids).toList();
      if (add.isEmpty && remove.isEmpty) return;
      // The server validates only the added users, so an id that is merely
      // retained does not block a removal.
      if (!editors.containsAll(add)) {
        throw const CollaborationException('invalid_assignee');
      }
      await (db.update(db.tasks)..where((row) => row.id.equals(taskId))).write(
        TasksCompanion(
          assigneeIdsJson: Value(jsonEncode(ids.toList()..sort())),
        ),
      );
      await queue.enqueue(
        type: 'task.assign',
        clientId: taskId,
        payload: {
          'scopeId': task.scopeId,
          'id': taskId,
          'add': add,
          'remove': remove,
        },
      );
    });
  }

  Future<void> comment(
    String scopeId,
    String taskId,
    String text, {
    String? commentId,
    List<String> mentions = const [],
  }) async {
    final body = text.trim();
    if (body.isEmpty || body.length > 10000) {
      throw const CollaborationException('invalid_comment');
    }
    final access = SharedAccess(db);
    await access.task(taskId);
    final task = await (db.select(
      db.tasks,
    )..where((row) => row.id.equals(taskId))).getSingle();
    if (task.scopeId != scopeId) {
      throw const CollaborationException('cross_scope_comment');
    }
    await access.requireEdit(scopeId);
    final actor = await access.actorId();
    final id = commentId ?? const Uuid().v4();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction(() async {
      final existing =
          await (db.select(db.sharedEntities)..where(
                (row) =>
                    row.scopeId.equals(scopeId) &
                    row.entityType.equals('comment') &
                    row.entityId.equals(id),
              ))
              .getSingleOrNull();
      final old = existing == null
          ? <String, dynamic>{}
          : jsonDecode(existing.dataJson) as Map<String, dynamic>;
      if (commentId != null &&
          (existing == null || old['createdBy'] != actor)) {
        throw const CollaborationException('forbidden');
      }
      final data = <String, dynamic>{
        ...old,
        'id': id,
        'scopeId': scopeId,
        'taskId': taskId,
        'body': body,
        'mentions': mentions,
        'createdBy': actor,
        'createdAt': old['createdAt'] ?? now,
        'updatedAt': now,
      };
      await db
          .into(db.sharedEntities)
          .insertOnConflictUpdate(
            SharedEntitiesCompanion.insert(
              scopeId: scopeId,
              entityType: 'comment',
              entityId: id,
              dataJson: jsonEncode(data),
              serverRevision: Value(existing?.serverRevision ?? 0),
            ),
          );
      await queue.enqueue(
        type: commentId == null ? 'comment.create' : 'comment.update',
        clientId: id,
        payload: data,
      );
    });
  }

  Future<void> deleteComment(String scopeId, String id) async {
    final access = SharedAccess(db);
    final scope = await access.scope(scopeId);
    await access.requireEdit(scopeId);
    await db.transaction(() async {
      final row =
          await (db.select(db.sharedEntities)..where(
                (row) =>
                    row.scopeId.equals(scopeId) &
                    row.entityType.equals('comment') &
                    row.entityId.equals(id),
              ))
              .getSingle();
      final data = jsonDecode(row.dataJson) as Map<String, dynamic>;
      if (data['createdBy'] != await access.actorId() &&
          !(scope?.canManage ?? false)) {
        throw const CollaborationException('forbidden');
      }
      await (db.update(db.sharedEntities)..where(
            (row) =>
                row.scopeId.equals(scopeId) &
                row.entityType.equals('comment') &
                row.entityId.equals(id),
          ))
          .write(const SharedEntitiesCompanion(isDeleted: Value(true)));
      await queue.enqueue(
        type: 'comment.delete',
        clientId: id,
        payload: {'id': id, 'scopeId': scopeId, 'taskId': data['taskId']},
      );
    });
  }

  Stream<List<SyncCommandRow>> watchConflicts() =>
      (db.select(db.syncCommands)..where(
            (row) => row.scopeId.isNotNull() & row.status.equals('conflict'),
          ))
          .watch();

  Future<void> resolveConflict(
    SyncCommandRow command, {
    required bool keepLocal,
  }) async {
    final conflict =
        jsonDecode(command.lastError ?? '{}') as Map<String, dynamic>;
    if (keepLocal) {
      await SharedAccess(db).requireEdit(command.scopeId);
      await (db.update(
        db.syncCommands,
      )..where((row) => row.id.equals(command.id))).write(
        SyncCommandsCompanion(
          uuid: Value(const Uuid().v4()),
          status: const Value('pending'),
          baseRevision: Value(
            (conflict['serverRevision'] as num?)?.toInt() ??
                command.baseRevision,
          ),
          lastError: const Value(null),
        ),
      );
    } else {
      await (db.delete(
        db.syncCommands,
      )..where((row) => row.id.equals(command.id))).go();
    }
    await (db.update(db.sharedScopes)
          ..where((row) => row.id.equals(command.scopeId!)))
        .write(const SharedScopesCompanion(cursor: Value(0)));
    await synchronize();
  }
}
