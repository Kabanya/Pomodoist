import 'package:pomodoist/utils/result.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

abstract interface class TaskRepository {
  Stream<List<TaskItem>> watchTasks(TaskQuery query);
  Stream<TaskItem?> watchTask(String id);
  Future<Result<String>> createTask(CreateTaskInput input);
  Future<Result<List<String>>> duplicateTasks(
    Set<String> taskIds, {
    required bool includeSubtasks,
  });
  Future<Result<void>> updateTask(String id, UpdateTaskPatch patch);
  Future<Result<void>> materializeDueRecurringTasks({DateTime? now});
  Future<Result<void>> moveTask(
    String id, {
    String? projectId,
    String? sectionId,
    bool clearSectionId = false,
    String? parentId,
    bool clearParentId = false,
    String? orderKey,
  });
  Future<Result<void>> placeTaskOnTimeline(
    String id, {
    required TaskSchedule schedule,
    required String projectId,
  });
  Future<Result<void>> completeTask(String id);
  Future<Result<void>> uncompleteTask(String id);
  Future<Result<DeletedTaskBatch>> deleteTask(String id);
  Future<Result<DeletedTaskBatch>> deleteTasks(Set<String> ids);
  Future<Result<DeletedTaskBatch>> deleteRecurringOccurrence(
    String id, {
    required bool includeFollowing,
  });
  Future<Result<bool>> restoreDeletedTasks(DeletedTaskBatch batch);
  Future<Result<void>> updateFocusAggregates(String id);
  Future<Result<String>> createTaskFromCalendar(RemoteCalendarTaskInput input);
  Future<Result<void>> applyRemoteCalendarPatch(
    String id,
    RemoteCalendarTaskPatch patch,
  );
}
