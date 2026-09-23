import 'package:pomodoist/data/repositories/projects/project_repository_impl.dart';
import 'dart:convert';
import 'package:app_account/app_account.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'support/account_sync_engine.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/data/services/collaboration/collaboration_api.dart';
import 'package:pomodoist/data/repositories/collaboration/collaboration_repository.dart';
import 'package:pomodoist/data/repositories/collaboration/drift_collaboration_repository.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

void main() {
  late AppDatabase db;
  late DriftOutboxService queue;
  late _Account account;
  late CollaborationRepository repository;
  late String root;
  late String child;
  late String task;
  final shares = <Map<String, dynamic>>[];
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.ensureSeedData();
    queue = DriftOutboxService(db);
    final projects = DriftProjectRepository(db, queue);
    root = await projects
        .createProject('Root')
        .then((result) => result.getOrThrow());
    child = await projects
        .createProject('Child', parentId: root)
        .then((result) => result.getOrThrow());
    task = await DriftTaskRepository(db, queue)
        .createTask(CreateTaskInput(content: 'Task', projectId: child))
        .then((result) => result.getOrThrow());
    await db.delete(db.syncCommands).go();
    account = _Account();
    shares.clear();
    final engine = testSyncEngine(db: db, uuid: const Uuid(), account: account);
    repository = DriftCollaborationRepository(
      db: db,
      queue: queue,
      api: CollaborationApi((args) async {
        if (args['action'] == 'state') {
          return {'personalRevision': account.revision};
        }
        if (args['action'] == 'unshare') {
          account.unsharedRoot = root;
          account.unsharedChild = child;
          account.unsharedTask = task;
          return {'ok': true, 'rootProjectId': root};
        }
        expect(args['action'], 'share');
        shares.add({...args, 'serverRevision': account.revision});
        return {
          'scope': {
            'id': 'scope',
            'rootProjectId': args['rootProjectId'],
            'ownerId': 'me',
            'role': 'administrator',
          },
        };
      }),
      synchronize: () async {
        await engine.pushPending();
        await engine.pullLatest();
      },
    );
  });
  tearDown(() => db.close());

  test(
    'sharing drains more than one personal push batch before the atomic transfer',
    () async {
      await queue.enqueueBatch([
        for (var i = 0; i < 205; i++)
          SyncQueueCommand(
            type: 'project.update',
            clientId: child,
            payload: {'id': child, 'name': 'Version $i'},
          ),
      ]);
      await repository.share(root);
      expect(shares.single['serverRevision'], 205);
      expect(shares.single['expectedRevision'], 205);
      expect(await db.select(db.syncCommands).get(), isEmpty);
    },
  );

  for (final status in ['deferred', 'conflict', 'rejected']) {
    test(
      'sharing blocks $status descendant mutations before transfer',
      () async {
        await queue.enqueue(
          type: 'task.delete',
          clientId: task,
          payload: {'id': task},
          availableAt: status == 'deferred'
              ? DateTime.now().add(const Duration(days: 1))
              : null,
        );
        if (status != 'deferred') {
          await db
              .update(db.syncCommands)
              .write(SyncCommandsCompanion(status: Value(status)));
        }
        await expectLater(
          repository.share(root).then((result) => result.getOrThrow()),
          throwsA(
            isA<CollaborationException>().having(
              (e) => e.code,
              'code',
              'personal_sync_pending',
            ),
          ),
        );
        expect(shares, isEmpty);
        expect(await db.select(db.syncCommands).get(), hasLength(1));
      },
    );
  }

  test(
    'unrelated deferred personal task does not block a fully synchronized subtree',
    () async {
      final other = await DriftTaskRepository(db, queue)
          .createTask(CreateTaskInput(content: 'Other'))
          .then((result) => result.getOrThrow());
      await db.delete(db.syncCommands).go();
      await queue.enqueue(
        type: 'task.delete',
        clientId: other,
        payload: {'id': other},
        availableAt: DateTime.now().add(const Duration(days: 1)),
      );
      (await repository.share(root)).getOrThrow();
      expect(shares, hasLength(1));
      expect(await db.select(db.syncCommands).get(), hasLength(1));
    },
  );

  test(
    'unsharing hands the project back as personal instead of dropping it',
    () async {
      (await repository.share(root)).getOrThrow();
      await _localSharedState(db, root);

      (await repository.unshare('scope')).getOrThrow();

      final restored = await (db.select(
        db.projects,
      )..where((p) => p.id.equals(root))).getSingle();
      expect(restored.scopeId, null);
      expect(restored.isDeleted, isFalse);
      expect(await db.select(db.sharedScopes).get(), isEmpty);
    },
  );

  test(
    'unsharing restores the whole subtree, not just the root project',
    () async {
      (await repository.share(root)).getOrThrow();
      await _localSharedState(db, root);

      (await repository.unshare('scope')).getOrThrow();

      final projects = await (db.select(
        db.projects,
      )..where((p) => p.id.isIn([root, child]))).get();
      expect(
        {for (final row in projects) row.id: row.scopeId},
        {root: null, child: null},
      );
      // The child and its task come back in the same pull as the root, and the
      // subtree pass must keep both rather than take them with the scope.
      expect(
        (await (db.select(
          db.tasks,
        )..where((t) => t.id.equals(task))).getSingle()).scopeId,
        null,
      );
    },
  );

  test('owner deletes a shared root through the server scope delete', () async {
    (await repository.share(root)).getOrThrow();
    await _localSharedState(db, root);
    final actions = <String>[];
    final projects = DriftProjectRepository(
      db,
      queue,
      collaboration: CollaborationApi((args) async {
        actions.add(args['action'] as String);
        return {'ok': true};
      }),
    );

    (await projects.deleteProject(root)).getOrThrow();

    expect(actions, ['delete']);
    expect(
      (await (db.select(
        db.projects,
      )..where((p) => p.id.equals(root))).getSingle()).isDeleted,
      isTrue,
    );
  });
}

