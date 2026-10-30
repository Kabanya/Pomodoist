import 'package:pomodoist/config/calendar_dependencies.dart';
import 'package:pomodoist/domain/models/files/file_attachment.dart';
import 'package:pomodoist/config/files_dependencies.dart';
import 'package:pomodoist/config/collaboration_dependencies.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'task_branch_rows.dart';
import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/config/task_focus_dependencies.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/tasks/task_focus_estimate.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository.dart';
import 'package:pomodoist/data/repositories/focus/focus_repository.dart';
import 'package:pomodoist/domain/models/tasks/task_time.dart';

typedef TaskDetailState = ({
  TaskDetailLayout layout,
  String? projectName,
  List<ProjectItem> projects,
  int? fileCount,
  int commentCount,
  AsyncValue<TaskItem?> task,
  bool calendarLinked,
  FocusPresetItem? preset,
  int? focusEstimate,
  TaskDetailFocusAction? focusAction,
  String? focusRunId,
});

enum TaskDetailFocusAction {
  startFocus,
  pause,
  pauseUnavailable,
  resume,
  startInterval,
}

TaskDetailFocusAction? taskDetailFocusAction({
  required String taskId,
  required FocusRunItem? run,
  required FocusIntervalItem? interval,
  bool allowPause = true,
}) {
  if (run?.taskId != taskId) return TaskDetailFocusAction.startFocus;
  if (interval?.runId != run!.id) return null;
  return switch (interval!.status) {
    'ready' => TaskDetailFocusAction.startInterval,
    'paused' => TaskDetailFocusAction.resume,
    'running' =>
      allowPause
          ? TaskDetailFocusAction.pause
          : TaskDetailFocusAction.pauseUnavailable,
    _ => null,
  };
}

Future<bool> performTaskDetailFocusAction(
  FocusRepository repository, {
  required String taskId,
  required String runId,
  required TaskDetailFocusAction action,
}) async {
  final run = await repository.watchActiveRun().first;
  final interval = await repository.watchActiveInterval().first;
  if (run?.id != runId || run?.taskId != taskId || interval?.runId != runId) {
    return false;
  }
  final result = switch (action) {
    TaskDetailFocusAction.pause when interval!.status == 'running' =>
      await repository.pauseActiveInterval(),
    TaskDetailFocusAction.resume when interval!.status == 'paused' =>
      await repository.resumeActiveInterval(),
    TaskDetailFocusAction.startInterval when interval!.status == 'ready' =>
      await repository.startReadyInterval(),
    _ => null,
  };
  if (result == null) return false;
  result.getOrThrow();
  return true;
}

final taskDetailFileCountProvider = StreamProvider.autoDispose
    .family<int, String>(
      (ref, taskId) =>
          ref
              .watch(filesRepositoryProvider)
              ?.watch(FileTarget(taskId: taskId))
              .map((files) => files.length) ??
          Stream.value(0),
    );

final taskDetailViewModelProvider = NotifierProvider.autoDispose
    .family<TaskDetailViewModel, TaskDetailState, String>(
      TaskDetailViewModel.new,
    );

