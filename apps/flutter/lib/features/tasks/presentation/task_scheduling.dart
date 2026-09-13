import '../domain/task_models.dart';

class TaskDueResult {
  const TaskDueResult.schedule(TaskSchedule this.schedule) : clear = false;
  const TaskDueResult.clear() : schedule = null, clear = true;

  final TaskSchedule? schedule;
  final bool clear;
}

UpdateTaskPatch taskDuePatch(TaskItem task, TaskDueResult result) {
  if (result.clear) return const UpdateTaskPatch(clearSchedule: true);
  final requested = result.schedule!;
  final existing = task.schedule;
  var schedule = requested.isAllDay
      ? existing?.moveToDate(requested.date!) ?? requested
      : requested;
  schedule = existing?.recurrence != null
      ? schedule.withRecurrence(existing!.recurrence)
      : schedule.withRecurrenceSeriesId(existing?.recurrenceSeriesId);
  return UpdateTaskPatch(schedule: schedule);
}

/// Apply independently so a failed task does not prevent the rest being moved.
/// A dismissed panel never writes anything.
Future<List<String>> applyTaskDueResult(
  Iterable<TaskItem> tasks,
  TaskDueResult? result, {
  required Future<void> Function(String, UpdateTaskPatch) updateTask,
}) async {
  if (result == null) return const [];
  final failed = <String>[];
  for (final task in tasks.toList()) {
    try {
      await updateTask(task.id, taskDuePatch(task, result));
    } catch (_) {
      failed.add(task.id);
    }
  }
  return failed;
}
