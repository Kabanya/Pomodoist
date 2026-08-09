import '../../focus/domain/focus_models.dart';
import '../../tasks/domain/task_focus_estimate.dart';
import '../../tasks/domain/task_models.dart';
import '../domain/quick_add_parser.dart';

class QuickAddService {
  QuickAddService({
    required QuickAddParser parser,
    required TaskRepository taskRepository,
    required ProjectRepository projectRepository,
    FocusPresetItem? focusPreset,
    Future<FocusPresetItem?> Function()? focusPresetProvider,
  }) : _parser = parser,
       _taskRepository = taskRepository,
       _projectRepository = projectRepository,
       _focusPreset = focusPreset,
       _focusPresetProvider = focusPresetProvider;

  final QuickAddParser _parser;
  final TaskRepository _taskRepository;
  final ProjectRepository _projectRepository;
  final FocusPresetItem? _focusPreset;
  final Future<FocusPresetItem?> Function()? _focusPresetProvider;

  Future<String> createTask(
    String input, {
    String? description,
    String? parentId,
    String? projectId,
    String? sectionId,
    int? priority,
    DateTime? defaultDate,
    TaskSchedule? defaultSchedule,
    String? kanbanStatusId,
  }) async {
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
    );
    return task.id;
  }

  Future<({String id, String? projectId, String? sectionId})>
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
  }) async {
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
    );
    return (
      id: await _taskRepository.createTask(context.input),
      projectId: context.projectId,
      sectionId: context.sectionId,
    );
  }

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
  ) async {
    final parsed = _parser.parse(input, defaultDate: defaultDate);
    if (parsed.content.isEmpty) {
      throw ArgumentError.value(input, 'input', 'Task content is empty');
    }
    final cleanedDescription = description?.trim();
    final explicitProjectId = parsed.project == null
        ? null
        : await _projectRepository.createProject(parsed.project!);
    final taskProjectId = explicitProjectId ?? projectId;
    final taskSectionId = explicitProjectId == null ? sectionId : null;
    final effectiveSchedule =
        parsed.schedule ?? (parsed.dueDate == null ? defaultSchedule : null);
    final focusPreset = _focusPreset ?? await _focusPresetProvider?.call();
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
