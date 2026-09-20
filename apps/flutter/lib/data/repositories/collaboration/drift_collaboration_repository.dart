import 'dart:convert';
import 'collaboration_repository.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_conflict.dart';
import 'package:pomodoist/utils/result.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_responses.dart';
import 'package:pomodoist/domain/models/collaboration/public_project.dart';
import 'package:pomodoist/data/services/collaboration/collaboration_api.dart';
import 'package:pomodoist/data/services/local/shared_access.dart';

class DriftCollaborationRepository implements CollaborationRepository {
  DriftCollaborationRepository({
    required this.db,
    required this.api,
    required this.queue,
    required this.synchronize,
  });
  final AppDatabase db;
  final CollaborationApi api;
  final OutboxService queue;
  final Future<void> Function() synchronize;

  @override
  Future<Result<PublicProject>> publicRead(String token) => Result.capture(
    () async => PublicProject.fromResponse(await api.publicRead(token)),
  );

  @override
  Future<Result<String>> actorId() =>
      Result.capture(() => SharedAccess(db).actorId());

  @override
  Future<Result<CollaborationState>> state() => Result.capture(
    () async => CollaborationState.fromJson(await api.state()),
  );

  @override
  Future<Result<SharedScope>> acceptInvitation(String token) =>
      Result.capture(() async {
        final response = await _mutate(() => api.acceptInvitation(token));
        return _scope(response);
      });

  @override
  Future<Result<void>> unshare(String scopeId) => Result.capture(() async {
    await _mutate(() => api.unshare(scopeId));
  });

  @override
  Future<Result<SharedScope>> share(String projectId) =>
      Result.capture(() => _share(projectId));

  @override
  Future<Result<CollaborationMembers>> members(String scopeId) =>
      Result.capture(
        () async => CollaborationMembers.fromJson(await api.members(scopeId)),
      );

  @override
  Future<Result<CollaborationInviteOutcome>> invite(
    String scopeId, {
    required String email,
    required CollaborationRole role,
  }) => Result.capture(() async {
    final response = await _mutate(
      () => api.invite(scopeId: scopeId, email: email, role: role),
    );
    return CollaborationInviteOutcome.fromJson(response);
  });

  @override
  Future<Result<void>> revokeInvitation(String scopeId, String invitationId) =>
      Result.capture(() async {
        await _mutate(
          () => api.revokeInvitation(
            scopeId: scopeId,
            invitationId: invitationId,
          ),
        );
      });

  @override
  Future<Result<void>> setMemberRole(
    String scopeId,
    String userId,
    CollaborationRole role,
  ) => Result.capture(() async {
    await _mutate(
      () => api.setMemberRole(scopeId: scopeId, userId: userId, role: role),
    );
  });

  @override
  Future<Result<void>> removeMember(String scopeId, String userId) =>
      Result.capture(() async {
        await _mutate(() => api.removeMember(scopeId: scopeId, userId: userId));
      });

  @override
  Future<Result<void>> transferOwnership(String scopeId, String userId) =>
      Result.capture(() async {
        await _mutate(
          () => api.transferOwnership(scopeId: scopeId, userId: userId),
        );
      });

  @override
  Future<Result<void>> leaveScope(String scopeId) => Result.capture(() async {
    await _mutate(() => api.leaveScope(scopeId));
  });

  @override
  Future<Result<void>> deleteScope(String scopeId) => Result.capture(() async {
    await _mutate(() => api.deleteScope(scopeId));
  });

  @override
  Future<Result<void>> markNotificationRead(String notificationId) =>
      Result.capture(() async {
        await _mutate(() => api.markNotificationRead(notificationId));
      });

  @override
  Future<Result<void>> setAssignees(String taskId, Set<String> ids) =>
      Result.capture(() => _setAssignees(taskId, ids));

  @override
  Future<Result<void>> comment(
    String scopeId,
    String taskId,
    String text, {
    String? commentId,
    List<String> mentions = const [],
  }) => Result.capture(
    () => _comment(
      scopeId,
      taskId,
      text,
      commentId: commentId,
      mentions: mentions,
    ),
  );

