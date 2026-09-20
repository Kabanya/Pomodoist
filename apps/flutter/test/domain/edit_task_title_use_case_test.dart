import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/projects/project_repository.dart';
import 'package:pomodoist/data/repositories/projects/project_repository_impl.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/use_cases/tasks/edit_task_title_use_case.dart';
import 'package:pomodoist/utils/result.dart';

void main() {
  const parser = QuickAddParser();
  final now = DateTime(2026, 9, 20, 12);
  final preset = FocusPresetItem(
    id: 'preset',
    userId: 'user',
    name: 'Preset',
    workSeconds: 1500,
    shortBreakSeconds: 300,
    longBreakSeconds: 900,
    intervalsBeforeLongBreak: 4,
    autoStartBreaks: false,
    autoStartWork: false,
    allowPause: true,
    strictMode: false,
    isDefault: true,
    createdAt: now,
    updatedAt: now,
  );

  test(
    'parses the title and quoted metadata, then patches before moving',
    () async {
      final events = <String>[];
      final tasks = _RecordingTaskRepository(events);
      final projects = _RecordingProjectRepository(events);
      final useCase = EditTaskTitleUseCase(
        parser: parser,
        taskRepository: tasks,
        projectRepository: projects,
      );

      final result = await useCase(
        _task(),
        'Renamed @"Deep Work" #"Team A" p2',
        now: now,
        focusPreset: preset,
      );

      expect(result, isA<Success<void>>());
      final (_, patch) = tasks.updates.single;
      expect(patch.content, 'Renamed');
      expect(patch.priority, 2);
      expect(patch.labelNames, ['Deep Work']);
      expect(patch.schedule, isNull);
      expect(patch.dueDate, isNull);
      expect(projects.createdNames, ['Team A']);
      expect(tasks.moves.single, ('task-1', 'project-1'));
      expect(events, ['update', 'create:Team A', 'move']);
    },
  );

  test('keeps a timed schedule and calculates its focus estimate', () async {
    final tasks = _RecordingTaskRepository(<String>[]);
    final useCase = EditTaskTitleUseCase(
      parser: parser,
      taskRepository: tasks,
      projectRepository: _RecordingProjectRepository(<String>[]),
    );

    final result = await useCase(
      _task(),
      'Renamed 14:00-15:00',
      now: now,
      focusPreset: preset,
    );

    expect(result, isA<Success<void>>());
    final (_, patch) = tasks.updates.single;
    expect(patch.schedule!.isTimed, isTrue);
    expect(patch.schedule!.start!.toLocal(), DateTime(2026, 9, 20, 14));
    expect(patch.schedule!.end!.toLocal(), DateTime(2026, 9, 20, 15));
    expect(patch.estimatedFocusIntervals, 2);
    expect(patch.dueDate, isNull);
    expect(tasks.moves, isEmpty);
  });

  test(
    'a bare date moves an existing timed block without rescheduling it',
    () async {
      final tasks = _RecordingTaskRepository(<String>[]);
      final useCase = EditTaskTitleUseCase(
        parser: parser,
        taskRepository: tasks,
        projectRepository: _RecordingProjectRepository(<String>[]),
      );
      final task = _task(
        schedule: TaskSchedule.timed(
          start: DateTime(2026, 9, 20, 9),
          end: DateTime(2026, 9, 20, 9, 30),
        ),
      );

      final result = await useCase(
        task,
        'Renamed 2026-09-25',
        now: now,
        focusPreset: preset,
      );

      expect(result, isA<Success<void>>());
      final (_, patch) = tasks.updates.single;
      expect(patch.schedule!.isTimed, isTrue);
      expect(patch.schedule!.start!.toLocal(), DateTime(2026, 9, 25, 9));
      expect(patch.schedule!.end!.toLocal(), DateTime(2026, 9, 25, 9, 30));
      expect(patch.dueDate, isNull);
      expect(patch.estimatedFocusIntervals, isNull);
      expect(tasks.moves, isEmpty);
    },
  );

  test('an explicit focus estimate applies without a schedule', () async {
    final tasks = _RecordingTaskRepository(<String>[]);
    final useCase = EditTaskTitleUseCase(
      parser: parser,
      taskRepository: tasks,
      projectRepository: _RecordingProjectRepository(<String>[]),
    );

    final result = await useCase(
      _task(),
      'Renamed 3p',
      now: now,
      focusPreset: preset,
    );

    expect(result, isA<Success<void>>());
    final (_, patch) = tasks.updates.single;
    expect(patch.content, 'Renamed');
    expect(patch.estimatedFocusIntervals, 3);
    expect(patch.schedule, isNull);
    expect(patch.dueDate, isNull);
  });

  test('empty input keeps the task untouched', () async {
    final events = <String>[];
    final tasks = _RecordingTaskRepository(events);
    final projects = _RecordingProjectRepository(events);
    final useCase = EditTaskTitleUseCase(
      parser: parser,
      taskRepository: tasks,
      projectRepository: projects,
    );

    final result = await useCase(_task(), '   ', now: now, focusPreset: preset);

    expect(result, isA<Success<void>>());
    expect(tasks.updates, isEmpty);
    expect(tasks.moves, isEmpty);
    expect(projects.createdNames, isEmpty);
    expect(events, isEmpty);
  });

  test('project creation failure keeps the committed title patch', () async {
    final events = <String>[];
    final tasks = _RecordingTaskRepository(events);
    final projects = _RecordingProjectRepository(events)..failNextCreate = true;
    final useCase = EditTaskTitleUseCase(
      parser: parser,
      taskRepository: tasks,
      projectRepository: projects,
    );

    final result = await useCase(
      _task(),
      'Renamed #Team',
      now: now,
      focusPreset: preset,
    );

    expect(result, isA<Failure<void>>());
    // Partial success: the task patch committed, the move never ran.
    expect(tasks.updates.single.$2.content, 'Renamed');
    expect(tasks.moves, isEmpty);
    expect(events, ['update', 'create:Team']);
  });

  test('a failed move retries without creating a second project', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.ensureSeedData();
    addTearDown(db.close);
    final events = <String>[];
    final tasks = _RecordingTaskRepository(events)..failNextMove = true;
    final projects = DriftProjectRepository(db, DriftOutboxService(db));
    final useCase = EditTaskTitleUseCase(
      parser: parser,
      taskRepository: tasks,
      projectRepository: projects,
    );

    final first = await useCase(
      _task(),
      'Renamed #Team',
      now: now,
      focusPreset: preset,
    );

    expect(first, isA<Failure<void>>());
    expect(tasks.updates, hasLength(1));
    expect(tasks.moves, hasLength(1));
    expect(await _projectsNamed(db, 'Team'), hasLength(1));

    final retry = await useCase(
      _task(),
      'Renamed #Team',
      now: now,
      focusPreset: preset,
    );

    expect(retry, isA<Success<void>>());
    expect(tasks.updates, hasLength(2));
    expect(tasks.moves, hasLength(2));
    expect(events, ['update', 'move', 'update', 'move']);
    expect(await _projectsNamed(db, 'Team'), hasLength(1));
  });
}

