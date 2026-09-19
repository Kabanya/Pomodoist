import 'package:flutter_riverpod/flutter_riverpod.dart';
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

final taskEditorViewModelProvider = NotifierProvider.autoDispose
    .family<TaskEditorViewModel, AsyncValue<void>, Object>(
      TaskEditorViewModel.new,
    );

class TaskEditorViewModel extends Notifier<AsyncValue<void>> {
  TaskEditorViewModel(this.identity);
  final Object identity;
  @override
  AsyncValue<void> build() => const AsyncData(null);
  Future<bool> _run(Future<void> Function() action) async {
    if (state.isLoading) return false;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(action);
    if (ref.mounted) state = result;
    return !result.hasError;
  }

  Future<bool> saveTitle(TaskItem task, String next) => _run(() async {
    final parsed = ref
        .read(quickAddParserProvider)
        .parse(
          next,
          now: ref.read(clockProvider).now().toLocal(),
          defaultDate: task.schedule?.displayDate,
        );
    final content = (parsed.content.isEmpty ? task.content : parsed.content);
    var schedule = parsed.dueDate != null || parsed.schedule?.isTimed == true
        ? parsed.schedule
        : null;
    if (parsed.dueDate != null && schedule?.isAllDay == true) {
      schedule = task.schedule?.moveToDate(parsed.dueDate!) ?? schedule;
    }
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
    final taskRepository = ref.read(taskRepositoryProvider);
    if (shouldUpdateTask) {
      (await taskRepository.updateTask(task.id, patch)).getOrThrow();
    }
    final project = parsed.project;
    if (project != null) {
      final projectId =
          (await ref.read(projectRepositoryProvider).createProject(project))
              .getOrThrow();
      (await taskRepository.moveTask(
        task.id,
        projectId: projectId,
      )).getOrThrow();
    }
  });
  Future<bool> saveDescription(TaskItem task, String value) => _run(() async {
    final text = value.trim();
    (await ref
            .read(taskRepositoryProvider)
            .updateTask(
              task.id,
              UpdateTaskPatch(
                description: text.isEmpty ? null : text,
                updateDescription: true,
              ),
            ))
        .getOrThrow();
  });
  Future<bool> createSubtask(TaskItem task, String input) => _run(() async {
    final parsed = ref
        .read(quickAddParserProvider)
        .parse(input, now: ref.read(clockProvider).now().toLocal());
    if (parsed.content.isEmpty) {
      return;
    }
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
  });
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
            .updateTask(task.id, const UpdateTaskPatch(clearSchedule: true)))
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