class TaskDetailViewModel extends Notifier<TaskDetailState> {
  TaskDetailViewModel(this.taskId);
  final String taskId;
  late TaskRepository _tasks;
  bool _focusActionBusy = false;
  @override
  TaskDetailState build() {
    _tasks = ref.watch(taskRepositoryProvider);
    final task = ref.watch(taskProvider(taskId));
    final presets =
        ref.watch(focusPresetsProvider).value ?? const <FocusPresetItem>[];
    final preset = selectedFocusPresetOrDefault(
      presets,
      ref.watch(lastFocusPresetIdProvider),
    );
    final run = ref.watch(activeFocusRunProvider).value;
    final interval = ref.watch(activeFocusIntervalProvider).value;
    final activePreset = selectedFocusPresetOrDefault(presets, run?.presetId);
    String? projectName;
    for (final project
        in ref.watch(projectsProvider).value ?? <ProjectItem>[]) {
      if (project.id == task.value?.projectId) projectName = project.name;
    }
    final scopeId = task.value?.scopeId;
    final comments = scopeId == null
        ? null
        : ref
              .watch(
                collaborationCommentsProvider((
                  scopeId: scopeId,
                  taskId: taskId,
                )),
              )
              .value;
    return (
      projectName: projectName,
      projects: List.unmodifiable(
        (ref.watch(projectsProvider).value ?? const <ProjectItem>[]).where(
          (project) => _canSelectProject(task.value, project),
        ),
      ),
      fileCount: ref.watch(taskDetailFileCountProvider(taskId)).value,
      commentCount: comments?.length ?? 0,
      task: task,
      layout: ref.watch(taskPreferencesStateProvider).detailLayout,
      calendarLinked:
          (ref.watch(calendarLinksProvider(taskId)).value?.isNotEmpty ??
              false) ||
          ref.watch(googleCalendarLinkProvider(taskId)).value != null,
      preset: preset,
      focusEstimate: task.value == null
          ? null
          : targetFocusIntervalsForTask(task.value!, preset),
      focusAction: taskDetailFocusAction(
        taskId: taskId,
        run: run,
        interval: interval,
        allowPause: activePreset?.allowPause ?? true,
      ),
      focusRunId: run?.taskId == taskId ? run?.id : null,
    );
  }

  Future<TaskItem?> current() async {
    try {
      return await _tasks.watchTask(taskId).first;
    } catch (_) {
      return null;
    }
  }

  Future<void> setProject(String projectId) async {
    final task = await current();
    if (task == null || task.isDeleted || !task.canEdit) return;
    if (task.projectId == projectId) return;
    final projects = ref.read(projectsProvider).value ?? const <ProjectItem>[];
    if (!projects.any(
      (project) => project.id == projectId && _canSelectProject(task, project),
    )) {
      throw StateError('Project unavailable');
    }
    (await _tasks.moveTask(
      taskId,
      projectId: projectId,
      clearSectionId: true,
      clearParentId: task.parentId != null,
    )).getOrThrow();
  }

  bool _canSelectProject(TaskItem? task, ProjectItem project) =>
      task != null &&
      project.canEdit &&
      !project.isDeleted &&
      !project.isArchived &&
      project.scopeId == task.scopeId;

  Future<TaskItem?> complete() async {
    (await _tasks.completeTask(taskId)).getOrThrow();
    return current();
  }

  Future<TaskItem?> reopen() async {
    (await _tasks.uncompleteTask(taskId)).getOrThrow();
    return current();
  }

  Future<bool> startFocus(Future<bool> Function() confirmSwitch) async {
    final task = state.task.value;
    if (task == null || task.isDeleted || task.isCompleted) return false;
    return ref
        .read(taskFocusLauncherProvider)
        .open(task, preset: state.preset, confirmSwitch: confirmSwitch);
  }

  Future<bool> performFocusAction(
    TaskDetailFocusAction action,
    String runId,
  ) async {
    if (_focusActionBusy) return false;
    _focusActionBusy = true;
    try {
      return await performTaskDetailFocusAction(
        ref.read(focusRepositoryProvider),
        taskId: taskId,
        runId: runId,
        action: action,
      );
    } finally {
      _focusActionBusy = false;
    }
  }
}

typedef TaskEditorState = ({
  String draft,
  bool dirty,
  bool saving,
  bool failed,
});
final taskEditorViewModelProvider = NotifierProvider.autoDispose
    .family<TaskEditorViewModel, TaskEditorState, Object>(
      TaskEditorViewModel.new,
    );

class TaskEditorViewModel extends Notifier<TaskEditorState> {
  TaskEditorViewModel(this.identity);
  final Object identity;
  int? _accountGeneration;
  @override
  TaskEditorState build() {
    ref.listen(accountSessionProvider, (_, next) {
      _accountGeneration = next.value?.generation;
    }, fireImmediately: true);
    return (draft: '', dirty: false, saving: false, failed: false);
  }

