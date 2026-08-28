import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/core/sync/sync_queue_repository.dart';

void main() {
  test(
    'enqueueBatch preserves payload order with monotonic timestamps',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();
      final queue = DriftSyncQueueRepository(db);
      final occurredAt = DateTime.utc(2026, 7, 10, 9);

      await queue.enqueueBatch(const [
        SyncQueueCommand(
          type: 'task.create',
          clientId: 'task-1',
          payload: {'id': 'task-1'},
        ),
        SyncQueueCommand(
          type: 'task.kanbanStatus.set',
          clientId: 'task-1',
          payload: {
            'taskId': 'task-1',
            'labelId': kanbanStatusBacklogId,
            'changedAt': '2026-07-10T09:00:00.000Z',
          },
        ),
      ], occurredAt: occurredAt);
      await queue.enqueueBatch(const [
        SyncQueueCommand(
          type: 'task.complete',
          clientId: 'task-1',
          payload: {'id': 'task-1', 'completedAt': '2026-07-10T09:00:00.000Z'},
        ),
        SyncQueueCommand(
          type: 'task.kanbanStatus.set',
          clientId: 'task-1',
          payload: {
            'taskId': 'task-1',
            'labelId': kanbanStatusDoneId,
            'changedAt': '2026-07-10T09:00:00.000Z',
          },
        ),
      ], occurredAt: occurredAt);

      final rows = await queue.watchPending().first;
      expect(rows.map((row) => row.type), [
        'task.create',
        'task.kanbanStatus.set',
        'task.complete',
        'task.kanbanStatus.set',
      ]);
      expect(rows.map((row) => row.createdAt.toUtc()).toList(), [
        occurredAt,
        occurredAt.add(const Duration(seconds: 1)),
        occurredAt.add(const Duration(seconds: 2)),
        occurredAt.add(const Duration(seconds: 3)),
      ]);
      expect(jsonDecode(rows[1].payloadJson), {
        'taskId': 'task-1',
        'labelId': kanbanStatusBacklogId,
        'changedAt': '2026-07-10T09:00:00.000Z',
      });
    },
  );

  test(
    'enqueueBatch orders separate mutations within the same stored second',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();
      final queue = DriftSyncQueueRepository(db);
      final second = DateTime.utc(2026, 7, 10, 9);

      await queue.enqueueBatch(const [
        SyncQueueCommand(type: 'first', payload: {}),
      ], occurredAt: second.add(const Duration(milliseconds: 500)));
      await queue.enqueueBatch(const [
        SyncQueueCommand(type: 'second', payload: {}),
      ], occurredAt: second.add(const Duration(milliseconds: 800)));

      final rows = await queue.watchPending().first;
      expect(rows.map((row) => row.type), ['first', 'second']);
      expect(rows[0].createdAt.toUtc(), second);
      expect(rows[1].createdAt.toUtc(), second.add(const Duration(seconds: 1)));
    },
  );

  test(
    'stores deferred availability without delaying ordinary commands',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();
      final queue = DriftSyncQueueRepository(db);
      final availableAt = DateTime.utc(2026, 7, 10, 9, 0, 7);

      await queue.enqueueBatch([
        SyncQueueCommand(
          type: 'task.delete',
          clientId: 'task-1',
          payload: const {'id': 'task-1'},
          availableAt: availableAt,
        ),
        const SyncQueueCommand(
          type: 'task.update',
          clientId: 'task-2',
          payload: {'id': 'task-2'},
        ),
      ]);

      final rows = await queue.watchPending().first;
      expect(rows[0].availableAt?.toUtc(), availableAt);
      expect(rows[1].availableAt, isNull);
    },
  );

  test('connection upserts keep only the latest pending snapshot', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();
    final queue = DriftSyncQueueRepository(db);

    await queue.enqueue(
      type: 'task.update',
      clientId: 'task-1',
      payload: const {'id': 'task-1'},
    );
    for (var index = 0; index < 10000; index++) {
      await queue.enqueue(
        type: 'google_calendar.connection.upsert',
        clientId: 'primary',
        payload: {'id': 'primary', 'revision': index},
      );
    }

    final pending = await queue.watchPending().first;
    final connectionCommands = pending
        .where(
          (command) =>
              command.type == 'google_calendar.connection.upsert' &&
              command.clientId == 'primary',
        )
        .toList();
    expect(
      pending.where((command) => command.type == 'task.update'),
      hasLength(1),
    );
    expect(connectionCommands, hasLength(1));
    expect(jsonDecode(connectionCommands.single.payloadJson), {
      'id': 'primary',
      'revision': 9999,
    });
  });

  test('stale connection completion cannot remove its replacement', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();
    final queue = DriftSyncQueueRepository(db);

    await queue.enqueue(
      type: 'google_calendar.connection.upsert',
      clientId: 'primary',
      payload: const {'id': 'primary', 'status': 'syncing'},
    );
    final stale = (await queue.watchPending().first).single;
    await (db.update(db.syncCommands)..where((row) => row.id.equals(stale.id)))
        .write(const SyncCommandsCompanion(attempts: Value(1)));

    await queue.enqueue(
      type: 'google_calendar.connection.upsert',
      clientId: 'primary',
      payload: const {'id': 'primary', 'status': 'connected'},
    );

    var pending = await queue.watchPending().first;
    expect(pending, hasLength(1));
    expect(jsonDecode(pending.single.payloadJson)['status'], 'connected');

    await (db.update(db.syncCommands)..where((row) => row.id.equals(stale.id)))
        .write(const SyncCommandsCompanion(status: Value('synced')));

    pending = await queue.watchPending().first;
    expect(pending, hasLength(1));
    expect(jsonDecode(pending.single.payloadJson)['status'], 'connected');
  });
}