  @override
  Future<Result<void>> deleteComment(String scopeId, String id) =>
      Result.capture(() => _deleteComment(scopeId, id));

  @override
  Future<Result<void>> resolveConflict(
    CollaborationConflict command, {
    required bool keepLocal,
  }) => Result.capture(() => _resolveConflict(command, keepLocal: keepLocal));

  @override
  Stream<List<SharedScope>> watchScopes() => db
      .select(db.sharedScopes)
      .watch()
      .map(
        (rows) => rows
            .map((row) => SharedScope.fromJson(jsonDecode(row.dataJson)))
            .toList(),
      );

  @override
  Stream<List<CollaborationComment>> watchComments(
    String scopeId, {
    String? taskId,
  }) => _watchEntities(
    scopeId,
    'comment',
    taskId: taskId,
  ).map((rows) => [for (final row in rows) CollaborationComment.fromJson(row)]);

  @override
  Stream<List<CollaborationFocusContribution>> watchFocusContributions(
    String scopeId, {
    String? taskId,
  }) => _watchEntities(scopeId, 'focus_interval', taskId: taskId).map(
    (rows) => [
      for (final row in rows) CollaborationFocusContribution.fromJson(row),
    ],
  );

  Stream<List<Map<String, dynamic>>> _watchEntities(
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

  SharedScope _scope(Map<String, dynamic> response) {
    final scope = response['scope'];
    if (scope is! Map) {
      throw const CollaborationException(
        'invalid_response',
        'The server did not return a shared scope.',
      );
    }
    return SharedScope.fromJson(Map<String, dynamic>.from(scope));
  }

  // The server already applied the change, so a failing local synchronization
  // must not turn it into an error reported to the user.
  Future<Map<String, dynamic>> _mutate(
    Future<Map<String, dynamic>> Function() request,
  ) async {
    final result = await request();
    try {
      await synchronize();
    } catch (_) {
      /* The server has already applied the change. */
    }
    return result;
  }

  Future<SharedScope> _share(String projectId) async {
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
    final state = CollaborationState.fromJson(await api.state());
    final response = await _mutate(
      () => api.share(
        projectId: projectId,
        expectedRevision: state.personalRevision,
      ),
    );
    return _scope(response);
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

  Future<void> _setAssignees(String taskId, Set<String> ids) async {
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
          .where((member) => member.role.canEdit)
          .map((member) => member.userId)
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

  Future<void> _comment(
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

  Future<void> _deleteComment(String scopeId, String id) async {
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

  @override
  Stream<List<CollaborationConflict>> watchConflicts() =>
      (db.select(db.syncCommands)..where(
            (row) => row.scopeId.isNotNull() & row.status.equals('conflict'),
          ))
          .watch()
          .map(
            (rows) => rows
                .map(
                  (row) => CollaborationConflict(
                    id: row.id,
                    scopeId: row.scopeId!,
                    type: row.type,
                    clientId: row.clientId,
                    lastError: row.lastError,
                    baseRevision: row.baseRevision,
                  ),
                )
                .toList(growable: false),
          );

  Future<void> _resolveConflict(
    CollaborationConflict command, {
    required bool keepLocal,
  }) async {
    if (keepLocal) {
      await SharedAccess(db).requireEdit(command.scopeId);
      await (db.update(
        db.syncCommands,
      )..where((row) => row.id.equals(command.id))).write(
        SyncCommandsCompanion(
          uuid: Value(const Uuid().v4()),
          status: const Value('pending'),
          baseRevision: Value(command.serverRevision),
          lastError: const Value(null),
        ),
      );
    } else {
      await (db.delete(
        db.syncCommands,
      )..where((row) => row.id.equals(command.id))).go();
    }
    await (db.update(db.sharedScopes)
          ..where((row) => row.id.equals(command.scopeId)))
        .write(const SharedScopesCompanion(cursor: Value(0)));
    await synchronize();
  }
}
