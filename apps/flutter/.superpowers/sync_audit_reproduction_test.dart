import 'package:app_account/app_account.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import '../test/support/account_sync_engine.dart';

// Audit reproductions document current failure modes; no live database is used.
void main() {
  late AppDatabase db;
  late DriftOutboxService queue;
  late _Account account;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.ensureSeedData();
    queue = DriftOutboxService(db);
    account = _Account();
  });
  tearDown(() => db.close());

  test(
    'failed personal push prevents the later pull and preserves queue',
    () async {
      final engine = testSyncEngine(
        db: db,
        account: account,
        uuid: const Uuid(),
      );
      await engine.syncNow();
      await DriftTaskRepository(
        db,
        queue,
      ).createTask(CreateTaskInput(content: 'Offline task'));
      final before = await queue.watchPending().first;
      expect(before, isNotEmpty);
      account.pullCalls = 0;
      account.failPush = true;
      await expectLater(engine.syncNow(), throwsA(isA<PostgrestException>()));
      expect(account.pullCalls, 0);
      expect((await queue.watchPending().first).length, before.length);
    },
  );

  test(
    'guest reset erases pending changes belonging to the signed-out owner',
    () async {
      final engine = testSyncEngine(
        db: db,
        account: account,
        uuid: const Uuid(),
      );
      await engine.prepareLocalAccountData();
      final id = (await DriftTaskRepository(
        db,
        queue,
      ).createTask(CreateTaskInput(content: 'Never uploaded'))).getOrThrow();
      expect(await queue.watchPending().first, isNotEmpty);
      await SyncOwnershipCoordinator.prepareGuestLocalData(
        db: db,
        uuid: const Uuid(),
      );
      expect(await queue.watchPending().first, isEmpty);
      expect(
        await (db.select(
          db.tasks,
        )..where((r) => r.id.equals(id))).getSingleOrNull(),
        isNull,
      );
    },
  );

  test(
    'incomplete remote task is skipped while the pull cursor advances',
    () async {
      account.pullResult = const AccountSyncPullResult(
        nextCursor: 88,
        hasMore: false,
        changes: [
          AccountSyncEntity(
            entityType: 'task',
            entityId: 'incomplete',
            serverRevision: 88,
            data: {'id': 'incomplete', 'dueJson': null},
          ),
        ],
      );
      final engine = testSyncEngine(
        db: db,
        account: account,
        uuid: const Uuid(),
      );
      await engine.pullLatest();
      expect(
        await (db.select(
          db.tasks,
        )..where((r) => r.id.equals('incomplete'))).getSingleOrNull(),
        isNull,
      );
      expect(
        (await (db.select(
          db.syncState,
        )..where((r) => r.id.equals('pomodoist'))).getSingle()).cursor,
        '88',
      );
    },
  );
}

class _Account implements AccountClient {
  bool failPush = false;
  int pullCalls = 0;
  AccountSyncPullResult pullResult = const AccountSyncPullResult(
    nextCursor: 0,
    hasMore: false,
    changes: [],
  );
  @override
  String get currentUserId => 'audit-account';
  @override
  AccountSession? get currentSession => null;
  @override
  Future<AccountSyncPushResult> pushChanges({
    required String appId,
    required String deviceId,
    required List<AccountSyncOperation> operations,
  }) async {
    if (failPush) {
      throw const PostgrestException(
        message: 'Invalid habit field',
        code: '22023',
      );
    }
    return const AccountSyncPushResult(serverRevision: 0, applied: []);
  }

  @override
  Future<AccountSyncPullResult> pullChanges({
    required String appId,
    required String deviceId,
    required int sinceRevision,
    int limit = 500,
  }) async {
    pullCalls++;
    return pullResult;
  }

  @override
  Future<void> broadcastSyncHint({
    required String appId,
    required String deviceId,
  }) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
