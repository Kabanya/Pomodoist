import 'package:app_account/app_account.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/core/sync/account_sync_engine.dart';
import 'package:pomodoist/core/sync/sync_queue_repository.dart';
import 'package:pomodoist/features/collaboration/data/collaboration_api.dart';
import 'package:pomodoist/features/collaboration/data/collaboration_repository.dart';
import 'package:pomodoist/features/collaboration/domain/collaboration_models.dart';
import 'package:pomodoist/features/tasks/data/task_repository_impl.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';

void main() {
  late AppDatabase db;
  late DriftSyncQueueRepository queue;
  late _Account account;
  late CollaborationRepository repository;
  late String root;
  late String child;
  late String task;
  final shares = <Map<String, dynamic>>[];
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.ensureSeedData();
    queue = DriftSyncQueueRepository(db);
    final projects = DriftProjectRepository(db, queue);
    root = await projects.createProject('Root');
    child = await projects.createProject('Child', parentId: root);
    task = await DriftTaskRepository(
      db,
      queue,
    ).createTask(CreateTaskInput(content: 'Task', projectId: child));
    await db.delete(db.syncCommands).go();
    account = _Account();
    shares.clear();
    final engine = AccountSyncEngine(
      db: db,
      uuid: const Uuid(),
      account: account,
      overviewLoader: () async => null,
    );
    repository = CollaborationRepository(
      db: db,
      queue: queue,
      api: CollaborationApi((args) async {
        expect(args['action'], 'share');
        shares.add({...args, 'serverRevision': account.revision});
        return {'scopeId': 'scope'};
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
          repository.share(root),
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
      final other = await DriftTaskRepository(
        db,
        queue,
      ).createTask(const CreateTaskInput(content: 'Other'));
      await db.delete(db.syncCommands).go();
      await queue.enqueue(
        type: 'task.delete',
        clientId: other,
        payload: {'id': other},
        availableAt: DateTime.now().add(const Duration(days: 1)),
      );
      await repository.share(root);
      expect(shares, hasLength(1));
      expect(await db.select(db.syncCommands).get(), hasLength(1));
    },
  );
}

class _Account implements AccountClient {
  var revision = 0;
  String? serverName;
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
      if (op.payload['name'] is String)
        serverName = op.payload['name'] as String;
    }
    return AccountSyncPushResult(serverRevision: revision, applied: const []);
  }

  @override
  Future<AccountSyncPullResult> pullChanges({
    required String appId,
    required String deviceId,
    required int sinceRevision,
    int limit = 500,
  }) async => AccountSyncPullResult(
    nextCursor: revision,
    hasMore: false,
    changes: const [],
  );
  @override
  Future<void> broadcastSyncHint({
    required String appId,
    required String deviceId,
  }) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
