import 'dart:async';
import 'dart:collection';

import 'package:app_account/app_account.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/core/sync/account_sync_engine.dart';
import 'package:pomodoist/core/sync/sync_queue_repository.dart';
import 'package:uuid/uuid.dart';

void main() {
  late bool previousMultipleDatabaseWarning;

  setUpAll(() {
    previousMultipleDatabaseWarning =
        driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        previousMultipleDatabaseWarning;
  });

  group('Focus account sync', () {
    late AppDatabase db;
    late DriftSyncQueueRepository queue;
    late _RecordingAccountClient account;
    late AccountSyncEngine engine;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.ensureSeedData();
      queue = DriftSyncQueueRepository(db);
      account = _RecordingAccountClient();
      engine = AccountSyncEngine(
        db: db,
        account: account,
        uuid: const Uuid(),
        localPaidEntitlementLoader: () async => true,
      );
    });

    tearDown(() => db.close());

    test('legacy active commands drain without reaching the server', () async {
      final now = DateTime.utc(2026, 7, 11, 9);
      await _insertRun(db, id: 'active-run', status: 'active', now: now);
      await _insertInterval(
        db,
        id: 'active-interval',
        runId: 'active-run',
        status: 'running',
        now: now,
      );
      await queue.enqueue(
        type: 'focus.run.start',
        clientId: 'active-run',
        payload: {'id': 'active-run'},
      );

      await engine.pushPending();

      expect(account.pushed, isEmpty);
      expect(await queue.watchPending().first, isEmpty);
    });

    test('terminal command uploads the complete focus session graph', () async {
      final now = DateTime.utc(2026, 7, 11, 9);
      await _insertRun(
        db,
        id: 'completed-run',
        status: 'completed',
        now: now,
        endedAt: now.add(const Duration(minutes: 30)),
      );
      await _insertInterval(
        db,
        id: 'work-interval',
        runId: 'completed-run',
        status: 'completed',
        now: now,
      );
      await _insertInterval(
        db,
        id: 'break-interval',
        runId: 'completed-run',
        status: 'skipped',
        now: now.add(const Duration(minutes: 25)),
        sequenceNumber: 2,
      );
      await db
          .into(db.focusEvents)
          .insert(
            FocusEventsCompanion.insert(
              id: 'run-event',
              runId: 'completed-run',
              type: 'runCompleted',
              occurredAt: now.add(const Duration(minutes: 30)),
              createdAt: now.add(const Duration(minutes: 30)),
            ),
          );
      await queue.enqueue(
        type: 'focus.run.complete',
        clientId: 'completed-run',
        payload: {'id': 'completed-run'},
      );

      await engine.pushPending();

      expect(account.pushed.map((operation) => operation.entityType), [
        'focus_run',
        'focus_interval',
        'focus_interval',
        'focus_event',
      ]);
      expect(account.pushed.map((operation) => operation.entityId), {
        'completed-run',
        'work-interval',
        'break-interval',
        'run-event',
      });
    });

    test(
      'pull ignores active focus state but keeps completed history',
      () async {
        final now = DateTime.utc(2026, 7, 11, 9);
        account.pullResults.add(
          AccountSyncPullResult(
            nextCursor: 4,
            hasMore: false,
            changes: [
              _runEntity(
                id: 'remote-active-run',
                status: 'active',
                revision: 1,
                now: now,
              ),
              _intervalEntity(
                id: 'remote-active-interval',
                runId: 'remote-active-run',
                status: 'running',
                revision: 2,
                now: now,
              ),
              _runEntity(
                id: 'remote-completed-run',
                status: 'completed',
                revision: 3,
                now: now,
                endedAt: now.add(const Duration(minutes: 30)),
              ),
              _intervalEntity(
                id: 'remote-completed-interval',
                runId: 'remote-completed-run',
                status: 'completed',
                revision: 4,
                now: now,
              ),
            ],
          ),
        );

        await engine.pullLatest();

        expect(
          await (db.select(db.focusRuns)
                ..where((row) => row.id.equals('remote-active-run')))
              .getSingleOrNull(),
          isNull,
        );
        expect(
          await (db.select(db.focusIntervals)
                ..where((row) => row.id.equals('remote-active-interval')))
              .getSingleOrNull(),
          isNull,
        );
        expect(
          await (db.select(db.focusRuns)
                ..where((row) => row.id.equals('remote-completed-run')))
              .getSingleOrNull(),
          isNotNull,
        );
        expect(
          await (db.select(db.focusIntervals)
                ..where((row) => row.id.equals('remote-completed-interval')))
              .getSingleOrNull(),
          isNotNull,
        );
      },
    );

    test('second device sees focus only after the run ends', () async {
      final now = DateTime.utc(2026, 7, 11, 9);
      await _insertRun(db, id: 'local-run', status: 'active', now: now);
      await _insertInterval(
        db,
        id: 'local-interval',
        runId: 'local-run',
        status: 'running',
        now: now,
      );

      final secondDb = AppDatabase(NativeDatabase.memory());
      addTearDown(secondDb.close);
      await secondDb.ensureSeedData();
      final secondEngine = AccountSyncEngine(
        db: secondDb,
        account: account,
        uuid: const Uuid(),
        localPaidEntitlementLoader: () async => true,
      );

      await engine.pushPending();
      await secondEngine.pullLatest();

      expect(await secondDb.select(secondDb.focusRuns).get(), isEmpty);
      expect(await secondDb.select(secondDb.focusIntervals).get(), isEmpty);

      final endedAt = now.add(const Duration(minutes: 25));
      await (db.update(
        db.focusRuns,
      )..where((row) => row.id.equals('local-run'))).write(
        FocusRunsCompanion(
          status: const Value('completed'),
          endedAt: Value(endedAt),
          updatedAt: Value(endedAt),
        ),
      );
      await (db.update(
        db.focusIntervals,
      )..where((row) => row.id.equals('local-interval'))).write(
        FocusIntervalsCompanion(
          status: const Value('completed'),
          completedAt: Value(endedAt),
          updatedAt: Value(endedAt),
        ),
      );
      await queue.enqueue(
        type: 'focus.run.complete',
        clientId: 'local-run',
        payload: {'id': 'local-run'},
      );

      await engine.pushPending();
      await secondEngine.pullLatest();

      expect(
        (await secondDb.select(secondDb.focusRuns).get()).single.status,
        'completed',
      );
      expect(
        (await secondDb.select(secondDb.focusIntervals).get()).single.status,
        'completed',
      );
    });

    test('push timeout preserves pending commands for retry', () async {
      final now = DateTime.utc(2026, 7, 11, 9);
      await _insertRun(
        db,
        id: 'timeout-run',
        status: 'completed',
        now: now,
        endedAt: now,
      );
      await _insertInterval(
        db,
        id: 'timeout-interval',
        runId: 'timeout-run',
        status: 'completed',
        now: now,
      );
      await queue.enqueue(
        type: 'focus.run.complete',
        clientId: 'timeout-run',
        payload: {'id': 'timeout-run'},
      );
      account.pendingPush = Completer<void>().future;
      engine = AccountSyncEngine(
        db: db,
        account: account,
        uuid: const Uuid(),
        localPaidEntitlementLoader: () async => true,
        requestTimeout: const Duration(milliseconds: 10),
      );

      await expectLater(engine.pushPending(), throwsA(isA<TimeoutException>()));
      final pending = await queue.watchPending().first;
      expect(pending, isNotEmpty);
      expect(pending.single.attempts, 1);

      account.pendingPush = null;
      await engine.pushPending();
      expect(await queue.watchPending().first, isEmpty);
    });

    test('pull timeout preserves cursor and permits retry', () async {
      account.pendingPull = Completer<AccountSyncPullResult>().future;
      engine = AccountSyncEngine(
        db: db,
        account: account,
        uuid: const Uuid(),
        localPaidEntitlementLoader: () async => true,
        requestTimeout: const Duration(milliseconds: 10),
      );

      await expectLater(engine.pullLatest(), throwsA(isA<TimeoutException>()));
      final timedOutState = await (db.select(
        db.syncState,
      )..where((row) => row.id.equals('pomodoist'))).getSingle();
      expect(timedOutState.cursor, isNull);

      account.pendingPull = null;
      account.pullResults.add(
        const AccountSyncPullResult(nextCursor: 7, hasMore: false, changes: []),
      );
      await engine.pullLatest();
      final retriedState = await (db.select(
        db.syncState,
      )..where((row) => row.id.equals('pomodoist'))).getSingle();
      expect(retriedState.cursor, '7');
    });

    test(
      'large focus graph uses a separate request per 100 operations',
      () async {
        final now = DateTime.utc(2026, 7, 11, 9);
        await _insertRun(
          db,
          id: 'large-run',
          status: 'completed',
          now: now,
          endedAt: now,
        );
        await _insertInterval(
          db,
          id: 'large-interval',
          runId: 'large-run',
          status: 'completed',
          now: now,
        );
        for (var index = 0; index < 101; index += 1) {
          await db
              .into(db.focusEvents)
              .insert(
                FocusEventsCompanion.insert(
                  id: 'large-event-$index',
                  runId: 'large-run',
                  type: 'distraction',
                  occurredAt: now,
                  createdAt: now,
                ),
              );
        }
        await queue.enqueue(
          type: 'focus.run.complete',
          clientId: 'large-run',
          payload: {'id': 'large-run'},
        );

        await engine.pushPending();

        expect(account.pushBatches.map((batch) => batch.length), [100, 3]);
      },
    );

    test('realtime hint failure does not fail a completed push', () async {
      final now = DateTime.utc(2026, 7, 11, 9);
      await _insertRun(
        db,
        id: 'hint-run',
        status: 'completed',
        now: now,
        endedAt: now,
      );
      await _insertInterval(
        db,
        id: 'hint-interval',
        runId: 'hint-run',
        status: 'completed',
        now: now,
      );
      await queue.enqueue(
        type: 'focus.run.complete',
        clientId: 'hint-run',
        payload: {'id': 'hint-run'},
      );
      account.hintThrows = true;

      await engine.pushPending();

      expect(await queue.watchPending().first, isEmpty);
    });
  });
}

