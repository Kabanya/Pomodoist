import 'package:pomodoist/data/repositories/projects/project_repository.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';
import 'package:pomodoist/domain/models/tasks/task_focus_estimate.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/utils/result.dart';

/// Coordinates the task patch, project resolution and move a Quick Add title
/// edit can express. The patch and the move are separate repository calls, so a
/// move failure leaves an already committed patch in place. A retry resolves an
/// existing project name through [ProjectRepository.createProject] instead of
/// creating a duplicate.
class EditTaskTitleUseCase {
  const EditTaskTitleUseCase({
    required QuickAddParser parser,
    required TaskRepository taskRepository,
    required ProjectRepository projectRepository,
  }) : _parser = parser,
       _taskRepository = taskRepository,
       _projectRepository = projectRepository;

  final QuickAddParser _parser;
  final TaskRepository _taskRepository;
  final ProjectRepository _projectRepository;

  Future<Result<void>> call(
    TaskItem task,
    String input, {
    required DateTime now,
    required FocusPresetItem? focusPreset,
  }) => Result.capture<void>(() async {
    final parsed = _parser.parse(
      input,
      now: now,
      defaultDate: task.schedule?.displayDate,
    );
    final content = parsed.content.isEmpty ? task.content : parsed.content;
    var schedule = parsed.dueDate != null || parsed.schedule?.isTimed == true
        ? parsed.schedule
        : null;
    if (parsed.dueDate != null && schedule?.isAllDay == true) {
      schedule = task.schedule?.moveToDate(parsed.dueDate!) ?? schedule;
    }
    final estimatedFocusIntervals = estimateFocusIntervalsForTaskDuration(
      schedule: parsed.schedule,
      durationSeconds: null,
      explicitEstimate: parsed.estimatedFocusIntervals,
      preset: focusPreset,
    );
    final patch = UpdateTaskPatch(
      content: content == task.content ? null : content,
      priority: parsed.priority,
      schedule: schedule,
      dueDate: schedule == null ? parsed.dueDate : null,
      estimatedFocusIntervals: estimatedFocusIntervals,
      labelNames: parsed.labels.isEmpty ? null : parsed.labels,
    );
    final shouldUpdateTask =
        patch.content != null ||
        patch.priority != null ||
        patch.schedule != null ||
        patch.dueDate != null ||
        patch.estimatedFocusIntervals != null ||
        patch.labelNames != null;
    final shouldMoveTask = parsed.project != null;
    if (!shouldUpdateTask && !shouldMoveTask) return;
    if (shouldUpdateTask) {
      (await _taskRepository.updateTask(task.id, patch)).getOrThrow();
    }
    final project = parsed.project;
    if (project != null) {
      final projectId = (await _projectRepository.createProject(
        project,
      )).getOrThrow();
      (await _taskRepository.moveTask(
        task.id,
        projectId: projectId,
      )).getOrThrow();
    }
  });
}
