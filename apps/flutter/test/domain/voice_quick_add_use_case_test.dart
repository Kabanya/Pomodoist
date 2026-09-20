import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/projects/project_repository_impl.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';
import 'package:pomodoist/domain/models/planning/task_decomposition.dart';
import 'package:pomodoist/domain/use_cases/quick_add/quick_add_use_case.dart';
import 'package:pomodoist/domain/use_cases/quick_add/voice_quick_add_use_case.dart';

class _FailSecondTaskInsert extends QueryInterceptor {
  bool enabled = false;
  int _taskInserts = 0;

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (enabled && statement.contains('INSERT INTO "tasks"')) {
      _taskInserts += 1;
      if (_taskInserts == 2) {
        throw StateError('Injected second task failure');
      }
    }
    return super.runInsert(executor, statement, args);
  }
}

void main() {
  late AppDatabase db;
  late _FailSecondTaskInsert interceptor;
  late QuickAddUseCase quickAdd;

  setUp(() async {
    interceptor = _FailSecondTaskInsert();
    db = AppDatabase(NativeDatabase.memory().interceptWith(interceptor));
    await db.ensureSeedData();
    final outbox = DriftOutboxService(db);
    quickAdd = QuickAddUseCase(
      parser: const QuickAddParser(),
      taskRepository: DriftTaskRepository(db, outbox),
      projectRepository: DriftProjectRepository(db, outbox),
    );
  });

  tearDown(() => db.close());

  VoiceQuickAddUseCase useCase() => VoiceQuickAddUseCase(
    quickAdd: quickAdd,
    runLocalTransaction: db.transaction,
  );

  test(
    'a failure on the second task rolls back the first task, project and labels',
    () async {
      final tasksBefore = await db.select(db.tasks).get();
      final projectsBefore = await db.select(db.projects).get();
      final labelsBefore = await db.select(db.labels).get();
      final commandsBefore = await db.select(db.syncCommands).get();

      interceptor.enabled = true;
      await expectLater(
        useCase()([
          DecomposedTaskDraft(quickAdd: 'First #Work @Extra'),
          DecomposedTaskDraft(quickAdd: 'Second'),
        ]),
        throwsStateError,
      );

      expect(await db.select(db.tasks).get(), tasksBefore);
      expect(await db.select(db.projects).get(), projectsBefore);
      expect(await db.select(db.labels).get(), labelsBefore);
      expect(await db.select(db.syncCommands).get(), commandsBefore);
    },
  );

  test('a successful repeat writes one batch and one workspace', () async {
    final created = await useCase()([
      DecomposedTaskDraft(quickAdd: 'First #Work @Extra'),
      DecomposedTaskDraft(quickAdd: 'Second'),
    ]);

    expect(created, hasLength(2));
    final tasks = await db.select(db.tasks).get();
    expect(tasks, hasLength(2));
    expect(
      (await db.select(db.projects).get()).where((p) => p.name == 'Work'),
      hasLength(1),
    );
    expect(
      (await db.select(db.labels).get()).where((l) => l.name == 'Extra'),
      hasLength(1),
    );
    final creates = await (db.select(
      db.syncCommands,
    )..where((row) => row.type.equals('task.create'))).get();
    expect(creates, hasLength(2));
  });
}