/// Leaves the database as a completed shared sync would: the project carries
/// the scope and the scope row is cached locally.
Future<void> _localSharedState(AppDatabase db, String root) async {
  await db
      .update(db.projects)
      .write(const ProjectsCompanion(scopeId: Value('scope')));
  await db
      .into(db.sharedScopes)
      .insertOnConflictUpdate(
        SharedScopesCompanion.insert(
          id: 'scope',
          dataJson: jsonEncode({
            'id': 'scope',
            'rootProjectId': root,
            'ownerId': 'me',
            'role': 'administrator',
          }),
        ),
      );
}

class _Account implements AccountClient {
  var revision = 0;
  String? serverName;

  /// Set when the server unshares a root: the subtree comes back as personal
  /// rows, so the next pull must carry all of it.
  String? unsharedRoot;
  String? unsharedChild;
  String? unsharedTask;
  @override
  String? get currentUserId => 'me';
  @override
  Future<AccountSyncPushResult> pushChanges({
    required String appId,
    required String deviceId,
    required List<AccountSyncOperation> operations,
  }) async {
    for (final op in operations) {
      revision++;
      if (op.payload['name'] is String) {
        serverName = op.payload['name'] as String;
      }
    }
    return AccountSyncPushResult(serverRevision: revision, applied: const []);
  }

  @override
  Future<AccountSyncPullResult> pullChanges({
    required String appId,
    required String deviceId,
    required int sinceRevision,
    int limit = 500,
  }) async {
    final root = unsharedRoot;
    final child = unsharedChild;
    final task = unsharedTask;
    if (root == null || child == null || task == null) {
      return AccountSyncPullResult(
        nextCursor: revision,
        hasMore: false,
        changes: const [],
      );
    }
    // `unshare` hands the subtree back as personal rows: none of them carries a
    // scopeId, while the local copies still do. That is exactly the state the
    // pull has to reconcile. A child is listed before its parent, so a pass that
    // resolves rows one at a time cannot know what else is coming back.
    return AccountSyncPullResult(
      nextCursor: revision,
      hasMore: false,
      changes: [
        for (final id in [child, task, root])
          AccountSyncEntity(
            entityType: id == task ? 'task' : 'project',
            entityId: id,
            serverRevision: revision,
            updatedAt: DateTime.now().toUtc(),
            data: {
              'id': id,
              'userId': 'me',
              if (id == task) 'projectId': child,
              if (id != task) 'name': id == root ? 'Root' : 'Child',
              if (id != task) 'viewStyle': 'list',
              if (id != task) 'isFavorite': false,
              if (id != task) 'isArchived': false,
              if (id != task && id == child) 'parentId': root,
              if (id == task) 'content': 'Task',
              if (id == task) 'isCompleted': false,
              'isDeleted': false,
              'orderKey': 'a',
              'createdAt': DateTime.utc(2026).toIso8601String(),
              'updatedAt': DateTime.now().toUtc().toIso8601String(),
            },
          ),
      ],
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