Future<void> _insertRun(
  AppDatabase db, {
  required String id,
  required String status,
  required DateTime now,
  DateTime? endedAt,
}) {
  return db
      .into(db.focusRuns)
      .insert(
        FocusRunsCompanion.insert(
          id: id,
          userId: localUserId,
          presetId: defaultPresetId,
          status: status,
          startedAt: now,
          endedAt: Value(endedAt),
          targetWorkIntervals: 1,
          completedWorkIntervals: const Value(1),
          createdAt: now,
          updatedAt: endedAt ?? now,
        ),
      );
}

Future<void> _insertInterval(
  AppDatabase db, {
  required String id,
  required String runId,
  required String status,
  required DateTime now,
  int sequenceNumber = 1,
}) {
  return db
      .into(db.focusIntervals)
      .insert(
        FocusIntervalsCompanion.insert(
          id: id,
          runId: runId,
          type: sequenceNumber == 1 ? 'work' : 'shortBreak',
          status: status,
          plannedSeconds: sequenceNumber == 1 ? 25 * 60 : 5 * 60,
          startedAt: now,
          completedAt: Value(status == 'completed' ? now : null),
          stoppedAt: Value(status == 'skipped' ? now : null),
          sequenceNumber: sequenceNumber,
          createdAt: now,
          updatedAt: now,
        ),
      );
}

