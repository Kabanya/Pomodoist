import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:app_account/app_account.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/sync/account_sync_engine.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/data/services/collaboration/collaboration_api.dart';
import 'package:pomodoist/data/repositories/collaboration/collaboration_repository.dart';
import 'package:pomodoist/data/repositories/collaboration/drift_collaboration_repository.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_conflict.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

void main() {
  late AppDatabase db;
  late AccountSyncEngine engine;
  late DriftOutboxService queue;
  late CollaborationRepository collaboration;
  late _Account account;
  final scope = {
    'id': 'scope',
    'rootProjectId': 'project',
    'ownerId': 'owner',
    'role': 'member',
  };
  var active = true;
  var revision = 2;
  var conflict = false;
  var taskRevision = 2;
  var rejected = false;
  final fieldRevisions = <String, int>{};
  final extraChanges = <Map<String, dynamic>>[];
  final pushes = <Map<String, dynamic>>[];
  Map<String, dynamic> task = {};
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.ensureSeedData();
    queue = DriftOutboxService(db);
    active = true;
    revision = 2;
    conflict = false;
    taskRevision = 2;
    rejected = false;
    fieldRevisions.clear();
    extraChanges.clear();
    pushes.clear();
    task = {
      'id': 'task',
      'projectId': 'project',
      'content': 'Shared',
      'createdBy': 'owner',
      'assigneeIds': ['me'],
    };
    final api = CollaborationApi((request) async {
      switch (request['action']) {
        case 'state':
          return {
            'scopes': active ? [scope] : [],
          };
        case 'pull':
          return {
            'changes':
                [
                      {
                        'entityType': 'project',
                        'entityId': 'project',
                        'serverRevision': 1,
                        'updatedAt': '2026-09-14T00:00:00Z',
                        'data': {'name': 'Project'},
                      },
                      {
                        'entityType': 'task',
                        'entityId': 'task',
                        'serverRevision': taskRevision,
                        'updatedAt': '2026-09-14T00:00:00Z',
                        'data': task,
                      },
                      ...extraChanges,
                    ]
                    .where(
                      (change) =>
                          (change['serverRevision'] as int) >
                          (request['sinceRevision'] as int),
                    )
                    .toList(),
            'nextCursor': revision,
            'hasMore': false,
            'members': [
              {'userId': 'me', 'role': 'member', 'displayName': 'Me'},
              {'userId': 'reader', 'role': 'observer', 'displayName': 'Reader'},
            ],
          };
        case 'push':
          pushes.add(request);
          final ops = (request['operations'] as List)
              .cast<Map<String, dynamic>>();
          if (rejected) {
            return {
              'applied': [],
              'conflicts': [],
              'rejected': [
                {'opId': ops.first['opId'], 'code': 'invalid_field'},
              ],
            };
          }
          final fields = (ops.first['payload'] as Map).keys
              .where(
                (key) =>
                    (fieldRevisions[key] ?? 0) >
                    (ops.first['baseRevision'] as int),
              )
              .toList();
          if (conflict || fields.isNotEmpty) {
            return {
              'conflicts': [
                {
                  'opId': ops.first['opId'],
                  'serverRevision': revision,
                  'fields': conflict ? ['content'] : fields,
                  'current': task,
                },
              ],
              'applied': [],
              'rejected': [],
            };
          }
          for (final op in ops) {
            revision++;
            if (op['entityType'] == 'task') {
              task = {...task, ...(op['payload'] as Map<String, dynamic>)};
              taskRevision = revision;
              for (final key in ['content', 'description']) {
                if ((op['payload'] as Map).containsKey(key)) {
                  fieldRevisions[key] = revision;
                }
              }
            } else {
              extraChanges.add({
                'entityType': op['entityType'],
                'entityId': op['entityId'],
                'serverRevision': revision,
                'updatedAt': '2026-09-14T00:00:00Z',
                'data': op['payload'],
              });
            }
          }
          return {
            'applied': [
              for (final op in ops)
                {'opId': op['opId'], 'serverRevision': revision},
            ],
            'conflicts': [],
            'rejected': [],
          };
        default:
          throw StateError('Unexpected action ${request['action']}');
      }
    });
    account = _Account();
    engine = AccountSyncEngine(
      db: db,
      uuid: const Uuid(),
      account: account,
      collaboration: api,
    );
    collaboration = DriftCollaborationRepository(
      db: db,
      api: api,
      queue: queue,
      synchronize: () async {
        await engine.syncShared();
      },
    );
    await engine.syncShared();
  });
  tearDown(() => db.close());

  test(
    'shared pull keeps scope, creator and assignees and replay uses shared revision',
    () async {
      final row = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals('task'))).getSingle();
      expect(row.scopeId, 'scope');
      expect(row.createdBy, 'owner');
      expect(jsonDecode(row.assigneeIdsJson), ['me']);
      await DriftTaskRepository(db, queue)
          .updateTask('task', const UpdateTaskPatch(content: 'My edit'))
          .then((result) => result.getOrThrow());
      final command = await db.select(db.syncCommands).getSingle();
      expect(command.scopeId, 'scope');
      expect(command.baseRevision, 2);
      await engine.syncShared();
      expect(pushes.single['scopeId'], 'scope');
      expect((pushes.single['operations'] as List).first['baseRevision'], 2);
      expect(await db.select(db.syncCommands).get(), isEmpty);
    },
  );

  test(
    'revocation discards shared snapshots and retains only own unsent text',
    () async {
      await DriftTaskRepository(db, queue)
          .updateTask('task', const UpdateTaskPatch(content: 'Own draft'))
          .then((result) => result.getOrThrow());
      active = false;
      await engine.syncShared();
      expect(
        await (db.select(db.tasks)..where((t) => t.scopeId.isNotNull())).get(),
        isEmpty,
      );
      expect(await db.select(db.sharedScopes).get(), isEmpty);
      expect(pushes, isEmpty);
      final draft = await db.select(db.syncCommands).getSingle();
      expect(draft.status, 'revoked');
      expect(jsonDecode(draft.payloadJson), {'content': 'Own draft'});
    },
  );

  test('unshared project returns as a personal row on the next pull', () async {
    active = false;
    await engine.syncShared();
    account.changes.addAll([
      AccountSyncEntity.fromJson({
        'entityType': 'project',
        'entityId': 'project',
        'serverRevision': 3,
        'updatedAt': '2026-09-15T00:00:00Z',
        'data': {
          'id': 'project',
          'userId': 'me',
          'name': 'Project',
          'viewStyle': 'list',
          'isFavorite': false,
          'isArchived': false,
          'isDeleted': false,
          'orderKey': 'a',
          'createdAt': '2026-09-14T00:00:00Z',
          'updatedAt': '2026-09-15T00:00:00Z',
        },
      }),
      AccountSyncEntity.fromJson({
        'entityType': 'task',
        'entityId': 'task',
        'serverRevision': 3,
        'updatedAt': '2026-09-15T00:00:00Z',
        'data': {
          'id': 'task',
          'userId': 'me',
          'content': 'Shared',
          'projectId': 'project',
          'priority': 4,
          'status': 'open',
          'completedFocusIntervals': 0,
          'totalFocusSeconds': 0,
          'orderKey': 'a',
          'isCollapsed': false,
          'isDeleted': false,
          'assigneeIds': ['me'],
          'createdAt': '2026-09-14T00:00:00Z',
          'updatedAt': '2026-09-15T00:00:00Z',
        },
      }),
    ]);
    await engine.pullLatest();
    expect(
      (await (db.select(
        db.projects,
      )..where((r) => r.id.equals('project'))).getSingle()).scopeId,
      isNull,
    );
    expect(
      (await (db.select(
        db.tasks,
      )..where((r) => r.id.equals('task'))).getSingle()).scopeId,
      isNull,
    );
  });

  test('conflicting text stays visible until explicit server choice', () async {
    await DriftTaskRepository(db, queue)
        .updateTask('task', const UpdateTaskPatch(content: 'Local text'))
        .then((result) => result.getOrThrow());
    task['content'] = 'Remote text';
    revision = taskRevision = 3;
    conflict = true;
    await engine.syncShared();
    final draft = await db.select(db.syncCommands).getSingle();
    expect(draft.status, 'conflict');
    expect(
      (await (db.select(
        db.tasks,
      )..where((t) => t.id.equals('task'))).getSingle()).content,
      'Local text',
    );
    (await collaboration.resolveConflict(
      CollaborationConflict(
        id: draft.id,
        scopeId: draft.scopeId!,
        type: draft.type,
        clientId: draft.clientId,
        lastError: draft.lastError,
        baseRevision: draft.baseRevision,
      ),
      keepLocal: false,
    )).getOrThrow();
    expect(
      (await (db.select(
        db.tasks,
      )..where((t) => t.id.equals('task'))).getSingle()).content,
      'Remote text',
    );
  });

  test(
    'accepting content never rebases an unseen remote description conflict',
    () async {
      final tasks = DriftTaskRepository(db, queue);
      await tasks
          .updateTask('task', const UpdateTaskPatch(content: 'Local content'))
          .then((result) => result.getOrThrow());
      await tasks
          .updateTask(
            'task',
            const UpdateTaskPatch(
              description: 'Local description',
              updateDescription: true,
            ),
          )
          .then((result) => result.getOrThrow());
      task['description'] = 'Remote description';
      revision = taskRevision = 3;
      fieldRevisions['description'] = 3;
      await engine.syncShared();
      final drafts = await db.select(db.syncCommands).get();
      expect(drafts, hasLength(1));
      final draft = drafts.single;
      expect(draft.status, 'conflict');
      expect(draft.baseRevision, 2);
      expect(task['description'], 'Remote description');
      expect(
        (await tasks.watchTask('task').first)!.description,
        'Local description',
      );
    },
  );

  test(
    'sequential edits to an accepted field do not conflict with themselves',
    () async {
      final tasks = DriftTaskRepository(db, queue);
      await tasks
          .updateTask('task', const UpdateTaskPatch(content: 'First'))
          .then((result) => result.getOrThrow());
      await tasks
          .updateTask('task', const UpdateTaskPatch(content: 'Second'))
          .then((result) => result.getOrThrow());
      task['description'] = 'Remote description';
      revision = taskRevision = 3;
      fieldRevisions['description'] = 3;
      await engine.syncShared();
      expect(await db.select(db.syncCommands).get(), isEmpty);
      expect((await tasks.watchTask('task').first)!.content, 'Second');
      expect(
        (await tasks.watchTask('task').first)!.description,
        'Remote description',
      );
    },
  );

  test(
    'relation acknowledgement cannot strand canonical task fields behind the cursor',
    () async {
      final tasks = DriftTaskRepository(db, queue);
      await tasks
          .updateTask('task', const UpdateTaskPatch(content: 'Local content'))
          .then((result) => result.getOrThrow());
      await queue.enqueue(
        type: 'task.kanbanStatus.set',
        clientId: 'task',
        payload: {'taskId': 'task', 'labelId': kanbanStatusBacklogId},
      );
      task['description'] = 'Remote description';
      revision = taskRevision = 3;
      await engine.syncShared();
      await engine.syncShared();
      expect(await db.select(db.syncCommands).get(), isEmpty);
      final row = (await tasks.watchTask('task').first)!;
      expect(row.content, 'Local content');
      expect(row.description, 'Remote description');
    },
  );

  test(
    'rejection restores cached canonical text even without a new server revision',
    () async {
      final tasks = DriftTaskRepository(db, queue);
      await tasks
          .updateTask('task', const UpdateTaskPatch(content: 'Rejected edit'))
          .then((result) => result.getOrThrow());
      rejected = true;
      await engine.syncShared();
      expect((await db.select(db.syncCommands).getSingle()).status, 'rejected');
      expect((await tasks.watchTask('task').first)!.content, 'Shared');
    },
  );

  test(
    'server completion JSON objects hydrate into personal completion history',
    () async {
      revision = 3;
      extraChanges.add({
        'entityType': 'task_completion',
        'entityId': 'completion',
        'serverRevision': 3,
        'updatedAt': '2026-09-14T00:00:00Z',
        'data': {
          'taskId': 'task',
          'userId': 'me',
          'completedAt': '2026-09-14T00:00:00Z',
          'snapshotJson': {
            'id': 'task',
            'content': 'Shared',
            'createdBy': 'owner',
          },
        },
      });
      await engine.syncShared();
      final completion = await db.select(db.taskCompletions).getSingle();
      expect(jsonDecode(completion.snapshotJson!)['content'], 'Shared');
    },
  );

  test('a posted comment carries only fields the scope accepts', () async {
    const scopeFields = {
      'id',
      'taskId',
      'body',
      'mentions',
      'createdAt',
      'updatedAt',
      'createdBy',
      'scopeId',
    };
    const envelopeFields = {
      'commandType',
      'isFavorite',
      'isCollapsed',
      'dayOrder',
      'viewStyle',
      'completedFocusIntervals',
      'totalFocusSeconds',
      'schemaVersion',
    };
    await collaboration.comment('scope', 'task', 'Hello from me');
    await engine.syncShared();
    final operation =
        (pushes.single['operations'] as List).single as Map<String, dynamic>;
    expect(operation['entityType'], 'comment');
    expect(operation['operation'], 'upsert');
    final payload = operation['payload'] as Map<String, dynamic>;
    expect(payload['taskId'], 'task');
    expect(payload['body'], 'Hello from me');
    expect(payload.keys, isNot(contains('schemaVersion')));
    expect(
      payload.keys.where(
        (key) => !scopeFields.contains(key) && !envelopeFields.contains(key),
      ),
      isEmpty,
    );
  });

  test('a comment another member writes reaches this member', () async {
    revision = 3;
    extraChanges.add({
      'entityType': 'comment',
      'entityId': 'comment-remote',
      'serverRevision': 3,
      'updatedAt': '2026-09-14T01:00:00Z',
      'data': {
        'id': 'comment-remote',
        'scopeId': 'scope',
        'taskId': 'task',
        'body': 'Remote comment',
        'mentions': <String>[],
        'createdBy': 'owner',
        'createdAt': '2026-09-14T01:00:00Z',
        'updatedAt': '2026-09-14T01:00:00Z',
      },
    });
    await engine.syncShared();
    final comments = await collaboration
        .watchEntities('scope', 'comment', taskId: 'task')
        .first;
    expect(comments.single['body'], 'Remote comment');
    expect(comments.single['createdBy'], 'owner');
    // The cursor now sits on the comment revision: a later pull must not drop it.
    await engine.syncShared();
    expect(
      await collaboration
          .watchEntities('scope', 'comment', taskId: 'task')
          .first,
      hasLength(1),
    );
  });

  test(
    'observers cannot be assigned and rejected selection leaves local state intact',
    () async {
      await expectLater(
        collaboration
            .setAssignees('task', {'reader'})
            .then((result) => result.getOrThrow()),
        throwsException,
      );
      expect(await db.select(db.syncCommands).get(), isEmpty);
      expect(
        (await (db.select(
          db.tasks,
        )..where((t) => t.id.equals('task'))).getSingle()).assigneeIdsJson,
        '["me"]',
      );
    },
  );
}

class _Account implements AccountClient {
  List<AccountSyncEntity> changes = [];
  @override
  String? get currentUserId => 'me';
  @override
  Future<AccountSyncPullResult> pullChanges({
    required String appId,
    required String deviceId,
    required int sinceRevision,
    int limit = 500,
  }) async =>
      AccountSyncPullResult(nextCursor: 2, hasMore: false, changes: changes);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
