import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/utils/result.dart';

class _ThrowingOutboxService implements OutboxService {
  @override
  Future<void> enqueue({
    required String type,
    required Map<String, Object?> payload,
    String? clientId,
    DateTime? availableAt,
  }) {
    throw StateError('Injected outbox failure');
  }

  @override
  Future<void> enqueueBatch(
    List<SyncQueueCommand> commands, {
    DateTime? occurredAt,
  }) {
    throw StateError('Injected outbox failure');
  }

  @override
  Stream<List<SyncCommandRow>> watchPending() => const Stream.empty();
}

class _FailingInsertInterceptor extends QueryInterceptor {
  _FailingInsertInterceptor(this.fragment);

  final String fragment;
  bool enabled = false;

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (enabled && statement.contains(fragment)) {
      throw StateError('Injected secondary row failure');
    }
    return super.runInsert(executor, statement, args);
  }
}

Future<int> _countCommands(AppDatabase db, String type) async {
  final rows = await (db.select(
    db.syncCommands,
  )..where((row) => row.type.equals(type))).get();
  return rows.length;
}

void main() {
  late AppDatabase db;
  late _FailingInsertInterceptor interceptor;

  setUp(() async {
    interceptor = _FailingInsertInterceptor('INSERT INTO "task_labels"');
    db = AppDatabase(NativeDatabase.memory().interceptWith(interceptor));
    await db.ensureSeedData();
  });

  tearDown(() async {
    await db.close();
  });

  test('outbox failure rolls back the task and every related row', () async {
    final repository = DriftTaskRepository(db, _ThrowingOutboxService());

    final result = await repository.createTask(
      CreateTaskInput(content: 'Atomic task'),
    );

    expect(result, isA<Failure<String>>());
    expect(await db.select(db.tasks).get(), isEmpty);
    expect(await db.select(db.syncCommands).get(), isEmpty);
    expect(await db.select(db.taskLabels).get(), isEmpty);
  });

  test('retry after an outbox failure creates exactly one operation', () async {
    final failing = DriftTaskRepository(db, _ThrowingOutboxService());
    expect(
      await failing.createTask(CreateTaskInput(content: 'Atomic task')),
      isA<Failure<String>>(),
    );

    final repository = DriftTaskRepository(db, DriftOutboxService(db));
    final retry = await repository.createTask(
      CreateTaskInput(content: 'Atomic task'),
    );

    expect(retry.getOrThrow(), isNotEmpty);
    expect(await db.select(db.tasks).get(), hasLength(1));
    expect(await _countCommands(db, 'task.create'), 1);
    expect(await db.select(db.taskLabels).get(), hasLength(1));
  });

  test('secondary row failure rolls back the already written task', () async {
    final repository = DriftTaskRepository(db, DriftOutboxService(db));
    interceptor.enabled = true;

    final result = await repository.createTask(
      CreateTaskInput(content: 'Atomic task'),
    );

    expect(result, isA<Failure<String>>());
    expect(await db.select(db.tasks).get(), isEmpty);
    expect(await db.select(db.syncCommands).get(), isEmpty);
    expect(await db.select(db.taskLabels).get(), isEmpty);
  });

  test(
    'retry after a secondary row failure creates exactly one operation',
    () async {
      final repository = DriftTaskRepository(db, DriftOutboxService(db));
      interceptor.enabled = true;
      expect(
        await repository.createTask(CreateTaskInput(content: 'Atomic task')),
        isA<Failure<String>>(),
      );

      interceptor.enabled = false;
      final retry = await repository.createTask(
        CreateTaskInput(content: 'Atomic task'),
      );

      expect(retry.getOrThrow(), isNotEmpty);
      expect(await db.select(db.tasks).get(), hasLength(1));
      expect(await _countCommands(db, 'task.create'), 1);
      expect(await db.select(db.taskLabels).get(), hasLength(1));
    },
  );

  test(
    'a nested operation returning Failure aborts the enclosing operation',
    () async {
      final now = DateTime.utc(2026, 9, 20);
      await db
          .into(db.projects)
          .insert(
            ProjectsCompanion.insert(
              id: 'shared-project',
              userId: localUserId,
              name: 'Shared',
              scopeId: const Value('scope-1'),
              orderKey: '1',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.sharedScopes)
          .insert(
            SharedScopesCompanion.insert(
              id: 'scope-1',
              dataJson:
                  '{"id":"scope-1","rootProjectId":"shared-project","ownerId":"owner","role":"observer"}',
            ),
          );
      await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              id: 'shared-task',
              userId: localUserId,
              content: 'Read only',
              projectId: 'shared-project',
              scopeId: const Value('scope-1'),
              orderKey: '1',
              createdAt: now,
              updatedAt: now,
            ),
          );
      final repository = DriftTaskRepository(db, DriftOutboxService(db));

      final result = await repository.deleteTask('shared-task');

      expect(result, isA<Failure<DeletedTaskBatch>>());
      final row = await (db.select(
        db.tasks,
      )..where((task) => task.id.equals('shared-task'))).getSingle();
      expect(row.isDeleted, isFalse);
      expect(await db.select(db.syncCommands).get(), isEmpty);
    },
  );
}
