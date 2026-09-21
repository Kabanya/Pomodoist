import 'package:pomodoist/data/repositories/tasks/task_repository.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/utils/result.dart';

import 'strict_fake.dart';

typedef DuplicateTasksCall = ({Set<String> taskIds, bool includeSubtasks});

typedef MoveTaskCall = ({
  String id,
  String? projectId,
  String? sectionId,
  bool clearSectionId,
  String? parentId,
  bool clearParentId,
  String? orderKey,
});

typedef PlaceTaskOnTimelineCall = ({
  String id,
  TaskSchedule schedule,
  String projectId,
});

typedef DeleteRecurringOccurrenceCall = ({String id, bool includeFollowing});

typedef ApplyRemoteCalendarPatchCall = ({
  String id,
  RemoteCalendarTaskPatch patch,
});

/// Configurable [TaskRepository] double.
///
/// Every method has a working default, so a test only has to set the fields it
/// cares about. Calls are appended to the matching recording list, and a
/// `Result`-returning method returns its `<method>Error` failure when that field
/// is non-null.
class FakeTaskRepository extends StrictFake implements TaskRepository {
  final watchedQueries = <TaskQuery>[];
  final watchedIds = <String>[];
  final created = <CreateTaskInput>[];
  final duplicated = <DuplicateTasksCall>[];
  final updatedIds = <String>[];
  final updatedPatches = <UpdateTaskPatch>[];
  final materializedNow = <DateTime?>[];
  final moved = <MoveTaskCall>[];
  final placedOnTimeline = <PlaceTaskOnTimelineCall>[];
  final completed = <String>[];
  final uncompleted = <String>[];
  final deleted = <String>[];
  final deletedMany = <Set<String>>[];
  final deletedRecurringOccurrences = <DeleteRecurringOccurrenceCall>[];
  final restored = <DeletedTaskBatch>[];
  final focusAggregateIds = <String>[];
  final createdFromCalendar = <RemoteCalendarTaskInput>[];
  final appliedRemoteCalendarPatches = <ApplyRemoteCalendarPatchCall>[];

  List<TaskItem> tasks = const [];
  TaskItem? task;
  String createTaskId = 'task-1';
  List<String> duplicateTaskIds = const [];
  DeletedTaskBatch deleteTaskBatch = DeletedTaskBatch(
    taskIds: const {},
    undoUntil: DateTime.utc(2026),
  );
  DeletedTaskBatch deleteTasksBatch = DeletedTaskBatch(
    taskIds: const {},
    undoUntil: DateTime.utc(2026),
  );
  DeletedTaskBatch deleteRecurringOccurrenceBatch = DeletedTaskBatch(
    taskIds: const {},
    undoUntil: DateTime.utc(2026),
  );
  bool restoreDeletedTasksValue = true;
  String createTaskFromCalendarId = 'task-1';

  Object? createTaskError;
  Object? duplicateTasksError;
  Object? updateTaskError;
  Object? materializeDueRecurringTasksError;
  Object? moveTaskError;
  Object? placeTaskOnTimelineError;
  Object? completeTaskError;
  Object? uncompleteTaskError;
  Object? deleteTaskError;
  Object? deleteTasksError;
  Object? deleteRecurringOccurrenceError;
  Object? restoreDeletedTasksError;
  Object? updateFocusAggregatesError;
  Object? createTaskFromCalendarError;
  Object? applyRemoteCalendarPatchError;

  @override
  Stream<List<TaskItem>> watchTasks(TaskQuery query) {
    watchedQueries.add(query);
    return Stream.value(tasks);
  }

  @override
  Stream<TaskItem?> watchTask(String id) {
    watchedIds.add(id);
    return Stream.value(task);
  }

  @override
  Future<Result<String>> createTask(CreateTaskInput input) async {
    created.add(input);
    final error = createTaskError;
    if (error != null) {
      return Result.error(error, StackTrace.current);
    }
    return Result.ok(createTaskId);
  }

  @override
  Future<Result<List<String>>> duplicateTasks(
    Set<String> taskIds, {
    required bool includeSubtasks,
  }) async {
    duplicated.add((taskIds: taskIds, includeSubtasks: includeSubtasks));
    final error = duplicateTasksError;
    if (error != null) {
      return Result.error(error, StackTrace.current);
    }
    return Result.ok(duplicateTaskIds);
  }

