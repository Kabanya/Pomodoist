import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:app_account/app_account.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/core/sync/account_sync_engine.dart';
import 'package:pomodoist/core/sync/sync_queue_repository.dart';
import 'package:pomodoist/features/collaboration/data/collaboration_api.dart';
import 'package:pomodoist/features/collaboration/data/collaboration_repository.dart';
import 'package:pomodoist/features/tasks/data/task_repository_impl.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';

void main() {
  late AppDatabase db;
  late AccountSyncEngine engine;
  late DriftSyncQueueRepository queue;
  late CollaborationRepository collaboration;
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
    queue = DriftSyncQueueRepository(db);
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
    engine = AccountSyncEngine(
      db: db,
      uuid: const Uuid(),
      account: _Account(),
      collaboration: api,
    );
    collaboration = CollaborationRepository(
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
      await DriftTaskRepository(
        db,
        queue,
      ).updateTask('task', const UpdateTaskPatch(content: 'My edit'));
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
      await DriftTaskRepository(
        db,
        queue,
      ).updateTask('task', const UpdateTaskPatch(content: 'Own draft'));
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

  test('conflicting text stays visible until explicit server choice', () async {
    await DriftTaskRepository(
      db,
      queue,
    ).updateTask('task', const UpdateTaskPatch(content: 'Local text'));
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
    await collaboration.resolveConflict(draft, keepLocal: false);
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
      await tasks.updateTask(
        'task',
        const UpdateTaskPatch(content: 'Local content'),
      );
      await tasks.updateTask(
        'task',
        const UpdateTaskPatch(
          description: 'Local description',
          updateDescription: true,
        ),
      );
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
      await tasks.updateTask('task', const UpdateTaskPatch(content: 'First'));
      await tasks.updateTask('task', const UpdateTaskPatch(content: 'Second'));
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
      await tasks.updateTask(
        'task',
        const UpdateTaskPatch(content: 'Local content'),
      );
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
      await tasks.updateTask(
        'task',
        const UpdateTaskPatch(content: 'Rejected edit'),
      );
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

  test(
    'observers cannot be assigned and rejected selection leaves local state intact',
    () async {
      await expectLater(
        collaboration.setAssignees('task', {'reader'}),
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
  @override
  String? get currentUserId => 'me';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
