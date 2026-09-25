import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/view_models/task_selection_view_model.dart';
import 'package:pomodoist/domain/use_cases/tasks/task_scheduling.dart';
import 'package:pomodoist/utils/clock.dart';
import 'package:pomodoist/utils/result.dart';

void main() {
  test(
    'selection can start empty and clear schedules once without deleting tasks',
    () async {
      final repository = _FakeTaskRepository()..failUpdates.add('b');
      final container = _container(repository: repository);
      addTearDown(container.dispose);
      final selection = container.read(
        taskSelectionViewModelProvider(Object()).notifier,
      );
      final a = _task(
        'a',
        schedule: TaskSchedule.allDay(DateTime(2026, 9, 25)),
      );
      final b = _task(
        'b',
        schedule: TaskSchedule.allDay(DateTime(2026, 9, 26)),
      );
      selection.updateVisible([a, a, b]);
      selection.begin();
      expect(selection.active, isTrue);
      expect(selection.selectedIds, isEmpty);
      selection.toggleAll();
      expect(selection.selectedIds, {'a', 'b'});
      final failed = await selection.schedule(
        selection.selectedTasks,
        const TaskDueResult.clear(),
      );
      expect(repository.clearedScheduleIds, ['a']);
      expect(repository.deletedIds, isEmpty);
      expect(failed, ['b']);
      selection.retainVisible(failed);
      expect(selection.selectedIds, {'b'});
      selection.updateVisible([a]);
      expect(selection.active, isFalse);
    },
  );

  test(
    'screen identities keep selection independent and share persisted values',
    () async {
      final projects = StreamController<List<ProjectItem>>();
      addTearDown(projects.close);
      final container = _container(projects: projects.stream);
      addTearDown(container.dispose);
      final firstIdentity = Object();
      final secondIdentity = Object();
      final firstListener = container.listen(
        taskSelectionViewModelProvider(firstIdentity),
        (_, _) {},
        fireImmediately: true,
      );
      final secondListener = container.listen(
        taskSelectionViewModelProvider(secondIdentity),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(firstListener.close);
      addTearDown(secondListener.close);
      final first = container.read(
        taskSelectionViewModelProvider(firstIdentity).notifier,
      );
      final second = container.read(
        taskSelectionViewModelProvider(secondIdentity).notifier,
      );
      final tasks = [_task('a'), _task('b')];
      first.updateVisible(tasks);
      second.updateVisible(tasks);

      first.begin('a');
      first.toggle('b');
      expect(first.active, isTrue);
      expect(first.selectedIds, {'a', 'b'});
      expect(second.active, isFalse);
      expect(second.selectedIds, isEmpty);

      first.toggleAll();
      expect(first.selectedIds, isEmpty);
      first.toggleAll();
      expect(first.selectedIds, {'a', 'b'});
      first.toggle('a');
      expect(first.selectedIds, {'b'});
      expect(first.active, isTrue);

      projects.add([_project('p1')]);
      await pumpEventQueue();
      expect(
        container
            .read(taskSelectionViewModelProvider(firstIdentity))
            .projects
            .single
            .id,
        'p1',
      );
      expect(
        container
            .read(taskSelectionViewModelProvider(secondIdentity))
            .projects
            .single
            .id,
        'p1',
      );
      expect(first.selectedIds, {'b'});
      expect(first.active, isTrue);
      expect(second.selectedIds, isEmpty);

      first.clear();
      expect(first.active, isFalse);
      expect(first.selectedIds, isEmpty);
    },
  );

  test(
    'a pending dialog resolves bulk targets against current visible ids',
    () async {
      final repository = _FakeTaskRepository();
      final container = _container(repository: repository);
      addTearDown(container.dispose);
      final selection = container.read(
        taskSelectionViewModelProvider(Object()).notifier,
      );
      selection.updateVisible([_task('a'), _task('b')]);
      selection.begin('a');
      selection.toggle('b');
      expect(selection.selectedIds, {'a', 'b'});

      // The task list rebuilds while the dialog is open: b is gone.
      selection.updateVisible([_task('a')]);
      expect(selection.selectedIds, {'a'});

      final failed = await selection.setPriority({'a', 'b'}, 2);
      expect(failed, isEmpty);
      expect(repository.priorityIds, ['a']);

      final moved = await selection.setProject([
        _task('a'),
        _task('b'),
      ], 'project-2');
      expect(moved, isEmpty);
      expect(repository.movedIds, ['a']);
    },
  );

  test('a pending move uses live project metadata', () async {
    final repository = _FakeTaskRepository();
    final container = _container(repository: repository);
    addTearDown(container.dispose);
    final selection = container.read(
      taskSelectionViewModelProvider(Object()).notifier,
    );
    final stale = _task('a');
    selection.updateVisible([stale]);
    selection.begin('a');
    selection.updateVisible([_task('a', projectId: 'destination')]);
    await selection.setProject([stale], 'destination');
    expect(repository.clearedSections, [false]);
  });

  test('a bulk action skips rows removed while it is pending', () async {
    final repository = _FakeTaskRepository();
    final container = _container(repository: repository);
    addTearDown(container.dispose);
    final selection = container.read(
      taskSelectionViewModelProvider(Object()).notifier,
    );
    selection.updateVisible([_task('a'), _task('b')]);
    selection.begin('a');
    selection.toggle('b');

    repository.updateGate = Completer<void>();
    final pending = selection.setPriority({'a', 'b'}, 3);
    expect(selection.pending, isTrue);
    selection.updateVisible([_task('a')]);
    expect(selection.selectedIds, {'a'});

    repository.updateGate!.complete();
    final failed = await pending;
    expect(failed, isEmpty);
    expect(repository.priorityIds, ['a']);
    expect(selection.pending, isFalse);
  });

  test('partial failures are reported and can be retained', () async {
    final repository = _FakeTaskRepository()
      ..failUpdates.add('b')
      ..failCompletes.add('b');
    final container = _container(repository: repository);
    addTearDown(container.dispose);
    final selection = container.read(
      taskSelectionViewModelProvider(Object()).notifier,
    );
    final tasks = [_task('a'), _task('b')];
    selection.updateVisible(tasks);
    selection.begin('a');
    selection.toggle('b');

    final failed = await selection.setPriority({'a', 'b'}, 1);
    expect(failed, ['b']);
    selection.retainVisible(failed);
    expect(selection.selectedIds, {'b'});
    expect(selection.active, isTrue);
    expect(repository.priorityIds, ['a']);

    selection.begin('a');
    selection.toggle('b');
    final completed = await selection.setCompleted({'a', 'b'}, completed: true);
    expect(completed.succeeded, ['a']);
    expect(completed.failed, ['b']);
    expect(completed.tasks.map((task) => task.id), ['a']);
    expect(repository.completedIds, ['a']);
  });

  test(
    'delete reports failed ids and batches for mixed recurring rows',
    () async {
      final ordinary = _task('ordinary');
      final recurring = _task(
        'recurring',
        schedule: TaskSchedule.allDay(
          DateTime(2026, 9, 20),
          recurrenceSeriesId: 'series',
        ),
      );
      final repository = _FakeTaskRepository();
      final container = _container(repository: repository);
      addTearDown(container.dispose);
      final selection = container.read(
        taskSelectionViewModelProvider(Object()).notifier,
      );
      selection.updateVisible([ordinary, recurring]);
      selection.begin('ordinary');
      selection.toggle('recurring');

      final deleted = await selection.delete([
        ordinary,
        ordinary,
        recurring,
        recurring,
      ], includeFollowing: true);
      expect(deleted.failed, isEmpty);
      expect(deleted.batches, hasLength(2));
      expect(repository.deletedIds, ['ordinary']);
      expect(repository.recurringDeletedIds, ['recurring']);
      expect(repository.recurringFollowing, [true]);
      // Undo must work after deleted cards have disappeared from the calendar.
      selection.updateVisible([]);
      final restored = await selection.restore(deleted.batches);
      expect(restored.ids, {'ordinary', 'recurring'});
      expect(restored.failures, 0);
      expect(repository.restoredIds, ['ordinary', 'recurring']);

      repository.failDeletes.add('ordinary-2');
      final failed = _task('ordinary-2');
      selection.updateVisible([failed, recurring]);
      selection.begin(failed.id);
      final partial = await selection.delete([
        failed,
        recurring,
      ], includeFollowing: false);
      expect(partial.failed, ['ordinary-2']);
      expect(partial.batches.single.taskIds, {'recurring'});
    },
  );
}

ProviderContainer _container({
  _FakeTaskRepository? repository,
  Stream<List<ProjectItem>>? projects,
}) => ProviderContainer(
  overrides: [
    taskRepositoryProvider.overrideWithValue(
      repository ?? _FakeTaskRepository(),
    ),
    projectsProvider.overrideWith(
      (ref) => projects ?? Stream.value(const <ProjectItem>[]),
    ),
    labelsProvider.overrideWith((ref) => Stream.value(const <LabelItem>[])),
    clockProvider.overrideWithValue(FixedClock(DateTime(2026, 9, 20, 9))),
  ],
);

TaskItem _task(
  String id, {
  TaskSchedule? schedule,
  String projectId = 'inbox',
}) => TaskItem(
  id: id,
  userId: 'user',
  content: id,
  projectId: projectId,
  priority: 4,
  status: 'open',
  completedFocusIntervals: 0,
  totalFocusSeconds: 0,
  orderKey: id,
  isDeleted: false,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  dueJson: schedule?.toJsonString(),
);

ProjectItem _project(String id) => ProjectItem(
  id: id,
  userId: 'user',
  name: id,
  orderKey: id,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _FakeTaskRepository implements TaskRepository {
  final List<String> priorityIds = [];
  final List<String> clearedScheduleIds = [];
  final List<String> labelIds = [];
  final List<String> movedIds = [];
  final List<bool> clearedSections = [];
  final List<String> completedIds = [];
  final List<String> uncompletedIds = [];
  final List<String> deletedIds = [];
  final List<String> recurringDeletedIds = [];
  final List<bool> recurringFollowing = [];
  final List<String> restoredIds = [];
  final Set<String> failUpdates = {};
  final Set<String> failCompletes = {};
  final Set<String> failDeletes = {};
  Completer<void>? updateGate;

  @override
  Future<Result<void>> updateTask(String id, UpdateTaskPatch patch) =>
      Result.capture(() async {
        final gate = updateGate;
        if (gate != null) await gate.future;
        if (failUpdates.contains(id)) {
          throw StateError('update $id failed');
        }
        if (patch.clearSchedule) clearedScheduleIds.add(id);
        if (patch.priority != null) priorityIds.add(id);
        if (patch.labelNames != null) labelIds.add(id);
      });

  @override
  Future<Result<void>> moveTask(
    String id, {
    String? projectId,
    String? sectionId,
    bool clearSectionId = false,
    String? parentId,
    bool clearParentId = false,
    String? orderKey,
  }) => Result.capture(() async {
    movedIds.add(id);
    clearedSections.add(clearSectionId);
  });

  @override
  Future<Result<void>> completeTask(String id) => Result.capture(() async {
    if (failCompletes.contains(id)) {
      throw StateError('complete $id failed');
    }
    completedIds.add(id);
  });

  @override
  Future<Result<void>> uncompleteTask(String id) => Result.capture(() async {
    if (failCompletes.contains(id)) {
      throw StateError('uncomplete $id failed');
    }
    uncompletedIds.add(id);
  });

  @override
  Stream<TaskItem?> watchTask(String id) => Stream<TaskItem?>.value(_task(id));

  @override
  Future<Result<List<String>>> duplicateTasks(
    Set<String> taskIds, {
    required bool includeSubtasks,
  }) => Result.capture(() async => taskIds.toList());

  @override
  Future<Result<DeletedTaskBatch>> deleteTasks(Set<String> ids) =>
      Result.capture(() async {
        if (ids.any(failDeletes.contains)) {
          throw StateError('delete failed');
        }
        deletedIds.addAll(ids);
        return DeletedTaskBatch(
          taskIds: {...ids},
          undoUntil: DateTime.utc(2026),
        );
      });

  @override
  Future<Result<DeletedTaskBatch>> deleteRecurringOccurrence(
    String id, {
    required bool includeFollowing,
  }) => Result.capture(() async {
    recurringDeletedIds.add(id);
    recurringFollowing.add(includeFollowing);
    return DeletedTaskBatch(taskIds: {id}, undoUntil: DateTime.utc(2026));
  });

  @override
  Future<Result<bool>> restoreDeletedTasks(DeletedTaskBatch batch) =>
      Result.capture(() async {
        restoredIds.addAll(batch.taskIds);
        return true;
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
