import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/planning/quick_add_hint_repository.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/utils/result.dart';

void main() {
  test('only manual task creation publishes a task-created event', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();
    var notifications = 0;
    final repository = DriftTaskRepository(db, DriftOutboxService(db));

    addTearDown(repository.dispose);
    final subscription = repository.userTaskCreated.listen(
      (_) => notifications++,
    );
    addTearDown(subscription.cancel);

    await repository
        .createTask(CreateTaskInput(content: 'Manual task'))
        .then((result) => result.getOrThrow());
    await repository
        .createTaskFromCalendar(
          RemoteCalendarTaskInput(
            content: 'Calendar task',
            schedule: TaskSchedule.allDay(DateTime(2026, 7, 9)),
            updatedAt: DateTime.utc(2026, 7, 9),
          ),
        )
        .then((result) => result.getOrThrow());

    final failed = await repository.createTask(
      CreateTaskInput(content: 'Rolled back task', labelId: 'missing-label'),
    );
    expect(failed, isA<Failure<String>>());
    await pumpEventQueue();
    expect(notifications, 1);
  });

  test(
    'composition forwards committed task events and isolates hint failures',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();
      final hints = _RecordingHints();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          quickAddHintRepositoryProvider.overrideWithValue(hints),
        ],
      );
      addTearDown(container.dispose);
      final tasks = container.read(taskRepositoryProvider);
      (await tasks.createTask(CreateTaskInput(content: 'First'))).getOrThrow();
      await pumpEventQueue();
      expect(hints.created, 1);
      hints.fail = true;
      final id = (await tasks.createTask(
        CreateTaskInput(content: 'Second'),
      )).getOrThrow();
      await pumpEventQueue();
      expect(hints.created, 2);
      expect((await tasks.watchTask(id).first)?.content, 'Second');
    },
  );
}

class _RecordingHints implements QuickAddHintRepository {
  int created = 0;
  bool fail = false;
  @override
  Future<void> recordUserTaskCreated() {
    created++;
    if (fail) throw StateError('Hint store unavailable');
    return Future.value();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
