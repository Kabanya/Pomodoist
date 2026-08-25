import '../features/tasks/domain/task_models.dart';
import '../l10n/app_localizations.dart';

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
      schedule.duration != Duration(minutes: defaultTimedBlockMinutes),
  };
}

TaskTimeState? taskTimeStateForTask({
  required TaskItem task,
  required DateTime now,
  String? activeFocusTaskId,
}) {
  final schedule = task.schedule;
  if (schedule == null || !schedule.isTimed) {
    return null;
  }
  return classifyTaskTimeState(
    isCompleted: task.isCompleted,
    taskId: task.id,
    schedule: schedule,
    now: now,
    activeFocusTaskId: activeFocusTaskId,
  );
}

String taskTimeStatusLabel(AppLocalizations l10n, TaskTimeState state) {
  return switch (state) {
    TaskTimeState.future => l10n.taskTimeStatusFuture,
    TaskTimeState.focused => l10n.taskTimeStatusFocused,
    TaskTimeState.current => l10n.taskTimeStatusCurrent,
    TaskTimeState.overdue => l10n.taskTimeStatusOverdue,
    TaskTimeState.completed => l10n.taskTimeStatusCompleted,
  };
}
