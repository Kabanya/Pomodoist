import '../features/tasks/domain/task_models.dart';

enum TaskTimeState { completed, focused, future, current, overdue }

enum TaskTimeDisplayMode {
  smart('smart'),
  range('range'),
  startOnly('startOnly');

  const TaskTimeDisplayMode(this.storageValue);

  final String storageValue;

  static TaskTimeDisplayMode fromStorageValue(String? value) {
    return switch (value) {
      'range' => TaskTimeDisplayMode.range,
      'startOnly' => TaskTimeDisplayMode.startOnly,
      _ => TaskTimeDisplayMode.smart,
    };
  }
}

TaskTimeState classifyTaskTimeState({
  required bool isCompleted,
  required String taskId,
  required TaskSchedule schedule,
  required DateTime now,
  String? activeFocusTaskId,
}) {
  if (isCompleted) {
    return TaskTimeState.completed;
  }
  if (activeFocusTaskId == taskId) {
    return TaskTimeState.focused;
  }
  final currentTime = now.toUtc();
  if (currentTime.isBefore(schedule.start!)) {
    return TaskTimeState.future;
  }
  if (currentTime.isBefore(schedule.end!)) {
    return TaskTimeState.current;
  }
  return TaskTimeState.overdue;
}

bool shouldShowTaskTimeRange(
  TaskSchedule schedule,
  TaskTimeDisplayMode displayMode, {
  required int defaultTimedBlockMinutes,
}) {
  return switch (displayMode) {
    TaskTimeDisplayMode.range => true,
    TaskTimeDisplayMode.startOnly => false,
    TaskTimeDisplayMode.smart =>
      schedule.duration!.inMinutes != defaultTimedBlockMinutes,
  };
}
