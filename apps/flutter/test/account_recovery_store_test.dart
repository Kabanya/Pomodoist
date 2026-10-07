import 'dart:convert';
import 'dart:io';
import 'package:pomodoist/data/repositories/focus/focus_repository_impl.dart';
import 'package:pomodoist/data/services/notifications/notification_scheduler.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/local/sync_ownership_coordinator.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:uuid/uuid.dart';

void main() {
  late AppDatabase db;
  String? user;
  late SyncOwnershipCoordinator owners;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.ensureSeedData();
    user = 'A';
    owners = SyncOwnershipCoordinator(db, const Uuid(), () => user);
    await owners.prepareAccount();
  });
  tearDown(() => db.close());

  Future<void> task(String id, {bool queued = true}) async {
    final now = DateTime.utc(2026, 10, 7);
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: id,
            userId: localUserId,
            content: 'Unsent $id',
            projectId: inboxProjectId,
            orderKey: '1',
            createdAt: now,
            updatedAt: now,
          ),
        );
    if (queued) {
      await db
          .into(db.syncCommands)
          .insert(
            SyncCommandsCompanion.insert(
              id: 'command-$id',
              uuid: 'operation-$id',
              type: 'task.create',
              clientId: Value(id),
              payloadJson: jsonEncode({'content': 'Unsent $id'}),
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
  }

  test(
    'A survives guest and B transitions with original command identity',
    () async {
      await task('a');
      user = null;
      await SyncOwnershipCoordinator.prepareGuestLocalData(
        db: db,
        uuid: const Uuid(),
      );
      expect(await db.select(db.tasks).get(), isEmpty);
      await task('guest');
      user = 'B';
      await owners.prepareAccount();
      expect(await db.select(db.tasks).get(), isEmpty);
      await task('b');
      user = 'A';
      await owners.prepareAccount();
      expect((await db.select(db.tasks).get()).map((t) => t.id), ['a']);
      expect(
        (await db.select(db.syncCommands).getSingle()).uuid,
        'operation-a',
      );
      await owners.prepareAccount();
      expect((await db.select(db.tasks).get()).length, 1);
      user = null;
      await SyncOwnershipCoordinator.prepareGuestLocalData(
        db: db,
        uuid: const Uuid(),
      );
      expect((await db.select(db.tasks).get()).map((t) => t.id), ['guest']);
    },
  );

  test(
    'unimported data without an outbox command survives returning to owner',
    () async {
      await task('no-command', queued: false);
      user = 'B';
      await owners.prepareAccount();
      user = 'A';
      await owners.prepareAccount();
      expect(
        (await db.select(db.tasks).getSingle()).content,
        'Unsent no-command',
      );
    },
  );

  test(
    'archive write failure rolls back owner transition and keeps data',
    () async {
      await task('disk-full');
      await db.customStatement(
        '''CREATE TRIGGER fail_archive BEFORE INSERT ON
      account_recovery_snapshots BEGIN SELECT RAISE(ABORT, 'disk full'); END''',
      );
      user = 'B';
      await expectLater(owners.prepareAccount(), throwsA(anything));
      expect((await db.select(db.tasks).getSingle()).id, 'disk-full');
      expect(
        (await (db.select(db.syncState)
                  ..where((r) => r.id.equals('pomodoist-account-owner-v1')))
                .getSingle())
            .cursor,
        'A',
      );
    },
  );

  test(
    'corrupt archive is retained and active account reset rolls back',
    () async {
      await task('a');
      user = 'B';
      await owners.prepareAccount();
      await task('b');
      await db.customStatement(
        "UPDATE account_recovery_snapshots SET payload_json='invalid' WHERE owner_id='A'",
      );
      user = 'A';
      await expectLater(
        owners.prepareAccount(),
        throwsA(isA<FormatException>()),
      );
      expect((await db.select(db.tasks).getSingle()).id, 'b');
      expect(
        (await db.select(db.accountRecoverySnapshots).getSingle()).payloadJson,
        'invalid',
      );
    },
  );

  test(
    'restoration leaves shared cache hidden while retaining scoped intent',
    () async {
      await task('shared');
      await (db.update(db.tasks)..where((r) => r.id.equals('shared'))).write(
        const TasksCompanion(scopeId: Value('scope')),
      );
      await db
          .update(db.syncCommands)
          .write(const SyncCommandsCompanion(scopeId: Value('scope')));
      user = 'B';
      await owners.prepareAccount();
      user = 'A';
      await owners.prepareAccount();
      expect(await db.select(db.tasks).get(), isEmpty);
      expect((await db.select(db.syncCommands).getSingle()).scopeId, 'scope');
    },
  );
  test('stale owner repository cannot commit into the next account', () async {
    final stale = DriftTaskRepository(
      db,
      DriftOutboxService(db, expectedOwner: Future.value('A')),
    );
    user = 'B';
    await owners.prepareAccount();
    final result = await stale.createTask(
      CreateTaskInput(content: 'Must not reach B'),
    );
    expect(() => result.getOrThrow(), throwsStateError);
    expect(await db.select(db.tasks).get(), isEmpty);
    expect(await db.select(db.syncCommands).get(), isEmpty);
  });

  test(
    'archive survives file reopen and schema-11 snapshot restores atomically',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'account-recovery-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      await db.close();
      db = AppDatabase(NativeDatabase(File('${directory.path}/data.sqlite')));
      owners = SyncOwnershipCoordinator(db, const Uuid(), () => user);
      await owners.prepareAccount();
      await task('persisted');
      user = 'B';
      await owners.prepareAccount();
      await db.customStatement(
        "UPDATE account_recovery_snapshots SET schema_version=11 WHERE owner_id='A'",
      );
      await db.close();
      db = AppDatabase(NativeDatabase(File('${directory.path}/data.sqlite')));
      owners = SyncOwnershipCoordinator(db, const Uuid(), () => user);
      user = 'A';
      await owners.prepareAccount();
      expect((await db.select(db.tasks).getSingle()).id, 'persisted');
      expect(
        (await db.select(db.syncCommands).getSingle()).uuid,
        'operation-persisted',
      );
      expect(
        (await db.customSelect('PRAGMA integrity_check').getSingle())
            .data
            .values
            .single,
        'ok',
      );
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    },
  );

  test(
    'active Focus restores paused at archival time without logged-out duration',
    () async {
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 2));
      await db
          .into(db.focusRuns)
          .insert(
            FocusRunsCompanion.insert(
              id: 'run',
              userId: localUserId,
              presetId: defaultPresetId,
              status: 'active',
              startedAt: now,
              targetWorkIntervals: 1,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.focusIntervals)
          .insert(
            FocusIntervalsCompanion.insert(
              id: 'interval',
              runId: 'run',
              type: 'work',
              status: 'running',
              plannedSeconds: 1500,
              startedAt: now,
              sequenceNumber: 1,
              createdAt: now,
              updatedAt: now,
            ),
          );
      user = 'B';
      await owners.prepareAccount();
      final archivedAt = (await (db.select(
        db.accountRecoverySnapshots,
      )..where((r) => r.ownerId.equals('A'))).getSingle()).createdAt;
      user = 'A';
      await owners.prepareAccount();
      final interval = await db.select(db.focusIntervals).getSingle();
      expect(interval.status, 'paused');
      expect(interval.pausedAt, archivedAt);
      expect((await db.select(db.focusRuns).getSingle()).status, 'paused');
      expect(await db.select(db.focusEvents).get(), isEmpty);
    },
  );
  test(
    'stale Focus writer cannot create a preset or run for the next account',
    () async {
      final stale = DriftFocusRepository(
        db,
        DriftOutboxService(db, expectedOwner: Future.value('A')),
        NotificationScheduler(),
      );
      user = 'B';
      await owners.prepareAccount();
      final result = await stale.startRun(const StartFocusRunInput());
      expect(() => result.getOrThrow(), throwsStateError);
      expect(await db.select(db.focusRuns).get(), isEmpty);
      final preset = await stale.createPreset(
        const CreateFocusPresetInput(
          name: 'Old owner',
          workSeconds: 1500,
          shortBreakSeconds: 300,
          longBreakSeconds: 900,
          intervalsBeforeLongBreak: 4,
        ),
      );
      expect(() => preset.getOrThrow(), throwsStateError);
      expect(
        (await db.select(db.focusPresets).get()).any(
          (p) => p.name == 'Old owner',
        ),
        isFalse,
      );
    },
  );
}
