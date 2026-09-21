import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/planning/quick_add_hint_repository.dart';
import 'package:pomodoist/data/repositories/projects/project_repository_impl.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';
import 'package:pomodoist/data/services/audio/focus_sound_player.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/use_cases/quick_add/quick_add_use_case.dart';
import 'package:pomodoist/utils/result.dart';

void main() {
  test('only manual quick-add creation records a hint event', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();
    final syncQueue = DriftOutboxService(db);
    final tasks = DriftTaskRepository(db, syncQueue);
    final hints = _RecordingHints();
    final quickAdd = QuickAddUseCase(
      parser: const QuickAddParser(),
      taskRepository: tasks,
      projectRepository: DriftProjectRepository(db, syncQueue),
      hints: hints,
    );

    await quickAdd.createTask('Manual task').then((r) => r.getOrThrow());
    expect(hints.created, 1);

    await tasks
        .createTaskFromCalendar(
          RemoteCalendarTaskInput(
            content: 'Calendar task',
            schedule: TaskSchedule.allDay(DateTime(2026, 7, 9)),
            updatedAt: DateTime.utc(2026, 7, 9),
          ),
        )
        .then((result) => result.getOrThrow());
    expect(hints.created, 1);

    final failed = await quickAdd.createTask(
      'Rolled back task',
      labelId: 'missing-label',
    );
    expect(failed, isA<Failure<String>>());
    expect(hints.created, 1);

    await quickAdd
        .createTask('Voice draft', recordCreation: false)
        .then((r) => r.getOrThrow());
    expect(hints.created, 1);
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
          lastFocusPresetIdProvider.overrideWithValue(null),
          focusSoundPlayerProvider.overrideWithValue(_SilentSoundPlayer()),
        ],
      );
      addTearDown(container.dispose);
      final quickAdd = container.read(quickAddUseCaseProvider);
      (await quickAdd.createTask('First')).getOrThrow();
      expect(hints.created, 1);
      hints.fail = true;
      final id = (await quickAdd.createTask('Second')).getOrThrow();
      expect(hints.created, 2);
      final task = await container
          .read(taskRepositoryProvider)
          .watchTask(id)
          .first;
      expect(task?.content, 'Second');
    },
  );
}

class _SilentSoundPlayer implements FocusSoundPlayer {
  @override
  Future<void> play(FocusSoundCue cue) async {}

  @override
  Future<void> dispose() async {}
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
