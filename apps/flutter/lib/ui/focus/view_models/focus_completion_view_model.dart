import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/data/repositories/focus/focus_completion_repository.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/tasks/task_focus_estimate.dart';
import 'package:pomodoist/domain/models/tasks/task_time.dart';

final focusCompletionSlotViewModelProvider =
    NotifierProvider<FocusCompletionSlotViewModel, FocusRunCompletionEvent?>(
      FocusCompletionSlotViewModel.new,
    );

class FocusCompletionSlotViewModel extends Notifier<FocusRunCompletionEvent?> {
  @override
  FocusRunCompletionEvent? build() => ref.watch(focusCompletionEventProvider);
}

class FocusCompletionState {
  const FocusCompletionState({
    required this.task,
    required this.nextTask,
    required this.nextTaskPreset,
    required this.loading,
    required this.hasError,
    required this.resolvingTask,
    required this.taskHasError,
    required this.busy,
  });
  final TaskItem? task, nextTask;
  final FocusPresetItem? nextTaskPreset;
  final bool loading, hasError, resolvingTask, taskHasError, busy;
  bool get canCompleteTask =>
      task != null && !task!.isDeleted && !task!.isCompleted;
}

final focusCompletionViewModelProvider = NotifierProvider.autoDispose
    .family<
      FocusCompletionViewModel,
      FocusCompletionState,
      FocusRunCompletionEvent
    >(FocusCompletionViewModel.new);

class FocusCompletionViewModel extends Notifier<FocusCompletionState> {
  FocusCompletionViewModel(this.completion);
  final FocusRunCompletionEvent completion;
  late FocusCompletionRepository _completion;
  TaskRepository? _tasks;
  bool _busy = false;
  @override
  FocusCompletionState build() {
    _completion = ref.watch(focusCompletionRepositoryProvider);
    final taskId = completion.taskId;
    final taskValue = taskId == null ? null : ref.watch(taskProvider(taskId));
    final tasksValue = ref.watch(tasksByQueryProvider(const TaskQuery.all()));
    final presetsValue = ref.watch(focusPresetsProvider);
    final task = taskValue?.asData?.value;
    return FocusCompletionState(
      task: task,
      nextTask: _nextScheduledTask(
        tasksValue.asData?.value ?? const [],
        completion,
        task,
      ),
      nextTaskPreset: selectedFocusPresetOrDefault(
        presetsValue.asData?.value ?? const [],
        ref.watch(lastFocusPresetIdProvider),
      ),
      loading:
          (taskValue?.isLoading ?? false) ||
          tasksValue.isLoading ||
          presetsValue.isLoading,
      hasError:
          (taskValue?.hasError ?? false) ||
          tasksValue.hasError ||
          presetsValue.hasError,
      resolvingTask: taskValue?.isLoading ?? false,
      taskHasError: taskValue?.hasError ?? false,
      busy: _busy,
    );
  }

  void retry() {
    if (completion.taskId case final id?) ref.invalidate(taskProvider(id));
    ref.invalidate(tasksByQueryProvider(const TaskQuery.all()));
    ref.invalidate(focusPresetsProvider);
  }

  bool _begin() {
    if (_busy || !_completion.tryBeginAction(completion.runId)) return false;
    _busy = true;
    ref.invalidateSelf();
    return true;
  }

  void _end() {
    _completion.endAction(completion.runId);
    _busy = false;
    if (ref.mounted) ref.invalidateSelf();
  }

  Future<TaskItem?> completeLinkedTask() async {
    if (!_begin()) return null;
    final id = completion.taskId!;
    final TaskRepository tasks = _tasks ?? ref.read(taskRepositoryProvider);
    _tasks = tasks;
    try {
      final current = await tasks.watchTask(id).first;
      if (current == null || current.isDeleted || current.isCompleted) {
        return null;
      }
      (await tasks.completeTask(id)).getOrThrow();
      try {
        return await tasks.watchTask(id).first;
      } catch (_) {
        return null;
      }
    } finally {
      _end();
    }
  }

