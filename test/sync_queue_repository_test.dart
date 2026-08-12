import 'dart:convert';

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
}
