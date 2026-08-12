import '../../focus/domain/focus_models.dart';
import 'task_models.dart';

int? estimateFocusIntervalsForTaskDuration({
  required TaskSchedule? schedule,
  required int? durationSeconds,
  required int? explicitEstimate,
  required FocusPresetItem? preset,
}) {
  if (explicitEstimate != null) {
    return explicitEstimate;
  }
  final duration =
      schedule?.duration ??
      (durationSeconds == null ? null : Duration(seconds: durationSeconds));
  if (duration == null || preset == null) {
    return null;
  }
  return estimateFocusIntervalsForDuration(duration: duration, preset: preset);
}

int? targetFocusIntervalsForTask(TaskItem task, FocusPresetItem? preset) {
  return estimateFocusIntervalsForTaskDuration(
    schedule: task.schedule,
    durationSeconds: task.durationSeconds,
    explicitEstimate: task.estimatedFocusIntervals,
    preset: preset,
  );
}
