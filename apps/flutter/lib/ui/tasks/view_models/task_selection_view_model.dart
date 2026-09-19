import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/use_cases/tasks/task_scheduling.dart';

typedef TaskSelectionState = ({
  List<ProjectItem> projects,
  List<LabelItem> labels,
  DateTime now,
});
typedef BulkTaskChange = ({
  List<String> succeeded,
  List<String> failed,
  List<TaskItem> tasks,
});
typedef BulkDeletion = ({List<String> failed, List<DeletedTaskBatch> batches});
final taskSelectionViewModelProvider = NotifierProvider.autoDispose
    .family<TaskSelectionViewModel, TaskSelectionState, Object>(
      TaskSelectionViewModel.new,
    );

class TaskSelectionViewModel extends Notifier<TaskSelectionState> {
  TaskSelectionViewModel(this.identity);
  final Object identity;
  late TaskRepository _tasks;
  @override
  TaskSelectionState build() {
    _tasks = ref.watch(taskRepositoryProvider);
    return (
      projects: List.unmodifiable(
        ref.watch(projectsProvider).value ?? const <ProjectItem>[],
      ),
      labels: List.unmodifiable(
        ref.watch(labelsProvider).value ?? const <LabelItem>[],
      ),
      now: ref.watch(clockProvider).now().toLocal(),
    );
  }

  Future<List<String>> _each(
    Iterable<String> ids,
    Future<void> Function(String) action,
  ) async {
    final failed = <String>[];
    for (final id in ids.toList()) {
      try {
        await action(id);
      } catch (_) {
        failed.add(id);
      }
    }
    return List.unmodifiable(failed);
  }

  Future<List<String>> schedule(
    Iterable<TaskItem> tasks,
    TaskDueResult result,
  ) => applyTaskDueResult(
    tasks,
    result,
    updateTask: (id, patch) async {
      (await _tasks.updateTask(id, patch)).getOrThrow();
    },
  );
  Future<List<String>> setProject(
    Iterable<TaskItem> selected,
    String projectId,
  ) async {
    final tasks = {for (final task in selected) task.id: task};
    return _each(tasks.keys, (id) async {
      final task = tasks[id]!;
      final changed = task.projectId != projectId;
      (await _tasks.moveTask(
        id,
        projectId: projectId,
        clearSectionId: changed,
        clearParentId:
            changed &&
            task.parentId != null &&
            !tasks.containsKey(task.parentId),
      )).getOrThrow();
    });
  }

  Future<List<String>> setLabels(Iterable<String> ids, List<String> labels) =>
      _each(ids, (id) async {
        (await _tasks.updateTask(
          id,
          UpdateTaskPatch(labelNames: labels),
        )).getOrThrow();
      });
  Future<List<String>> setPriority(Iterable<String> ids, int priority) =>
      _each(ids, (id) async {
        (await _tasks.updateTask(
          id,
          UpdateTaskPatch(priority: priority),
        )).getOrThrow();
      });
  Future<BulkTaskChange> setCompleted(
    Iterable<String> selected, {
    required bool completed,
  }) async {
    final ids = selected.toList();
    final failed = await _each(ids, (id) async {
      (await (completed ? _tasks.completeTask(id) : _tasks.uncompleteTask(id)))
          .getOrThrow();
    });
    final succeeded = ids.where((id) => !failed.contains(id)).toList();
    final tasks = <TaskItem>[];
    for (final id in succeeded) {
      try {
        final task = await _tasks.watchTask(id).first;
        if (task != null) tasks.add(task);
      } catch (_) {
        /* Committed changes do not become failures when motion snapshots fail. */
      }
    }
    return (
      succeeded: List<String>.unmodifiable(succeeded),
      failed: failed,
      tasks: List<TaskItem>.unmodifiable(tasks),
    );
  }

  Future<List<String>> duplicate(
    Set<String> ids, {
    required bool includeSubtasks,
  }) async => (await _tasks.duplicateTasks(
    ids,
    includeSubtasks: includeSubtasks,
  )).getOrThrow();
  Future<BulkDeletion> delete(
    Iterable<TaskItem> selected, {
    required bool includeFollowing,
  }) async {
    final tasks = selected.toList();
    final failed = <String>[];
    final batches = <DeletedTaskBatch>[];
    final ordinary = tasks
        .where((t) => !(t.schedule?.isRecurringOccurrence ?? false))
        .map((t) => t.id)
        .toSet();
    if (ordinary.isNotEmpty) {
      try {
        batches.add((await _tasks.deleteTasks(ordinary)).getOrThrow());
      } catch (_) {
        failed.addAll(ordinary);
      }
    }
    for (final task in tasks.where(
      (t) => t.schedule?.isRecurringOccurrence ?? false,
    )) {
      try {
        batches.add(
          (await _tasks.deleteRecurringOccurrence(
            task.id,
            includeFollowing: includeFollowing,
          )).getOrThrow(),
        );
      } catch (_) {
        failed.add(task.id);
      }
    }
    return (
      failed: List<String>.unmodifiable(failed),
      batches: List<DeletedTaskBatch>.unmodifiable(batches),
    );
  }

  Future<({Set<String> ids, int failures})> restore(
    Iterable<DeletedTaskBatch> batches,
  ) async {
    final restored = <String>{};
    var failures = 0;
    for (final batch in batches) {
      try {
        if ((await _tasks.restoreDeletedTasks(batch)).getOrThrow()) {
          restored.addAll(batch.taskIds);
        } else {
          failures += batch.taskIds.length;
        }
      } catch (_) {
        failures += batch.taskIds.length;
      }
    }
    return (ids: Set.unmodifiable(restored), failures: failures);
  }
}

final taskDuePanelViewModelProvider =
    NotifierProvider.autoDispose<TaskDuePanelViewModel, DateTime>(
      TaskDuePanelViewModel.new,
    );

class TaskDuePanelViewModel extends Notifier<DateTime> {
  @override
  DateTime build() => ref.watch(clockProvider).now().toLocal();
}
