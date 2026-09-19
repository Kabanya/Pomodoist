import 'package:pomodoist/config/task_focus_dependencies.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/use_cases/tasks/task_scheduling.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/tasks/task_focus_estimate.dart';
import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'package:pomodoist/domain/models/tasks/task_time.dart';

typedef TaskItemState = ({
  int? focusEstimate,
  TaskTimeState? timeState,
  TaskTimeDisplayMode timeDisplayMode,
  int timedMinutes,
  TaskListStyle listStyle,
  TaskRowSpacing rowSpacing,
  ProjectItem? project,
});
final taskItemViewModelProvider = NotifierProvider.autoDispose
    .family<TaskItemViewModel, TaskItemState, TaskItem>(TaskItemViewModel.new);

class TaskItemViewModel extends Notifier<TaskItemState> {
  TaskItemViewModel(this.task);
  final TaskItem task;
  late TaskRepository _tasks;
  @override
  TaskItemState build() {
    _tasks = ref.watch(taskRepositoryProvider);
    final preset = selectedFocusPresetOrDefault(
      ref.watch(focusPresetsProvider).value ?? const [],
      ref.watch(lastFocusPresetIdProvider),
    );
    return (
      focusEstimate: targetFocusIntervalsForTask(task, preset),
      timeState: ref.watch(taskTimeStateProvider(task)),
      timeDisplayMode: ref.watch(taskTimeDisplayModeProvider),
      timedMinutes: ref.watch(quickAddDefaultTimedBlockMinutesProvider),
      listStyle: ref.watch(taskListStyleProvider),
      rowSpacing: ref.watch(taskRowSpacingProvider),
      project: ref
          .watch(projectsProvider)
          .value
          ?.where((p) => p.id == task.projectId)
          .firstOrNull,
    );
  }

  Future<TaskItem?> current() async {
    try {
      return await _tasks.watchTask(task.id).first;
    } catch (_) {
      return null;
    }
  }

  Future<TaskItem?> complete() async {
    (await _tasks.completeTask(task.id)).getOrThrow();
    return current();
  }

  Future<TaskItem?> reopen() async {
    (await _tasks.uncompleteTask(task.id)).getOrThrow();
    return current();
  }

  Future<DeletedTaskBatch> delete({required bool includeFollowing}) async =>
      (await ((task.schedule?.isRecurringOccurrence ?? false)
              ? _tasks.deleteRecurringOccurrence(
                  task.id,
                  includeFollowing: includeFollowing,
                )
              : _tasks.deleteTask(task.id)))
          .getOrThrow();
  Future<bool> restore(DeletedTaskBatch batch) async =>
      (await _tasks.restoreDeletedTasks(batch)).getOrThrow();
  Future<void> setPriority(int priority) async {
    (await _tasks.updateTask(
      task.id,
      UpdateTaskPatch(priority: priority),
    )).getOrThrow();
  }

  Future<void> moveToDay(int offset) async {
    final now = ref.read(clockProvider).now().toLocal();
    final day = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(Duration(days: offset));
    (await _tasks.updateTask(
      task.id,
      UpdateTaskPatch(
        schedule: task.schedule?.moveToDate(day) ?? TaskSchedule.allDay(day),
      ),
    )).getOrThrow();
  }

  Future<void> clearSchedule() async {
    (await _tasks.updateTask(
      task.id,
      const UpdateTaskPatch(clearSchedule: true),
    )).getOrThrow();
  }

  Future<void> makeParent() async {
    (await _tasks.moveTask(
      task.id,
      clearParentId: true,
      orderKey: _orderKey(),
    )).getOrThrow();
  }

  Future<void> nestTask(String draggedId) async {
    (await _tasks.moveTask(
      draggedId,
      projectId: task.projectId,
      sectionId: task.sectionId,
      clearSectionId: task.sectionId == null,
      parentId: task.id,
      orderKey: _orderKey(),
    )).getOrThrow();
  }

  String _orderKey() =>
      DateTime.now().toUtc().microsecondsSinceEpoch.toString().padLeft(20, '0');
  Future<void> schedule(TaskDueResult result) async {
    final latest = await _tasks.watchTask(task.id).first;
    if (latest == null || latest.isDeleted) {
      throw StateError('Task unavailable');
    }
    (await _tasks.updateTask(
      task.id,
      taskDuePatch(latest, result),
    )).getOrThrow();
  }

  Future<bool> startFocus(Future<bool> Function() confirmSwitch) async {
    final launcher = ref.read(taskFocusLauncherProvider);
    final presetId = ref.read(lastFocusPresetIdProvider);
    final presets = await ref.read(focusPresetsProvider.future);
    if (!ref.mounted) return false;
    return launcher.open(
      task,
      preset: selectedFocusPresetOrDefault(presets, presetId),
      confirmSwitch: confirmSwitch,
    );
  }
}
