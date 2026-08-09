import 'package:app_account/app_account.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/account_providers.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/core/sync/account_sync_engine.dart';
import 'package:uuid/uuid.dart';

void main() {
  test(
    'switching accounts never imports the previous account snapshot',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();
      final now = DateTime.utc(2026, 7, 12, 12);
      await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              id: 'ethan-private-task',
              userId: localUserId,
              content: 'Ethan private task',
              projectId: inboxProjectId,
              orderKey: 'private',
              createdAt: now,
              updatedAt: now,
            ),
          );

      final ethan = _RecordingAccountClient(
        userId: 'ethan-user-id',
        nextCursor: 10,
      );
      await _engine(db, ethan).syncNow();
      expect(
        ethan.pushed.any(
          (operation) => operation.entityId == 'ethan-private-task',
        ),
        isTrue,
      );

      final other = _RecordingAccountClient(
        userId: 'other-user-id',
        nextCursor: 0,
      );
      await _engine(db, other).syncNow();

      expect(
        other.pushed.any(
          (operation) => operation.entityId == 'ethan-private-task',
        ),
        isFalse,
      );
      expect(
        await (db.select(
          db.tasks,
        )..where((row) => row.id.equals('ethan-private-task'))).get(),
        isEmpty,
      );
    },
  );

  test('the boundary upgrade clears previously synced unowned data', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();
    final now = DateTime.utc(2026, 7, 12, 12);
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: 'legacy-private-task',
            userId: localUserId,
            content: 'Legacy private task',
            projectId: inboxProjectId,
            orderKey: 'legacy-private',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.syncState)
        .insert(
          SyncStateCompanion.insert(
            id: 'pomodoist-import',
            deviceId: 'legacy-device',
            cursor: const Value('done-v3'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.syncState)
        .insert(
          SyncStateCompanion.insert(
            id: 'pomodoist',
            deviceId: 'legacy-device',
            cursor: const Value('10'),
            createdAt: now,
            updatedAt: now,
          ),
        );

    final account = _RecordingAccountClient(
      userId: 'first-user-after-upgrade',
      nextCursor: 0,
    );
    await _engine(db, account).syncNow();

    expect(
      account.pushed.any(
        (operation) => operation.entityId == 'legacy-private-task',
      ),
      isFalse,
    );
    expect(
      await (db.select(
        db.tasks,
      )..where((row) => row.id.equals('legacy-private-task'))).get(),
      isEmpty,
    );
  });

  test(
    'account startup prepares local data without requiring network',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();
      final account = _RecordingAccountClient(
        userId: 'offline-user-id',
        nextCursor: 0,
        throwOnPull: true,
      );
      final container = ProviderContainer(
        overrides: [
          accountSyncEngineProvider.overrideWithValue(_engine(db, account)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(accountSyncStartupProvider.future);

      expect(account.pullCalls, 0);
    },
  );
}

AccountSyncEngine _engine(AppDatabase db, _RecordingAccountClient account) {
  return AccountSyncEngine(
    db: db,
    account: account,
    uuid: const Uuid(),
    localPaidEntitlementLoader: () async => true,
  );
}

class _RecordingAccountClient implements AccountClient {
  _RecordingAccountClient({
    required this.userId,
    required this.nextCursor,
    this.throwOnPull = false,
  });

  final String userId;
  final int nextCursor;
  final bool throwOnPull;
  final List<AccountSyncOperation> pushed = [];
  var pullCalls = 0;

  @override
  String? get currentUserId => userId;

  @override
  Future<AccountSyncPushResult> pushChanges({
    required String appId,
    required String deviceId,
    required List<AccountSyncOperation> operations,
  }) async {
    pushed.addAll(operations);
    return AccountSyncPushResult(serverRevision: nextCursor, applied: const []);
  }

  @override
  Future<AccountSyncPullResult> pullChanges({
    required String appId,
    required String deviceId,
    required int sinceRevision,
    int limit = 500,
  }) async {
    pullCalls += 1;
    if (throwOnPull) {
      throw StateError('network unavailable');
    }
    return AccountSyncPullResult(
      nextCursor: nextCursor,
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
