import 'package:pomodoist/data/repositories/focus/focus_repository.dart';
import 'package:pomodoist/utils/result.dart';
import 'package:pomodoist/data/repositories/projects/project_repository.dart';
import 'package:pomodoist/data/repositories/planning/quick_add_hint_repository.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/models/tasks/task_focus_estimate.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';

class QuickAddUseCase {
  QuickAddUseCase({
    required QuickAddParser parser,
    required TaskRepository taskRepository,
    required ProjectRepository projectRepository,
    FocusPresetItem? focusPreset,
    DateTime Function()? now,
    FocusRepository? focusRepository,
    String? Function()? selectedFocusPresetId,
    QuickAddHintRepository? hints,
  }) : _now = now ?? DateTime.now,
       _parser = parser,
       _taskRepository = taskRepository,
       _projectRepository = projectRepository,
       _focusPreset = focusPreset,
       _focusRepository = focusRepository,
       _selectedFocusPresetId = selectedFocusPresetId,
       _hints = hints;

  final DateTime Function() _now;
  final QuickAddParser _parser;
  final TaskRepository _taskRepository;
  final ProjectRepository _projectRepository;
  final FocusPresetItem? _focusPreset;
  final FocusRepository? _focusRepository;
  final String? Function()? _selectedFocusPresetId;
  final QuickAddHintRepository? _hints;

  Future<Result<String>> createTask(
    String input, {
    String? description,
    String? parentId,
    String? projectId,
    String? sectionId,
    int? priority,
    DateTime? defaultDate,
    TaskSchedule? defaultSchedule,
    String? kanbanStatusId,
    String? labelId,
    bool recordCreation = true,
  }) => Result.capture<String>(() async {
    final task = await createTaskWithContext(
      input,
      description: description,
      parentId: parentId,
      projectId: projectId,
      sectionId: sectionId,
      priority: priority,
      defaultDate: defaultDate,
      defaultSchedule: defaultSchedule,
      kanbanStatusId: kanbanStatusId,
      labelId: labelId,
      recordCreation: recordCreation,
    ).then((result) => result.getOrThrow());
    return task.id;
  });

  Future<Result<({String id, String? projectId, String? sectionId})>>
  createTaskWithContext(
    String input, {
    String? description,
    String? parentId,
    String? projectId,
    String? sectionId,
    int? priority,
    DateTime? defaultDate,
    TaskSchedule? defaultSchedule,
    String? kanbanStatusId,
    String? labelId,
    bool recordCreation = true,
  }) => Result.capture<({String id, String? projectId, String? sectionId})>(
    () async {
      final context = await _createTask(
        input,
        description,
        parentId,
        projectId,
        sectionId,
        priority,
        defaultDate,
        defaultSchedule,
        kanbanStatusId,
        labelId,
      );
      final id = await _taskRepository
          .createTask(context.input)
          .then((result) => result.getOrThrow());
      if (recordCreation) {
        try {
          await _hints?.recordUserTaskCreated();
        } catch (_) {
          // Hint bookkeeping is advisory and cannot fail a committed task.
        }
      }
      return (
        id: id,
        projectId: context.projectId,
        sectionId: context.sectionId,
      );
    },
  );

  Future<_QuickAddTaskContext> _createTask(
    String input,
    String? description,
    String? parentId,
    String? projectId,
    String? sectionId,
    int? priority,
    DateTime? defaultDate,
    TaskSchedule? defaultSchedule,
    String? kanbanStatusId,
    String? labelId,
  ) async {
    final parsed = _parser.parse(input, now: _now(), defaultDate: defaultDate);
    if (parsed.content.isEmpty) {
      throw ArgumentError.value(input, 'input', 'Task content is empty');
    }
    final cleanedDescription = description?.trim();
    final explicitProjectId = parsed.project == null
        ? null
        : await _projectRepository
              .createProject(parsed.project!)
              .then((result) => result.getOrThrow());
    final taskProjectId = explicitProjectId ?? projectId;
    final taskSectionId = explicitProjectId == null ? sectionId : null;
    final effectiveSchedule =
        parsed.schedule ?? (parsed.dueDate == null ? defaultSchedule : null);
    final focusRepository = _focusRepository;
    final focusPreset =
        _focusPreset ??
        (focusRepository == null
            ? null
            : selectedFocusPresetOrDefault(
                await focusRepository.watchPresets().first,
                _selectedFocusPresetId?.call(),
              ));
    final estimatedFocusIntervals = estimateFocusIntervalsForTaskDuration(
      schedule: effectiveSchedule,
      durationSeconds: null,
      explicitEstimate: parsed.estimatedFocusIntervals,
      preset: focusPreset,
    );
    return _QuickAddTaskContext(
      projectId: taskProjectId,
      sectionId: taskSectionId,
      input: CreateTaskInput(
        content: parsed.content,
        description: cleanedDescription == null || cleanedDescription.isEmpty
            ? null
            : cleanedDescription,
        projectId: taskProjectId,
        sectionId: taskSectionId,
        parentId: parentId,
        priority: parsed.priority ?? priority,
        labelNames: parsed.labels,
        schedule: effectiveSchedule,
        dueDate: effectiveSchedule == null ? parsed.dueDate : null,
        durationSeconds: effectiveSchedule?.duration?.inSeconds,
        estimatedFocusIntervals: estimatedFocusIntervals,
        kanbanStatusId: kanbanStatusId,
        labelId: labelId,
      ),
    );
  }
}

class _QuickAddTaskContext {
  const _QuickAddTaskContext({
    required this.input,
    required this.projectId,
    required this.sectionId,
  });

  final CreateTaskInput input;
  final String? projectId;
  final String? sectionId;
}
