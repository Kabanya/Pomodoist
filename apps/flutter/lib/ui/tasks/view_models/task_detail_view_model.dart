import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/tasks/task_focus_estimate.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository.dart';
import 'package:pomodoist/domain/models/tasks/task_time.dart';

typedef TaskDetailState = ({
  AsyncValue<TaskItem?> task,
  bool calendarLinked,
  FocusPresetItem? preset,
  int? focusEstimate,
});
final taskDetailViewModelProvider = NotifierProvider.autoDispose
    .family<TaskDetailViewModel, TaskDetailState, String>(
      TaskDetailViewModel.new,
    );

class TaskDetailViewModel extends Notifier<TaskDetailState> {
  TaskDetailViewModel(this.taskId);
  final String taskId;
  late TaskRepository _tasks;
  @override
  TaskDetailState build() {
    _tasks = ref.watch(taskRepositoryProvider);
    final task = ref.watch(taskProvider(taskId));
    final preset = selectedFocusPresetOrDefault(
      ref.watch(focusPresetsProvider).value ?? const [],
      ref.watch(lastFocusPresetIdProvider),
    );
    return (
      task: task,
      calendarLinked:
          ref.watch(googleCalendarLinkProvider(taskId)).value != null,
      preset: preset,
      focusEstimate: task.value == null
          ? null
          : targetFocusIntervalsForTask(task.value!, preset),
    );
  }

  Future<TaskItem?> current() async {
    try {
      return await _tasks.watchTask(taskId).first;
    } catch (_) {
      return null;
    }
  }

  Future<TaskItem?> complete() async {
    (await _tasks.completeTask(taskId)).getOrThrow();
    return current();
  }

  Future<TaskItem?> reopen() async {
    (await _tasks.uncompleteTask(taskId)).getOrThrow();
    return current();
  }

  Future<void> startFocus() async {
    final task = state.task.value;
    if (task == null || task.isDeleted || task.isCompleted) return;
    final estimate = state.focusEstimate;
    (await ref
            .read(focusRepositoryProvider)
            .startRun(
              StartFocusRunInput(
                taskId: task.id,
                projectId: task.projectId,
                presetId: state.preset?.id,
                targetWorkIntervals: estimate == null
                    ? null
                    : estimate < 1
                    ? 1
                    : estimate,
              ),
            ))
        .getOrThrow();
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
    state = _copy(saving: false, failed: failed, dirty: failed);
    return !failed;
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
    return (
      tasks: tasks.whenData((items) {
        final children = items.where((t) => t.parentId == parentId).toList()
          ..sort((a, b) => a.orderKey.compareTo(b.orderKey));
        return List.unmodifiable(children);
      }),
      allTasks: List.unmodifiable([...?tasks.value, ...?completed.value]),
    );
  }
}