  @override
  Future<Result<void>> updateTask(String id, UpdateTaskPatch patch) async {
    updatedIds.add(id);
    updatedPatches.add(patch);
    final error = updateTaskError;
    if (error != null) {
      return Result.error(error, StackTrace.current);
    }
    return Result.ok(null);
  }

  @override
  Future<Result<void>> materializeDueRecurringTasks({DateTime? now}) async {
    materializedNow.add(now);
    final error = materializeDueRecurringTasksError;
    if (error != null) {
      return Result.error(error, StackTrace.current);
    }
    return Result.ok(null);
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
    moved.add((
      id: id,
      projectId: projectId,
      sectionId: sectionId,
      clearSectionId: clearSectionId,
      parentId: parentId,
      clearParentId: clearParentId,
      orderKey: orderKey,
    ));
    final error = moveTaskError;
    if (error != null) {
      return Result.error(error, StackTrace.current);
    }
    return Result.ok(null);
  }

  @override
  Future<Result<void>> placeTaskOnTimeline(
    String id, {
    required TaskSchedule schedule,
    required String projectId,
  }) async {
    placedOnTimeline.add((id: id, schedule: schedule, projectId: projectId));
    final error = placeTaskOnTimelineError;
    if (error != null) {
      return Result.error(error, StackTrace.current);
    }
    return Result.ok(null);
  }

  @override
  Future<Result<void>> completeTask(String id) async {
    completed.add(id);
    final error = completeTaskError;
    if (error != null) {
      return Result.error(error, StackTrace.current);
    }
    return Result.ok(null);
  }

  @override
  Future<Result<void>> uncompleteTask(String id) async {
    uncompleted.add(id);
    final error = uncompleteTaskError;
    if (error != null) {
      return Result.error(error, StackTrace.current);
    }
    return Result.ok(null);
  }

  @override
  Future<Result<DeletedTaskBatch>> deleteTask(String id) async {
    deleted.add(id);
    final error = deleteTaskError;
    if (error != null) {
      return Result.error(error, StackTrace.current);
    }
    return Result.ok(deleteTaskBatch);
  }

  @override
  Future<Result<DeletedTaskBatch>> deleteTasks(Set<String> ids) async {
    deletedMany.add(ids);
    final error = deleteTasksError;
    if (error != null) {
      return Result.error(error, StackTrace.current);
    }
    return Result.ok(deleteTasksBatch);
  }

  @override
  Future<Result<DeletedTaskBatch>> deleteRecurringOccurrence(
    String id, {
    required bool includeFollowing,
  }) async {
    deletedRecurringOccurrences.add((
      id: id,
      includeFollowing: includeFollowing,
    ));
    final error = deleteRecurringOccurrenceError;
    if (error != null) {
      return Result.error(error, StackTrace.current);
    }
    return Result.ok(deleteRecurringOccurrenceBatch);
  }

  @override
  Future<Result<bool>> restoreDeletedTasks(DeletedTaskBatch batch) async {
    restored.add(batch);
    final error = restoreDeletedTasksError;
    if (error != null) {
      return Result.error(error, StackTrace.current);
    }
    return Result.ok(restoreDeletedTasksValue);
  }

  @override
  Future<Result<void>> updateFocusAggregates(String id) async {
    focusAggregateIds.add(id);
    final error = updateFocusAggregatesError;
    if (error != null) {
      return Result.error(error, StackTrace.current);
    }
    return Result.ok(null);
  }

  @override
  Future<Result<String>> createTaskFromCalendar(
    RemoteCalendarTaskInput input,
  ) async {
    createdFromCalendar.add(input);
    final error = createTaskFromCalendarError;
    if (error != null) {
      return Result.error(error, StackTrace.current);
    }
    return Result.ok(createTaskFromCalendarId);
  }

  @override
  Future<Result<void>> applyRemoteCalendarPatch(
    String id,
    RemoteCalendarTaskPatch patch,
  ) async {
    appliedRemoteCalendarPatches.add((id: id, patch: patch));
    final error = applyRemoteCalendarPatchError;
    if (error != null) {
      return Result.error(error, StackTrace.current);
    }
    return Result.ok(null);
  }
}