  Future<TaskItem?> undoLinkedTask() async {
    final id = completion.taskId!;
    final tasks = _tasks!;
    (await tasks.uncompleteTask(id)).getOrThrow();
    try {
      return await tasks.watchTask(id).first;
    } catch (_) {
      return null;
    }
  }

  Future<void> startNextTask() async {
    if (!_begin()) return;
    final task = state.nextTask;
    final preset = state.nextTaskPreset;
    final currentTaskId = state.canCompleteTask ? completion.taskId : null;
    final tasks = ref.read(taskRepositoryProvider);
    var completedCurrent = false;
    try {
      if (task == null) return;
      if (currentTaskId != null) {
        final current = await tasks.watchTask(currentTaskId).first;
        if (current != null && !current.isDeleted && !current.isCompleted) {
          (await tasks.completeTask(currentTaskId)).getOrThrow();
          completedCurrent = true;
        }
      }
      final estimate = targetFocusIntervalsForTask(task, preset);
      (await ref
              .read(focusRepositoryProvider)
              .startRun(
                StartFocusRunInput(
                  taskId: task.id,
                  projectId: task.projectId,
                  presetId: preset?.id,
                  targetWorkIntervals: estimate == null
                      ? null
                      : estimate < 1
                      ? 1
                      : estimate,
                ),
              ))
          .getOrThrow();
      _completion.dismiss(runId: completion.runId);
    } catch (_) {
      if (completedCurrent) {
        (await tasks.uncompleteTask(currentTaskId!)).getOrThrow();
      }
      rethrow;
    } finally {
      _end();
    }
  }

  void dismiss() {
    if (!_busy) _completion.dismiss(runId: completion.runId);
  }
}

class FocusCompletionTimeState {
  const FocusCompletionTimeState(
    this.timeState,
    this.displayMode,
    this.defaultTimedBlockMinutes,
  );
  final TaskTimeState? timeState;
  final TaskTimeDisplayMode displayMode;
  final int defaultTimedBlockMinutes;
}

final focusCompletionTimeViewModelProvider = NotifierProvider.autoDispose
    .family<FocusCompletionTimeViewModel, FocusCompletionTimeState, TaskItem?>(
      FocusCompletionTimeViewModel.new,
    );

class FocusCompletionTimeViewModel extends Notifier<FocusCompletionTimeState> {
  FocusCompletionTimeViewModel(this.task);
  final TaskItem? task;
  @override
  FocusCompletionTimeState build() => FocusCompletionTimeState(
    task == null ? null : ref.watch(taskTimeStateProvider(task!)),
    ref.watch(taskTimeDisplayModeProvider),
    ref.watch(quickAddDefaultTimedBlockMinutesProvider),
  );
}

TaskItem? _nextScheduledTask(
  Iterable<TaskItem> tasks,
  FocusRunCompletionEvent completion,
  TaskItem? currentTask,
) {
  final currentSchedule = currentTask?.schedule;
  final hasTimedCurrentTask = currentSchedule?.isTimed ?? false;
  TaskItem? next;
  for (final task in tasks) {
    final schedule = task.schedule;
    if (task.id == completion.taskId ||
        task.isCompleted ||
        task.isDeleted ||
        schedule == null ||
        !schedule.isTimed) {
      continue;
    }
    if (hasTimedCurrentTask) {
      if (_compareScheduledTasks(task, currentTask!) <= 0) {
        continue;
      }
    } else if (!schedule.start!.isAfter(completion.completedAt)) {
      continue;
    }
    if (next == null || _compareScheduledTasks(task, next) < 0) {
      next = task;
    }
  }
  return next;
}

int _compareScheduledTasks(TaskItem left, TaskItem right) {
  final start = left.schedule!.start!.compareTo(right.schedule!.start!);
  if (start != 0) {
    return start;
  }
  final dayOrder = (left.dayOrder ?? 999999).compareTo(
    right.dayOrder ?? 999999,
  );
  if (dayOrder != 0) {
    return dayOrder;
  }
  final orderKey = left.orderKey.compareTo(right.orderKey);
  return orderKey != 0 ? orderKey : left.id.compareTo(right.id);
}