AccountSyncEntity _runEntity({
  required String id,
  required String status,
  required int revision,
  required DateTime now,
  DateTime? endedAt,
}) {
  return AccountSyncEntity(
    entityType: 'focus_run',
    entityId: id,
    serverRevision: revision,
    data: {
      'id': id,
      'userId': localUserId,
      'presetId': defaultPresetId,
      'status': status,
      'startedAt': now.toIso8601String(),
      'endedAt': endedAt?.toIso8601String(),
      'targetWorkIntervals': 1,
      'completedWorkIntervals': status == 'completed' ? 1 : 0,
      'createdAt': now.toIso8601String(),
      'updatedAt': (endedAt ?? now).toIso8601String(),
      'isDeleted': false,
    },
  );
}

AccountSyncEntity _intervalEntity({
  required String id,
  required String runId,
  required String status,
  required int revision,
  required DateTime now,
}) {
  return AccountSyncEntity(
    entityType: 'focus_interval',
    entityId: id,
    serverRevision: revision,
    data: {
      'id': id,
      'runId': runId,
      'type': 'work',
      'status': status,
      'plannedSeconds': 25 * 60,
      'startedAt': now.toIso8601String(),
      'pausedTotalSeconds': 0,
      'completedAt': status == 'completed' ? now.toIso8601String() : null,
      'sequenceNumber': 1,
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'isDeleted': false,
    },
  );
}

class _RecordingAccountClient implements AccountClient {
  final pushed = <AccountSyncOperation>[];
  final pushBatches = <List<AccountSyncOperation>>[];
  final pullResults = Queue<AccountSyncPullResult>();
  final serverChanges = <AccountSyncEntity>[];
  Future<void>? pendingPush;
  Future<AccountSyncPullResult>? pendingPull;
  bool hintThrows = false;
  var _revision = 0;

  @override
  Future<AccountSyncPushResult> pushChanges({
    required String appId,
    required String deviceId,
    required List<AccountSyncOperation> operations,
  }) async {
    await pendingPush;
    pushBatches.add(List.of(operations));
    pushed.addAll(operations);
    for (final operation in operations) {
      _revision += 1;
      serverChanges.add(
        AccountSyncEntity(
          entityType: operation.entityType,
          entityId: operation.entityId,
          serverRevision: _revision,
          data: operation.payload,
          deletedAt: operation.operation == 'delete'
              ? operation.clientUpdatedAt
              : null,
          updatedAt: operation.clientUpdatedAt,
        ),
      );
    }
    return AccountSyncPushResult(serverRevision: _revision, applied: const []);
  }

  @override
  Future<AccountSyncPullResult> pullChanges({
    required String appId,
    required String deviceId,
    required int sinceRevision,
    int limit = 500,
  }) async {
    final pending = pendingPull;
    if (pending != null) {
      return pending;
    }
    if (pullResults.isNotEmpty) {
      return pullResults.removeFirst();
    }
    final changes = serverChanges
        .where((change) => change.serverRevision > sinceRevision)
        .toList(growable: false);
    return AccountSyncPullResult(
      nextCursor: _revision,
      hasMore: false,
      changes: changes,
    );
  }

  @override
  Future<void> broadcastSyncHint({
    required String appId,
    required String deviceId,
  }) async {
    if (hintThrows) {
      throw StateError('hint failed');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
