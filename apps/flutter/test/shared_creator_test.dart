import 'package:app_account/app_account.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/core/sync/account_sync_engine.dart';

void main() {
  late AppDatabase db;
  final now = DateTime.utc(2026, 9, 14);
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.ensureSeedData();
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: 'legacy',
            userId: localUserId,
            content: 'Legacy',
            projectId: inboxProjectId,
            orderKey: 'a',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: 'authored',
            userId: localUserId,
            content: 'Authored',
            projectId: inboxProjectId,
            orderKey: 'b',
            createdAt: now,
            updatedAt: now,
            createdBy: const Value('original-author'),
          ),
        );
  });
  tearDown(() => db.close());

  Future<String?> creator(String id) async => (await (db.select(
    db.tasks,
  )..where((row) => row.id.equals(id))).getSingle()).createdBy;

  test(
    'startup gives legacy guest tasks a local creator placeholder',
    () async {
      await db.ensureSeedData();
      expect(await creator('legacy'), localUserId);
      expect(await creator('authored'), 'original-author');
    },
  );

  test(
    'startup backfills legacy tasks from the persisted account owner',
    () async {
      await db
          .into(db.syncState)
          .insert(
            SyncStateCompanion.insert(
              id: 'pomodoist-account-owner-v1',
              deviceId: 'device',
              cursor: const Value('me'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.ensureSeedData();
      expect(await creator('legacy'), 'me');
      expect(await creator('authored'), 'original-author');
    },
  );

  test(
    'claiming ownerless local tasks replaces only the guest creator placeholder',
    () async {
      await (db.update(db.tasks)..where((row) => row.id.equals('legacy')))
          .write(const TasksCompanion(createdBy: Value(localUserId)));
      await AccountSyncEngine(
        db: db,
        uuid: const Uuid(),
        account: _Account(),
      ).prepareLocalAccountData();
      expect(await creator('legacy'), 'me');
      expect(await creator('authored'), 'original-author');
    },
  );

  test(
    'personal pull fills an existing nullable creator without losing authoritative authors',
    () async {
      final account = _Account();
      account.changes = [
        AccountSyncEntity.fromJson({
          'entityType': 'task',
          'entityId': 'legacy',
          'serverRevision': 1,
          'updatedAt': now.toIso8601String(),
          'data': {
            'id': 'legacy',
            'createdBy': null,
            'updatedAt': now.millisecondsSinceEpoch,
            'content': 'Updated',
          },
        }),
        AccountSyncEntity.fromJson({
          'entityType': 'task',
          'entityId': 'authored',
          'serverRevision': 2,
          'updatedAt': now.toIso8601String(),
          'data': {
            'id': 'authored',
            'createdBy': null,
            'updatedAt': now.millisecondsSinceEpoch,
            'content': 'Updated',
          },
        }),
      ];
      await AccountSyncEngine(
        db: db,
        uuid: const Uuid(),
        account: account,
      ).pullLatest();
      expect(await creator('legacy'), 'me');
      expect(await creator('authored'), 'original-author');
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
