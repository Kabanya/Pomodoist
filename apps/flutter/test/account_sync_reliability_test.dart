import 'dart:async';
import 'dart:convert';
import 'package:app_account/app_account.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'support/account_sync_engine.dart';

void main() {
  late AppDatabase db;
  late _Account account;
  late AccountSyncEngine engine;
  late DriftOutboxService queue;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.ensureSeedData();
    account = _Account();
    queue = DriftOutboxService(db);
    engine = testSyncEngine(db: db, account: account, uuid: const Uuid());
    await engine.syncNow();
    account.pushed.clear();
    account.pullCalls = 0;
  });
  tearDown(() => db.close());
  test(
    'bounded legacy scan resumes without moving the primary cursor',
    () async {
      account.paged = true;
      await engine.requestRecoveryScan();
      final before = (await (db.select(
        db.syncState,
      )..where((r) => r.id.equals('pomodoist'))).getSingle()).cursor;
      await engine.recoverUnreadable();
      expect(account.pullCalls, 4);
      expect(
        (await (db.select(
              db.syncState,
            )..where((r) => r.id.equals('pomodoist-repair-v1'))).getSingle())
            .cursor,
        '400',
      );
      await engine.recoverUnreadable();
      expect(account.pullCalls, 5);
      expect(
        (await (db.select(
              db.syncState,
            )..where((r) => r.id.equals('pomodoist-repair-v1'))).getSingle())
            .cursor,
        'done:500',
      );
      expect(
        (await (db.select(
          db.syncState,
        )..where((r) => r.id.equals('pomodoist'))).getSingle()).cursor,
        before,
      );
      expect((await watchSyncQueueStatus(db).first).repair, 5);
    },
  );

  test(
    'initial snapshot preserves dependency order ahead of queued edits',
    () async {
      for (var n = 0; n < 12; n++) {
        await DriftTaskRepository(
          db,
          queue,
        ).createTask(CreateTaskInput(content: 'Import $n'));
      }
      await (db.delete(
        db.syncState,
      )..where((r) => r.id.equals('pomodoist-import'))).go();
      await engine.importLocalSnapshotIfNeeded(push: false);
      final rows =
          await (db.select(db.syncCommands)..orderBy([
                (r) => OrderingTerm.asc(r.createdAt),
                (r) => OrderingTerm.asc(r.id),
              ]))
              .get();
      final snapshots = rows.where((r) => r.type == 'sync.snapshot').toList();
      expect(
        rows.take(snapshots.length).every((r) => r.type == 'sync.snapshot'),
        isTrue,
      );
      final types = snapshots
          .map(
            (r) => (jsonDecode(r.payloadJson)['_syncOperationsV1'] as List)
                .single['entityType'],
          )
          .toList();
      expect(types.lastIndexOf('project'), lessThan(types.indexOf('task')));
    },
  );

  test(
    'invalid command is retained while independent commands and pull progress',
    () async {
      final tasks = DriftTaskRepository(db, queue);
      await tasks.createTask(CreateTaskInput(content: 'First'));
      await queue.enqueue(
        type: 'habit.upsert',
        clientId: 'bad',
        payload: {'id': 'bad'},
      );
      await tasks.createTask(CreateTaskInput(content: 'Last'));
      account.rejectBad = true;
      await engine.syncNow();
      expect(account.pullCalls, greaterThan(0));
      expect(
        account.pushed
            .where((o) => o.entityType == 'task')
            .map((o) => o.payload['content']),
        containsAll(['First', 'Last']),
      );
      final bad = await (db.select(
        db.syncCommands,
      )..where((r) => r.clientId.equals('bad'))).getSingle();
      expect(bad.status, 'rejected');
      expect(jsonDecode(bad.payloadJson)['id'], 'bad');
    },
  );

  test(
    'lost response preserves identical replay even after live row changes',
    () async {
      final id = (await DriftTaskRepository(
        db,
        queue,
      ).createTask(CreateTaskInput(content: 'Original'))).getOrThrow();
      account.failOnce = true;
      await expectLater(engine.syncNow(), throwsA(anything));
      expect(account.pullCalls, greaterThan(0));
      final original = account.attempts.last
          .where((o) => o['entityType'] == 'task')
          .single;
      await (db.update(db.tasks)..where((r) => r.id.equals(id))).write(
        const TasksCompanion(content: Value('Changed by pull')),
      );
      await engine.syncNow();
      final replay = account.attempts
          .lastWhere((batch) => batch.any((o) => o['opId'] == original['opId']))
          .singleWhere((o) => o['opId'] == original['opId']);
      expect(replay, original);
    },
  );

  test(
    'unknown focus command is retained instead of acknowledged as a no-op',
    () async {
      await queue.enqueue(
        type: 'focus.run.unknown',
        clientId: 'run',
        payload: {},
      );
      await engine.syncNow();
      expect((await db.select(db.syncCommands).getSingle()).status, 'rejected');
    },
  );

  test(
    'unknown task command is not acknowledged as an ordinary upsert',
    () async {
      await queue.enqueue(
        type: 'task.unknown',
        clientId: 'unknown',
        payload: {'content': 'Retain me'},
      );
      await engine.syncNow();
      expect((await db.select(db.syncCommands).getSingle()).status, 'rejected');
    },
  );

  test('ordinary edit replaces rejected create with complete intent', () async {
    final tasks = DriftTaskRepository(db, queue);
    final id = (await tasks.createTask(
      CreateTaskInput(content: 'Original'),
    )).getOrThrow();
    account.rejectId = id;
    await engine.syncNow();
    final old =
        await (db.select(db.syncCommands)..where(
              (r) => r.clientId.equals(id) & r.status.equals('rejected'),
            ))
            .getSingle();
    await (db.update(db.tasks)..where((r) => r.id.equals(id))).write(
      const TasksCompanion(content: Value('Corrected')),
    );
    await queue.enqueue(
      type: 'task.update',
      clientId: id,
      payload: {'content': 'Corrected'},
    );
    account.rejectId = null;
    account.pushed.clear();
    await engine.syncNow();
    final repair = account.pushed.singleWhere(
      (o) => o.entityId == id && o.entityType == 'task',
    );
    expect(repair.payload['content'], 'Corrected');
    expect(repair.payload['projectId'], inboxProjectId);
    expect(repair.payload['createdAt'], isNotNull);
    expect(repair.opId, isNot(old.uuid));
    expect(
      (await (db.select(
        db.syncCommands,
      )..where((r) => r.id.equals(old.id))).getSingle()).status,
      'superseded',
    );
  });

  test(
    'more than 100 blocked dependents do not hide an independent task',
    () async {
      await queue.enqueue(
        type: 'habit.upsert',
        clientId: 'bad',
        payload: {'id': 'bad'},
      );
      account.rejectBad = true;
      await engine.syncNow();
      for (var n = 0; n < 105; n++) {
        await queue.enqueue(
          type: 'habit_check_in.create',
          clientId: 'check-$n',
          payload: {'id': 'check-$n', 'habitId': 'bad'},
        );
      }
      await DriftTaskRepository(
        db,
        queue,
      ).createTask(CreateTaskInput(content: 'Healthy'));
      await engine.syncNow();
      expect(
        account.pushed.any((o) => o.payload['content'] == 'Healthy'),
        isTrue,
      );
      expect(
        (await db.select(db.syncCommands).get())
            .where((r) => r.status == 'pending')
            .length,
        105,
      );
    },
  );

  test(
    'pending local task survives incoming tombstone and cursor advances',
    () async {
      final id = (await DriftTaskRepository(
        db,
        queue,
      ).createTask(CreateTaskInput(content: 'Offline'))).getOrThrow();
      account.changes = [
        AccountSyncEntity(
          entityType: 'task',
          entityId: id,
          serverRevision: 88,
          data: const {},
          deletedAt: DateTime.utc(2026),
        ),
      ];
      await engine.pullLatest();
      expect(
        (await (db.select(
          db.tasks,
        )..where((r) => r.id.equals(id))).getSingle()).isDeleted,
        isFalse,
      );
      expect(
        (await (db.select(db.sharedEntities)
                  ..where((r) => r.entityType.equals('sync_incoming:task')))
                .getSingle())
            .entityId,
        id,
      );
    },
  );

  test('cursor failure rolls back retained malformed row', () async {
    account.changes = const [
      AccountSyncEntity(
        entityType: 'task',
        entityId: 'partial',
        serverRevision: 88,
        data: {'id': 'partial'},
      ),
    ];
    await db.customStatement(
      "CREATE TRIGGER fail_cursor BEFORE UPDATE ON sync_state WHEN NEW.id = 'pomodoist' BEGIN SELECT RAISE(ABORT, 'disk full'); END",
    );
    await expectLater(engine.pullLatest(), throwsA(anything));
    expect(
      await (db.select(
        db.sharedEntities,
      )..where((r) => r.entityId.equals('partial'))).get(),
      isEmpty,
    );
    expect(
      (await (db.select(
        db.syncState,
      )..where((r) => r.id.equals('pomodoist'))).getSingle()).cursor,
      isNot('88'),
    );
  });

  test(
    'repair scan recovers skipped row from same-owner source with stable IDs',
    () async {
      final id = (await DriftTaskRepository(
        db,
        queue,
      ).createTask(CreateTaskInput(content: 'Verified source'))).getOrThrow();
      await engine.syncNow();
      account.changes = [
        AccountSyncEntity(
          entityType: 'task',
          entityId: id,
          serverRevision: 88,
          data: {'id': id, 'priority': 4, 'content': null},
        ),
      ];
      await engine.requestRecoveryScan();
      await engine.recoverUnreadable();
      final repair = await db.select(db.syncCommands).getSingle();
      final op =
          (jsonDecode(repair.payloadJson)['_syncOperationsV1'] as List).single;
      expect(op['payload']['content'], 'Verified source');
      expect(op['payload']['priority'], 4);
      await engine.requestRecoveryScan();
      await engine.recoverUnreadable();
      expect((await db.select(db.syncCommands).getSingle()).uuid, repair.uuid);
    },
  );

  test(
    'source-less legacy row remains visible without guessing content',
    () async {
      account.changes = const [
        AccountSyncEntity(
          entityType: 'task',
          entityId: 'missing',
          serverRevision: 88,
          data: {'id': 'missing'},
        ),
      ];
      await engine.requestRecoveryScan();
      await engine.recoverUnreadable();
      expect(await db.select(db.syncCommands).get(), isEmpty);
      expect(
        (await (db.select(
          db.sharedEntities,
        )..where((r) => r.entityId.equals('missing'))).getSingle()).isDeleted,
        isFalse,
      );
    },
  );

  test(
    'incomplete remote task is retained durably with committed cursor',
    () async {
      account.changes = const [
        AccountSyncEntity(
          entityType: 'task',
          entityId: 'partial',
          serverRevision: 88,
          data: {'id': 'partial', 'dueJson': null},
        ),
      ];
      await engine.pullLatest();
      final marker = await (db.select(
        db.sharedEntities,
      )..where((r) => r.entityType.equals('sync_repair:task'))).getSingle();
      expect(marker.entityId, 'partial');
      expect(marker.serverRevision, 88);
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
  bool paged = false;
  bool rejectBad = false;
  String? rejectId;
  bool failOnce = false;
  int pullCalls = 0;
  final pushed = <AccountSyncOperation>[];
  final attempts = <List<Map<String, Object?>>>[];
  List<AccountSyncEntity> changes = [];
  @override
  String get currentUserId => 'owner';
  @override
  AccountSession? get currentSession => null;
  @override
  Future<AccountSyncPushResult> pushChanges({
    required String appId,
    required String deviceId,
    required List<AccountSyncOperation> operations,
  }) async {
    attempts.add(operations.map((o) => o.toJson()).toList());
    if (operations.any((o) => o.entityId == rejectId) ||
        rejectBad && operations.any((o) => o.entityId == 'bad')) {
      throw const PostgrestException(
        message: 'Invalid habit field',
        code: '22023',
      );
    }
    pushed.addAll(operations);
    if (failOnce) {
      failOnce = false;
      throw TimeoutException('Response lost');
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
    if (paged) {
      final next = sinceRevision + 100;
      return AccountSyncPullResult(
        nextCursor: next,
        hasMore: next < 500,
        changes: [
          AccountSyncEntity(
            entityType: 'task',
            entityId: 'legacy-$next',
            serverRevision: next,
            data: const {},
          ),
        ],
      );
    }
    return AccountSyncPullResult(
      nextCursor: changes.isEmpty ? sinceRevision : 88,
      hasMore: false,
      changes: changes,
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