Future<List<ProjectRow>> _projectsNamed(AppDatabase db, String name) async {
  final rows = await db.select(db.projects).get();
  return rows.where((row) => row.name == name).toList();
}

TaskItem _task({TaskSchedule? schedule}) => TaskItem(
  id: 'task-1',
  userId: 'user',
  content: 'Old title',
  projectId: inboxProjectId,
  priority: 4,
  status: 'open',
  completedFocusIntervals: 0,
  totalFocusSeconds: 0,
  orderKey: '1',
  isDeleted: false,
  dueJson: schedule?.toJsonString(),
  createdAt: DateTime(2026, 9, 20),
  updatedAt: DateTime(2026, 9, 20),
);

class _RecordingTaskRepository implements TaskRepository {
  _RecordingTaskRepository(this.events);

  final List<String> events;
  final updates = <(String, UpdateTaskPatch)>[];
  final moves = <(String, String?)>[];
  bool failNextMove = false;

  @override
  Future<Result<void>> updateTask(String id, UpdateTaskPatch patch) async {
    events.add('update');
    updates.add((id, patch));
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> moveTask(
    String id, {
    String? projectId,
    String? sectionId,
    bool clearSectionId = false,
    String? parentId,
    bool clearParentId = false,
    String? orderKey,
  }) async {
    events.add('move');
    moves.add((id, projectId));
    if (failNextMove) {
      failNextMove = false;
      return Failure<void>(
        StateError('Injected move failure'),
        StackTrace.current,
      );
    }
    return const Success<void>(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _RecordingProjectRepository implements ProjectRepository {
  _RecordingProjectRepository(this.events);

  final List<String> events;
  final createdNames = <String>[];
  final resolvedIds = <String, String>{};
  bool failNextCreate = false;

  @override
  Future<Result<String>> createProject(
    String name, {
    String? color,
    String? parentId,
  }) => Result.capture<String>(() async {
    events.add('create:$name');
    createdNames.add(name);
    if (failNextCreate) {
      failNextCreate = false;
      throw StateError('Injected project creation failure');
    }
    final key = name.trim().toLowerCase();
    return resolvedIds.putIfAbsent(
      key,
      () => 'project-${resolvedIds.length + 1}',
    );
  });

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