  TaskEditorState _copy({
    String? draft,
    bool? dirty,
    bool? saving,
    bool? failed,
  }) => (
    draft: draft ?? state.draft,
    dirty: dirty ?? state.dirty,
    saving: saving ?? state.saving,
    failed: failed ?? state.failed,
  );

  void updateDraft(String value) {
    if (state.draft == value && state.dirty) return;
    state = _copy(draft: value, dirty: true);
  }

  Future<bool> saveTitle(TaskItem task, String next) async {
    if (state.saving) return false;
    final draft = next.trim();
    if (draft.isEmpty) {
      state = _copy(failed: false, dirty: false);
      return true;
    }
    if (draft == task.content.trim() && !state.failed) {
      state = _copy(draft: task.content, dirty: false, failed: false);
      return true;
    }
    state = _copy(draft: next, dirty: true, saving: true, failed: false);
    final useCase = ref.read(editTaskTitleUseCaseProvider);
    final now = ref.read(clockProvider).now().toLocal();
    final focusPreset = selectedFocusPresetOrDefault(
      ref.read(focusPresetsProvider).value ?? const [],
      ref.read(lastFocusPresetIdProvider),
    );
    final accountGeneration = ref
        .read(accountSessionProvider)
        .value
        ?.generation;
    var failed = false;
    try {
      (await useCase(
        task,
        draft,
        now: now,
        focusPreset: focusPreset,
      )).getOrThrow();
    } catch (_) {
      failed = true;
    }
    if (!ref.mounted) return !failed;
    final accountChanged =
        accountGeneration != null && accountGeneration != _accountGeneration;
    state = _copy(
      saving: false,
      failed: accountChanged ? false : failed,
      dirty: accountChanged ? false : failed,
    );
    return !failed;
  }

  Future<bool> saveDescription(TaskItem task, String value) async {
    if (state.saving) return false;
    final draft = value.trim();
    final persisted = (task.description ?? '').trim();
    if (draft == persisted && !state.failed) {
      state = _copy(draft: value, dirty: false, failed: false);
      return true;
    }
    state = _copy(draft: value, dirty: true, saving: true, failed: false);
    final taskRepository = ref.read(taskRepositoryProvider);
    var failed = false;
    try {
      (await taskRepository.updateTask(
        task.id,
        UpdateTaskPatch(
          description: draft.isEmpty ? null : draft,
          updateDescription: true,
        ),
      )).getOrThrow();
    } catch (_) {
      failed = true;
    }
    if (!ref.mounted) return !failed;
    final changedWhileSaving = state.draft != value;
    state = _copy(
      saving: false,
      failed: failed,
      dirty: failed || changedWhileSaving,
    );
    return !failed && !changedWhileSaving;
  }

  Future<bool> createSubtask(TaskItem task, String input) async {
    if (state.saving) return false;
    state = _copy(draft: input, dirty: true, saving: true, failed: false);
    var failed = false;
    try {
      final parsed = ref
          .read(quickAddParserProvider)
          .parse(input, now: ref.read(clockProvider).now().toLocal());
      if (parsed.content.isNotEmpty) {
        final focusPreset = selectedFocusPresetOrDefault(
          ref.read(focusPresetsProvider).value ?? const [],
          ref.read(lastFocusPresetIdProvider),
        );
        final estimatedFocusIntervals = estimateFocusIntervalsForTaskDuration(
          schedule: parsed.schedule,
          durationSeconds: null,
          explicitEstimate: parsed.estimatedFocusIntervals,
          isFocusEstimateManual: parsed.estimatedFocusIntervals != null,
          preset: focusPreset,
        );
        (await ref
                .read(taskRepositoryProvider)
                .createTask(
                  CreateTaskInput(
                    content: parsed.content,
                    projectId: task.projectId,
                    sectionId: task.sectionId,
                    parentId: task.id,
                    priority: parsed.priority,
                    labelNames: parsed.labels,
                    schedule: parsed.schedule,
                    dueDate: parsed.schedule == null ? parsed.dueDate : null,
                    durationSeconds: parsed.schedule?.duration?.inSeconds,
                    estimatedFocusIntervals: estimatedFocusIntervals,
                    isFocusEstimateManual:
                        parsed.estimatedFocusIntervals != null,
                  ),
                ))
            .getOrThrow();
      }
    } catch (_) {
      failed = true;
    }
    if (!ref.mounted) return !failed;
    state = _copy(
      saving: false,
      failed: failed,
      dirty: failed,
      draft: failed ? input : '',
    );
    return !failed;
  }
}

