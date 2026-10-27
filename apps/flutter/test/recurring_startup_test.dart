import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

class _Reads extends QueryInterceptor {
  int tasks = 0;
  int scopes = 0;
  bool failNextRead = false;
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.startsWith('SELECT * FROM "tasks" WHERE "is_deleted"')) {
      tasks++;
      if (failNextRead) {
        failNextRead = false;
        throw StateError('Injected read failure');
      }
    }
    if (statement.contains('FROM "shared_scopes"')) scopes++;
    return executor.runSelect(statement, args);
  }
}

void main() {
  test(
    'large task store coalesces bursts without duplicate occurrences',
    () async {
      final reads = _Reads();
      final db = AppDatabase(NativeDatabase.memory().interceptWith(reads));
      addTearDown(db.close);
      await db.ensureSeedData();
      final repository = DriftTaskRepository(db, DriftOutboxService(db));
      final now = DateTime(2026, 7, 2);
      await db.batch((batch) {
        batch.insertAll(db.tasks, [
          for (var task = 0; task < 10000; task++)
            TasksCompanion.insert(
              id: 'ordinary-$task',
              userId: localUserId,
              projectId: inboxProjectId,
              content: 'Ordinary task',
              scopeId: const Value('scope'),
              orderKey: '$task',
              createdAt: now,
              updatedAt: now,
            ),
        ]);
      });
      for (var series = 0; series < 100; series++) {
        (await repository.createTask(
          CreateTaskInput(
            content: 'Daily',
            schedule: TaskSchedule.allDay(
              DateTime(2026, 7, 1),
              recurrence: TaskRecurrence(
                interval: 1,
                unit: TaskRecurrenceUnit.day,
                seriesId: 'daily-$series',
              ),
            ),
          ),
        )).getOrThrow();
      }
      reads.tasks = 0;
      reads.scopes = 0;
      for (var wave = 0; wave < 10; wave++) {
        final results = await Future.wait([
          for (var request = 0; request < 200; request++)
            repository.materializeDueRecurringTasks(now: now),
        ]);
        for (final result in results) {
          result.getOrThrow();
        }
        expect(reads.tasks, wave + 1);
        expect(reads.scopes, 0);
        expect(await db.select(db.tasks).get(), hasLength(10200));
      }
    },
  );

  test(
    'overlapping recurrence runs share one scan and allow later retries',
    () async {
      final reads = _Reads();
      final db = AppDatabase(NativeDatabase.memory().interceptWith(reads));
      addTearDown(db.close);
      await db.ensureSeedData();
      final repository = DriftTaskRepository(db, DriftOutboxService(db));
      (await repository.createTask(
        CreateTaskInput(
          content: 'Daily',
          schedule: TaskSchedule.allDay(
            DateTime(2026, 7, 1),
            recurrence: const TaskRecurrence(
              interval: 1,
              unit: TaskRecurrenceUnit.day,
              seriesId: 'daily',
            ),
          ),
        ),
      )).getOrThrow();
      reads.tasks = 0;
      final now = DateTime(2026, 7, 2);
      final results = await Future.wait([
        repository.materializeDueRecurringTasks(now: now),
        repository.materializeDueRecurringTasks(now: now),
      ]);
      for (final result in results) {
        result.getOrThrow();
      }
      expect(reads.tasks, 1);
      expect(await db.select(db.tasks).get(), hasLength(2));

      reads.failNextRead = true;
      final failure = await repository.materializeDueRecurringTasks(now: now);
      expect(failure.getOrThrow, throwsStateError);
      (await repository.materializeDueRecurringTasks(now: now)).getOrThrow();
      expect(await db.select(db.tasks).get(), hasLength(2));
    },
  );

  test(
    'ordinary shared tasks do not require per-row access reads during recurrence scan',
    () async {
      final reads = _Reads();
      final db = AppDatabase(NativeDatabase.memory().interceptWith(reads));
      addTearDown(db.close);
      await db.ensureSeedData();
      final now = DateTime.utc(2026, 7, 2);
      await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              id: 'shared-task',
              userId: localUserId,
              projectId: inboxProjectId,
              content: 'Shared ordinary task',
              scopeId: const Value('scope'),
              orderKey: 'a',
              createdAt: now,
              updatedAt: now,
            ),
          );
      (await DriftTaskRepository(
        db,
        DriftOutboxService(db),
      ).materializeDueRecurringTasks(now: now)).getOrThrow();
      expect(reads.scopes, 0);
    },
  );
}
