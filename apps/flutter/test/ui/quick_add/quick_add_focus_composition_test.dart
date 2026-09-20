import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/focus/focus_repository.dart';
import 'package:pomodoist/data/repositories/projects/project_repository.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/utils/result.dart';

void main() {
  test(
    'Quick Add resolves selected and fallback presets through the repository',
    () async {
      final tasks = _Tasks();
      final focus = _Focus();
      String? selected = 'short';
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith(
            (_) => throw StateError('Unexpected database access'),
          ),
          taskRepositoryProvider.overrideWithValue(tasks),
          projectRepositoryProvider.overrideWithValue(_Projects()),
          focusRepositoryProvider.overrideWithValue(focus),
          lastFocusPresetIdProvider.overrideWith((_) => selected),
          quickAddParserProvider.overrideWithValue(const QuickAddParser()),
        ],
      );
      addTearDown(container.dispose);
      final useCase = container.read(quickAddUseCaseProvider);
      final schedule = TaskSchedule.timed(
        start: DateTime(2026, 9, 21, 10),
        end: DateTime(2026, 9, 21, 10, 30),
      );

      (await useCase.createTask(
        'Selected preset',
        defaultSchedule: schedule,
      )).getOrThrow();
      expect(tasks.created.last.estimatedFocusIntervals, 2);
      selected = 'removed';
      container.invalidate(lastFocusPresetIdProvider);
      (await useCase.createTask(
        'Default preset',
        defaultSchedule: schedule,
      )).getOrThrow();
      expect(tasks.created.last.estimatedFocusIntervals, 1);
      expect(focus.reads, 2);
    },
  );
}

class _Tasks implements TaskRepository {
  final created = <CreateTaskInput>[];
  @override
  Future<Result<String>> createTask(CreateTaskInput input) async {
    created.add(input);
    return Success('task-${created.length}');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Projects implements ProjectRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Focus implements FocusRepository {
  int reads = 0;
  @override
  Stream<List<FocusPresetItem>> watchPresets() {
    reads++;
    return Stream.value([
      _preset('default', 25, isDefault: true),
      _preset('short', 10),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

FocusPresetItem _preset(String id, int minutes, {bool isDefault = false}) =>
    FocusPresetItem(
      id: id,
      userId: 'user',
      name: id,
      workSeconds: minutes * 60,
      shortBreakSeconds: 5 * 60,
      longBreakSeconds: 15 * 60,
      intervalsBeforeLongBreak: 4,
      autoStartBreaks: false,
      autoStartWork: false,
      allowPause: true,
      strictMode: false,
      isDefault: isDefault,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
