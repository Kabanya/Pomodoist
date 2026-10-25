import 'dart:convert';
import 'dart:async';
import 'package:app_account/app_account.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:pomodoist/data/services/local/account_recovery_store.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'support/account_sync_engine.dart';

void main() {
  late AppDatabase db;
  late _Account account;
  late AccountSyncEngine engine;
  final old = DateTime.utc(2026, 10, 1);
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.ensureSeedData();
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: 'legacy',
            userId: localUserId,
            content: 'Archived task',
            projectId: inboxProjectId,
            orderKey: '1',
            createdAt: old,
            updatedAt: old,
          ),
        );
    await db
        .into(db.syncCommands)
        .insert(
          SyncCommandsCompanion.insert(
            id: 'old-command',
            uuid: 'original-operation',
            type: 'task.update',
            clientId: const Value('legacy'),
            payloadJson: jsonEncode({'content': 'Unsent patch'}),
            createdAt: old,
            updatedAt: old.add(const Duration(minutes: 1)),
          ),
        );
    for (final terminal in [false, true]) {
      final id = terminal ? 'finished' : 'running';
      await db
          .into(db.focusRuns)
          .insert(
            FocusRunsCompanion.insert(
              id: id,
              userId: localUserId,
              presetId: 'preset',
              status: terminal ? 'completed' : 'active',
              startedAt: old,
              endedAt: Value(
                terminal ? old.add(const Duration(minutes: 25)) : null,
              ),
              targetWorkIntervals: 1,
              createdAt: old,
              updatedAt: old,
            ),
          );
      await db
          .into(db.focusIntervals)
          .insert(
            FocusIntervalsCompanion.insert(
              id: '$id-interval',
              runId: id,
              type: 'work',
              status: terminal ? 'completed' : 'running',
              plannedSeconds: 1500,
              startedAt: old,
              completedAt: Value(
                terminal ? old.add(const Duration(minutes: 25)) : null,
              ),
              sequenceNumber: 1,
              createdAt: old,
              updatedAt: old,
            ),
          );
      await db
          .into(db.focusEvents)
          .insert(
            FocusEventsCompanion.insert(
              id: '$id-event',
              runId: id,
              type: terminal ? 'runCompleted' : 'runStarted',
              occurredAt: old,
              createdAt: old,
            ),
          );
    }
    await db
        .into(db.habits)
        .insert(
          HabitsCompanion.insert(
            id: 'ac115000-0000-4000-8000-000000000001',
            userId: localUserId,
            title: 'Read',
            scheduleHistoryJson:
                '[{"effectiveFrom":"2026-10-01","startDate":"2026-10-01","weekdays":[1,2,3,4,5,6,7],"targetPerDay":1}]',
            createdAt: old,
            updatedAt: old,
          ),
        );
    await db
        .into(db.habitCheckIns)
        .insert(
          HabitCheckInsCompanion.insert(
            id: 'ac115000-0000-4000-8000-000000000002',
            userId: localUserId,
            habitId: 'ac115000-0000-4000-8000-000000000001',
            day: '2026-10-01',
            createdAt: old,
            updatedAt: old,
          ),
        );
    await db.transaction(
      () => AccountRecoveryStore(db).archiveInTransaction('legacy-unowned'),
    );
    await db.resetAccountData();
    account = _Account();
    engine = testSyncEngine(db: db, account: account, uuid: const Uuid());
    await engine.syncNow();
    account.pushed.clear();
  });
  tearDown(() => db.close());

  Future<Map<String, dynamic>> payload() async =>
      jsonDecode(
            (await db.select(db.accountRecoverySnapshots).getSingle())
                .payloadJson,
          )
          as Map<String, dynamic>;
  Future<void> editArchive(
    void Function(Map<String, dynamic>) edit, {
    int schema = 14,
  }) async {
    final data = await payload();
    edit(data);
    await db
        .update(db.accountRecoverySnapshots)
        .write(
          AccountRecoverySnapshotsCompanion(
            schemaVersion: Value(schema),
            payloadJson: Value(jsonEncode(data)),
          ),
        );
  }

  List<Map<String, dynamic>> queued(List<SyncCommandRow> rows) => rows
      .expand(
        (row) => (jsonDecode(row.payloadJson)['_syncOperationsV1'] as List)
            .cast<Map<String, dynamic>>(),
      )
      .toList();

  test(
    'confirmation queues original IDs and archived patches without replacing current rows or cursor',
    () async {
      await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              id: 'legacy',
              userId: localUserId,
              content: 'Current local edit',
              projectId: inboxProjectId,
              orderKey: '1',
              createdAt: old,
              updatedAt: old.add(const Duration(days: 2)),
            ),
          );
      final beforeCursor = (await (db.select(
        db.syncState,
      )..where((r) => r.id.equals('pomodoist'))).getSingle()).cursor;
      expect((await watchSyncQueueStatus(db).first).recovering, isTrue);
      final request = (await engine.legacyRecoveryRequest())!;
      expect(request.recordCount, greaterThan(0));
      expect(await db.select(db.syncCommands).get(), isEmpty);
      final originalPayload =
          (await db.select(db.accountRecoverySnapshots).getSingle())
              .payloadJson;
      final originalTables = (await payload())['tables'];
      await engine.recoverLegacyArchive(request);
      final rows = await db.select(db.syncCommands).get();
      final operations = queued(rows);
      final original = operations.singleWhere(
        (op) => op['opId'] == 'original-operation',
      );
      expect(original['payload']['content'], 'Unsent patch');
      expect(
        original['clientUpdatedAt'],
        old.add(const Duration(minutes: 1)).toIso8601String(),
      );
      expect(
        operations.any(
          (op) =>
              op['entityId'] == 'legacy' &&
              op['payload']['content'] == 'Archived task',
        ),
        isTrue,
      );
      expect(
        (await db.select(db.tasks).getSingle()).content,
        'Current local edit',
      );
      expect(
        (await (db.select(
          db.syncState,
        )..where((r) => r.id.equals('pomodoist'))).getSingle()).cursor,
        beforeCursor,
      );
      await engine.recoverLegacyArchive(request);
      expect(await db.select(db.syncCommands).get(), rows);
      expect(await engine.legacyRecoveryRequest(), isNull);
      expect((await payload())['tables'], originalTables);
      final backup = await db.select(db.accountRecoverySnapshots).getSingle();
      expect(backup.payloadJson, originalPayload);
      expect(backup.ownerId, startsWith('legacy-recovered:A:'));
      expect((await watchSyncQueueStatus(db).first).pending, rows.length);
    },
  );

  for (final schema in [11, 12, 14]) {
    test('schema $schema archive decodes old task defaults', () async {
      await editArchive((data) {
        final tables = data['tables'] as Map;
        for (final row in tables['tasks'] as List) {
          (row as Map).remove('is_focus_estimate_manual');
        }
        tables.remove('calendar_projections');
      }, schema: schema);
      await engine.recoverLegacyArchive(
        (await engine.legacyRecoveryRequest())!,
      );
      final task = queued(
        await db.select(db.syncCommands).get(),
      ).firstWhere((op) => op['entityType'] == 'task');
      expect(task['payload']['isFocusEstimateManual'], false);
    });
  }

  test('account switch and changed archive invalidate confirmation', () async {
    final request = (await engine.legacyRecoveryRequest())!;
    account.user = 'B';
    await expectLater(engine.recoverLegacyArchive(request), throwsStateError);
    account.user = 'A';
    await editArchive(
      (data) => data['tables']['tasks'][0]['content'] = 'Changed archive',
    );
    await expectLater(engine.recoverLegacyArchive(request), throwsStateError);
    expect(await db.select(db.syncCommands).get(), isEmpty);
    expect((await payload())['recovery'], isNull);
  });

  test('corrupt archive cannot disappear into a completed state', () async {
    await editArchive(
      (data) => data['tables']['tasks'][0]['unknown_column'] = true,
    );
    await expectLater(engine.legacyRecoveryRequest(), throwsFormatException);
    expect((await watchSyncQueueStatus(db).first).recovering, isTrue);
    expect(await db.select(db.accountRecoverySnapshots).get(), hasLength(1));
  });

  test(
    'unknown commands remain rejected while valid records can recover',
    () async {
      await editArchive(
        (data) => data['tables']['sync_commands'][0]['type'] = 'future.command',
      );
      await engine.recoverLegacyArchive(
        (await engine.legacyRecoveryRequest())!,
      );
      expect((await watchSyncQueueStatus(db).first).rejected, 1);
      expect((await watchSyncQueueStatus(db).first).pending, greaterThan(0));
    },
  );

  test(
    'lost response preserves recovery operations across a new engine and retry',
    () async {
      await engine.recoverLegacyArchive(
        (await engine.legacyRecoveryRequest())!,
      );
      final operations = queued(await db.select(db.syncCommands).get());
      account.offline = true;
      await expectLater(engine.pushPending(), throwsA(isA<TimeoutException>()));
      expect((await watchSyncQueueStatus(db).first).pending, greaterThan(0));
      engine = testSyncEngine(db: db, account: account, uuid: const Uuid());
      account.offline = false;
      await engine.pushPending();
      expect(account.pushed.map((op) => op.toJson()).toList(), operations);
      expect(await db.select(db.syncCommands).get(), isEmpty);
      expect(await engine.legacyRecoveryRequest(), isNull);
    },
  );

  test(
    'habits and terminal focus recover; active focus stays paused locally',
    () async {
      await engine.recoverLegacyArchive(
        (await engine.legacyRecoveryRequest())!,
      );
      final operations = queued(await db.select(db.syncCommands).get());
      expect(
        operations
            .where((op) => op['entityType'] == 'focus_run')
            .single['entityId'],
        'finished',
      );
      expect(
        operations
            .where((op) => op['entityType'] == 'focus_interval')
            .single['entityId'],
        'finished-interval',
      );
      expect(
        operations
            .where((op) => op['entityType'] == 'focus_event')
            .single['entityId'],
        'finished-event',
      );
      expect(
        operations
            .where((op) => op['entityType'] == 'habit')
            .single['payload']['title'],
        'Read',
      );
      expect(
        operations.where((op) => op['entityType'] == 'habit_check_in'),
        hasLength(1),
      );
      expect((await db.select(db.focusRuns).getSingle()).status, 'paused');
      final interval = await db.select(db.focusIntervals).getSingle();
      expect(interval.status, 'paused');
      expect(interval.pausedAt, isNotNull);
      expect((await db.select(db.focusEvents).getSingle()).id, 'running-event');
    },
  );

  test(
    'frozen commands preserve original operation IDs and exclude active focus',
    () async {
      await editArchive((data) {
        final command = data['tables']['sync_commands'][0] as Map;
        command['payload_json'] = jsonEncode({
          '_syncDeviceIdV1': 'old-device',
          '_syncOperationsV1': [
            AccountSyncOperation.upsertV1(
              opId: 'frozen-op',
              entityType: 'task',
              entityId: 'legacy',
              payload: {'content': 'Frozen content'},
              clientUpdatedAt: old,
            ).toJson(),
            AccountSyncOperation.upsertV1(
              opId: 'active-op',
              entityType: 'focus_run',
              entityId: 'running',
              payload: {'id': 'running', 'status': 'active'},
              clientUpdatedAt: old,
            ).toJson(),
          ],
        });
      });
      await engine.recoverLegacyArchive(
        (await engine.legacyRecoveryRequest())!,
      );
      final operations = queued(await db.select(db.syncCommands).get());
      expect(
        operations.singleWhere(
          (op) => op['opId'] == 'frozen-op',
        )['payload']['content'],
        'Frozen content',
      );
      expect(operations.any((op) => op['opId'] == 'active-op'), isFalse);
      await engine.pushPending();
      expect((await watchSyncQueueStatus(db).first).rejected, 0);
    },
  );

  test(
    'current focus session is not modified by archived local session',
    () async {
      await db
          .into(db.focusRuns)
          .insert(
            FocusRunsCompanion.insert(
              id: 'running',
              userId: localUserId,
              presetId: 'current',
              status: 'active',
              startedAt: old,
              targetWorkIntervals: 2,
              createdAt: old,
              updatedAt: old.add(const Duration(days: 1)),
            ),
          );
      await engine.recoverLegacyArchive(
        (await engine.legacyRecoveryRequest())!,
      );
      expect((await db.select(db.focusRuns).getSingle()).status, 'active');
      expect(await db.select(db.focusIntervals).get(), isEmpty);
      expect(await db.select(db.focusEvents).get(), isEmpty);
    },
  );

  test('claimed archive cannot be offered to a different account', () async {
    final request = (await engine.legacyRecoveryRequest())!;
    await engine.recoverLegacyArchive(request);
    account.user = 'B';
    await engine.prepareLocalAccountData();
    expect(await engine.legacyRecoveryRequest(), isNull);
    await expectLater(engine.recoverLegacyArchive(request), throwsStateError);
    expect(await db.select(db.syncCommands).get(), isEmpty);
  });

  test(
    'recovered backup survives account restore cleanup and is removed only with its owner deletion',
    () async {
      await engine.recoverLegacyArchive(
        (await engine.legacyRecoveryRequest())!,
      );
      final store = AccountRecoveryStore(db);
      await store.discardOwner('A');
      expect(await db.select(db.accountRecoverySnapshots).get(), hasLength(1));
      await store.discardOwner('B', includeRecoveredLegacy: true);
      expect(await db.select(db.accountRecoverySnapshots).get(), hasLength(1));
      await store.discardOwner('A', includeRecoveredLegacy: true);
      expect(await db.select(db.accountRecoverySnapshots).get(), isEmpty);
    },
  );

  test('shared data and integration credentials are excluded', () async {
    await editArchive((data) {
      data['tables']['tasks'][0]['scope_id'] = 'shared-scope';
      data['tables']['sync_commands'][0]['scope_id'] = 'shared-scope';
      data['tables']['google_calendar_connections'] = [
        {'private_secret': 'must not import'},
      ];
    });
    await engine.recoverLegacyArchive((await engine.legacyRecoveryRequest())!);
    expect(
      queued(
        await db.select(db.syncCommands).get(),
      ).any((op) => op['entityId'] == 'legacy'),
      isFalse,
    );
    expect(await db.select(db.googleCalendarConnections).get(), isEmpty);
    expect(await db.select(db.calendarProjections).get(), isEmpty);
  });
}

class _Account implements AccountClient {
  String user = 'A';
  bool offline = false;
  final pushed = <AccountSyncOperation>[];
  @override
  String get currentUserId => user;
  @override
  AccountSession? get currentSession => null;
  @override
  Future<AccountSyncPushResult> pushChanges({
    required String appId,
    required String deviceId,
    required List<AccountSyncOperation> operations,
  }) async {
    if (offline) throw TimeoutException('Offline');
    pushed.addAll(operations);
    return const AccountSyncPushResult(serverRevision: 0, applied: []);
  }

  @override
  Future<AccountSyncPullResult> pullChanges({
    required String appId,
    required String deviceId,
    required int sinceRevision,
    int limit = 500,
  }) async => AccountSyncPullResult(
    nextCursor: sinceRevision,
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
