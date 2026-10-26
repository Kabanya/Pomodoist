import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/focus_adoption_service.dart';

void main() {
  late AppDatabase db;
  final now = DateTime.utc(2026, 10, 26);
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.ensureSeedData();
    for (final suffix in ['a', 'b']) {
      await db
          .into(db.focusRuns)
          .insert(
            FocusRunsCompanion.insert(
              id: 'run-$suffix',
              userId: 'owner',
              presetId: 'preset',
              status: 'running',
              startedAt: now,
              targetWorkIntervals: 4,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.focusIntervals)
          .insert(
            FocusIntervalsCompanion.insert(
              id: 'interval-$suffix',
              runId: 'run-$suffix',
              type: 'work',
              status: 'running',
              plannedSeconds: 1500,
              startedAt: now,
              sequenceNumber: 1,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.focusEvents)
          .insert(
            FocusEventsCompanion.insert(
              id: 'event-$suffix',
              runId: 'run-$suffix',
              intervalId: Value('interval-$suffix'),
              type: 'distractionLogged',
              occurredAt: now,
              createdAt: now,
            ),
          );
    }
  });
  tearDown(() => db.close());

  test(
    'exports complete prior history using ISO dates without changing outbox or other runs',
    () async {
      await db
          .into(db.focusIntervals)
          .insert(
            FocusIntervalsCompanion.insert(
              id: 'prior',
              runId: 'run-a',
              type: 'work',
              status: 'completed',
              plannedSeconds: 60,
              startedAt: now.subtract(const Duration(minutes: 1)),
              completedAt: Value(now),
              sequenceNumber: 1,
              createdAt: now,
              updatedAt: now,
            ),
          );
      final history = await exportFocusAdoptionHistory(
        db,
        'run-a',
        'interval-a',
      );
      final intervals = history['intervals'] as List;
      expect(intervals, hasLength(1));
      expect(intervals.single['id'], 'prior');
      expect(DateTime.parse(intervals.single['completedAt']), now);
      expect((history['events'] as List).single['id'], 'event-a');
      expect((await db.select(db.focusIntervals).get()), hasLength(3));
    },
  );

  Future<void> queue(
    String id,
    String type,
    Map<String, Object?> payload, {
    String? clientId,
    String status = 'pending',
  }) => db
      .into(db.syncCommands)
      .insert(
        SyncCommandsCompanion.insert(
          id: id,
          uuid: id,
          type: type,
          clientId: Value(clientId),
          payloadJson: jsonEncode(payload),
          status: Value(status),
          lastError: status == 'rejected'
              ? const Value('42501')
              : const Value.absent(),
          createdAt: now,
          updatedAt: now,
        ),
      )
      .then((_) {});

  Future<Map<String, SyncCommandRow>> commands() async => {
    for (final row in await db.select(db.syncCommands).get()) row.id: row,
  };
  Map<String, Object?> op(
    String id,
    String type,
    String entityId,
    Map<String, Object?> payload,
  ) => {
    'opId': id,
    'entityType': type,
    'entityId': entityId,
    'operation': 'upsert',
    'payload': payload,
    'clientUpdatedAt': now.toIso8601String(),
  };

  test(
    'retires only adopted lifecycle commands with interval and event ID mapping',
    () async {
      await queue('run-id', 'focus.run.start', {'id': 'run-a'});
      await queue('run-client', 'focus.run.pause', {}, clientId: 'run-a');
      await queue(
        'interval-client',
        'focus.interval.pause',
        {},
        clientId: 'interval-a',
      );
      await queue('interval-id', 'focus.interval.resume', {'id': 'interval-a'});
      await queue('new-interval', 'focus.interval.start', {
        'id': 'new',
        'runId': 'run-a',
      });
      await queue('event-run', 'focus.distraction.log', {'runId': 'run-a'});
      await queue(
        'event-client',
        'focus.distraction.log',
        {},
        clientId: 'event-a',
      );
      await queue('rejected', 'focus.run.stop', {
        'id': 'run-a',
      }, status: 'rejected');
      await queue('other-run', 'focus.run.stop', {'id': 'run-b'});
      await queue(
        'other-interval',
        'focus.interval.stop',
        {},
        clientId: 'interval-b',
      );
      await queue('explicit-other', 'focus.interval.pause', {
        'runId': 'run-b',
      }, clientId: 'interval-a');
      await queue('task', 'task.update', {'id': 'run-a'}, clientId: 'run-a');
      await queue('preset', 'focus.preset.update', {
        'id': 'run-a',
      }, clientId: 'run-a');
      await queue('unknown', 'focus.custom', {'runId': 'run-a'});
      final before = await commands();
      final runs = await db.select(db.focusRuns).get();
      final intervals = await db.select(db.focusIntervals).get();
      final events = await db.select(db.focusEvents).get();
      await acknowledgeAdoptedFocusRun(db, 'run-a');
      final after = await commands();
      for (final id in [
        'run-id',
        'run-client',
        'interval-client',
        'interval-id',
        'new-interval',
        'event-run',
        'event-client',
        'rejected',
      ]) {
        expect(after[id]!.status, 'synced', reason: id);
        expect(after[id]!.lastError, isNull, reason: id);
      }
      for (final id in [
        'other-run',
        'other-interval',
        'explicit-other',
        'task',
        'preset',
        'unknown',
      ]) {
        expect(after[id], before[id], reason: id);
      }
      expect(await db.select(db.focusRuns).get(), runs);
      expect(await db.select(db.focusIntervals).get(), intervals);
      expect(await db.select(db.focusEvents).get(), events);
      await acknowledgeAdoptedFocusRun(db, 'run-a');
      expect(await commands(), after);
    },
  );

  test(
    'strips adopted operations from mixed captures without changing tasks or presets',
    () async {
      final related = [
        op('run', 'focus_run', 'run-a', {}),
        op('interval', 'focus_interval', 'interval-a', {}),
        op('event', 'focus_event', 'event-a', {}),
      ];
      final retained = [
        op('task', 'task', 'run-a', {}),
        op('preset', 'focus_preset', 'run-a', {}),
        op('other', 'focus_interval', 'interval-b', {'runId': 'run-b'}),
        {'unknown': 'preserve'},
      ];
      await queue('mixed', 'sync.snapshot', {
        '_syncDeviceIdV1': 'device',
        'keep': 42,
        '_syncOperationsV1': [...related, ...retained],
      });
      await queue('only', 'focus.run.stop', {
        '_syncOperationsV1': related,
      }, clientId: 'run-a');
      final original = await commands();
      await acknowledgeAdoptedFocusRun(db, 'run-a');
      final rows = await commands();
      expect(rows['only']!.status, 'synced');
      expect(rows['mixed']!.status, 'pending');
      expect(jsonDecode(rows['mixed']!.payloadJson), {
        '_syncDeviceIdV1': 'device',
        'keep': 42,
        '_syncOperationsV1': retained,
      });
      expect(rows['mixed']!.uuid, original['mixed']!.uuid);
      expect(rows['mixed']!.clientId, original['mixed']!.clientId);
    },
  );

  test('malformed and unrelated captures remain untouched', () async {
    await queue('invalid-list', 'focus.run.stop', {
      'id': 'run-a',
      '_syncOperationsV1': 'invalid',
    });
    await queue('unrelated', 'sync.snapshot', {
      '_syncOperationsV1': [op('other', 'focus_run', 'run-b', {})],
    });
    await queue('invalid-json', 'focus.run.stop', {}, clientId: 'run-a');
    await (db.update(db.syncCommands)
          ..where((row) => row.id.equals('invalid-json')))
        .write(const SyncCommandsCompanion(payloadJson: Value('{')));
    final before = await commands();
    await acknowledgeAdoptedFocusRun(db, 'run-a');
    expect(await commands(), before);
  });

  test('all retirements roll back when any queue write fails', () async {
    await queue('a', 'focus.run.start', {'id': 'run-a'});
    await queue('b', 'sync.snapshot', {
      '_syncOperationsV1': [
        op('run', 'focus_run', 'run-a', {}),
        op('task', 'task', 'task', {}),
      ],
    });
    final before = await commands();
    await db.customStatement(
      "CREATE TRIGGER fail_adoption BEFORE UPDATE ON sync_commands WHEN OLD.id = 'b' BEGIN SELECT RAISE(ABORT, 'test rollback'); END",
    );
    await expectLater(
      acknowledgeAdoptedFocusRun(db, 'run-a'),
      throwsA(anything),
    );
    expect(await commands(), before);
  });
}