typedef TaskScheduleState = ({
  DateTime now,
  TaskTimeState? timeState,
  TaskTimeDisplayMode displayMode,
  int timedMinutes,
});
final taskScheduleViewModelProvider = NotifierProvider.autoDispose
    .family<TaskScheduleViewModel, TaskScheduleState, TaskItem>(
      TaskScheduleViewModel.new,
    );

class TaskScheduleViewModel extends Notifier<TaskScheduleState> {
  TaskScheduleViewModel(this.task);
  final TaskItem task;
  @override
  TaskScheduleState build() => (
    now: ref.watch(clockProvider).now().toLocal(),
    timeState: ref.watch(taskTimeStateProvider(task)),
    displayMode: ref.watch(taskTimeDisplayModeProvider),
    timedMinutes: ref.watch(quickAddDefaultTimedBlockMinutesProvider),
  );
  Future<void> setPriority(int priority) async {
    (await ref
            .read(taskRepositoryProvider)
            .updateTask(task.id, UpdateTaskPatch(priority: priority)))
        .getOrThrow();
  }

  Future<void> clear() async {
    (await ref
            .read(taskRepositoryProvider)
            .updateTask(task.id, UpdateTaskPatch(clearSchedule: true)))
        .getOrThrow();
  }

  Future<void> setSchedule(
    TaskSchedule schedule, {
    bool preserveRecurrence = true,
  }) async {
    final recurrence = preserveRecurrence
        ? schedule.recurrence ?? task.schedule?.recurrence
        : schedule.recurrence;
    final seriesId = preserveRecurrence
        ? task.schedule?.recurrenceSeriesKey
        : schedule.recurrenceSeriesId;
    final next = recurrence == null
        ? schedule.withRecurrenceSeriesId(seriesId)
        : schedule.withRecurrence(recurrence);
    (await ref
            .read(taskRepositoryProvider)
            .updateTask(task.id, UpdateTaskPatch(schedule: next)))
        .getOrThrow();
  }
}

typedef SubtasksState = ({
  AsyncValue<List<TaskItem>> tasks,
  List<TaskItem> allTasks,
});
final subtasksViewModelProvider = NotifierProvider.autoDispose
    .family<SubtasksViewModel, SubtasksState, String>(SubtasksViewModel.new);

class SubtasksViewModel extends Notifier<SubtasksState> {
  SubtasksViewModel(this.parentId);
  final String parentId;
  @override
  SubtasksState build() {
    final tasks = ref.watch(tasksByQueryProvider(const TaskQuery.all()));
    final completed = ref.watch(
      tasksByQueryProvider(const TaskQuery.completed()),
    );
    final byId = <String, TaskItem>{};
    for (final task in [...?tasks.value, ...?completed.value]) {
      if (!task.isDeleted) byId.putIfAbsent(task.id, () => task);
    }
    final all = byId.values.toList();
    final ids = descendantTaskIds(parentId, all);
    final descendants = all.where((task) => ids.contains(task.id)).toList()
      ..sort(compareTaskOrder);
    return (
      tasks: tasks.hasError
          ? AsyncError(tasks.error!, tasks.stackTrace ?? StackTrace.current)
          : completed.hasError
          ? AsyncError(
              completed.error!,
              completed.stackTrace ?? StackTrace.current,
            )
          : tasks.hasValue && completed.hasValue
          ? AsyncData(List.unmodifiable(descendants))
          : const AsyncLoading(),
      allTasks: List.unmodifiable(all),
    );
  }
}
