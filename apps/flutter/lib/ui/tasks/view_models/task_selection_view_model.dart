import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/use_cases/tasks/task_scheduling.dart';

typedef TaskSelectionState = ({
  List<ProjectItem> projects,
  List<LabelItem> labels,
  DateTime now,
  Set<String> selectedIds,
  bool active,
  bool pending,
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
  Map<String, TaskItem> _visibleTasks = const {};

  @override
  TaskSelectionState build() {
    _tasks = ref.watch(taskRepositoryProvider);
    ref.listen(projectsProvider, (_, next) {
      state = _copy(
        projects: List.unmodifiable(next.value ?? const <ProjectItem>[]),
      );
    });
    ref.listen(labelsProvider, (_, next) {
      state = _copy(
        labels: List.unmodifiable(next.value ?? const <LabelItem>[]),
      );
    });
    return (
      projects: List.unmodifiable(
        ref.read(projectsProvider).value ?? const <ProjectItem>[],
      ),
      labels: List.unmodifiable(
        ref.read(labelsProvider).value ?? const <LabelItem>[],
      ),
      now: ref.read(clockProvider).now().toLocal(),
      selectedIds: const <String>{},
      active: false,
      pending: false,
    );
  }

  bool get active => state.active;
  bool get pending => state.pending;
  bool get hasSelection => state.selectedIds.isNotEmpty;
  int get selectedCount => state.selectedIds.length;
  Set<String> get selectedIds => state.selectedIds;
  Iterable<TaskItem> get visibleTasks => _visibleTasks.values;
  bool get allVisibleSelected =>
      _visibleTasks.isNotEmpty &&
      _visibleTasks.keys.every(state.selectedIds.contains);
  Iterable<TaskItem> get selectedTasks sync* {
    for (final id in state.selectedIds) {
      final task = _visibleTasks[id];
      if (task != null) yield task;
    }
  }

  bool isSelected(String id) => state.selectedIds.contains(id);

  void updateVisible(Iterable<TaskItem> tasks) {
    _visibleTasks = {for (final task in tasks) task.id: task};
    if (!state.active || state.selectedIds.isEmpty) return;
    final retained = state.selectedIds.where(_visibleTasks.containsKey).toSet();
    if (retained.length == state.selectedIds.length) return;
    state = _copy(
      selectedIds: Set<String>.unmodifiable(retained),
      active: retained.isNotEmpty,
    );
  }

  void begin([String? id]) {
    state = _copy(
      selectedIds: Set<String>.unmodifiable({if (id != null) id}),
      active: true,
    );
  }

  void toggle(String id) {
    if (!state.active) return;
    final next = {...state.selectedIds};
    if (!next.remove(id)) next.add(id);
    state = _copy(selectedIds: Set<String>.unmodifiable(next));
  }

  void toggleAll() {
    final next = allVisibleSelected
        ? const <String>{}
        : _visibleTasks.keys.toSet();
    state = _copy(selectedIds: Set<String>.unmodifiable(next));
  }

  void retainVisible(Iterable<String> ids) {
    final retained = ids.where(_visibleTasks.containsKey).toSet();
    state = _copy(
      selectedIds: Set<String>.unmodifiable(retained),
      active: retained.isNotEmpty,
    );
  }

  void clear() {
    if (!state.active && state.selectedIds.isEmpty) return;
    state = _copy(selectedIds: const <String>{}, active: false);
  }

  TaskSelectionState _copy({
    List<ProjectItem>? projects,
    List<LabelItem>? labels,
    Set<String>? selectedIds,
    bool? active,
    bool? pending,
  }) => (
    projects: projects ?? state.projects,
    labels: labels ?? state.labels,
    now: state.now,
    selectedIds: selectedIds ?? state.selectedIds,
    active: active ?? state.active,
    pending: pending ?? state.pending,
  );

  List<String> _validIds(Iterable<String> ids) => [
    for (final id in ids)
      if (_visibleTasks.containsKey(id)) id,
  ];

  Future<({List<String> succeeded, List<String> failed})> _each(
    Iterable<String> ids,
    Future<void> Function(String) action, {
    bool requireVisible = true,
  }) async {
    final succeeded = <String>[];
    final failed = <String>[];
    for (final id in ids.toSet()) {
      if (requireVisible && !_visibleTasks.containsKey(id)) continue;
      try {
        await action(id);
        succeeded.add(id);
      } catch (_) {
        failed.add(id);
      }
    }
    return (
      succeeded: List<String>.unmodifiable(succeeded),
      failed: List<String>.unmodifiable(failed),
    );
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    state = _copy(pending: true);
    try {
      return await action();
    } finally {
      if (ref.mounted) state = _copy(pending: false);
    }
  }

  Future<List<String>> schedule(
    Iterable<TaskItem> tasks,
    TaskDueResult result,
  ) async {
    final byId = {for (final task in tasks) task.id: task};
    return _run(
      () async => (await _each(byId.keys, (id) async {
        (await _tasks.updateTask(
          id,
          taskDuePatch(_visibleTasks[id]!, result),
        )).getOrThrow();
      })).failed,
    );
  }

  Future<List<String>> setProject(
    Iterable<TaskItem> selected,
    String projectId,
  ) async {
    final tasks = {for (final task in selected) task.id: task};
    return _run(
      () async => (await _each(tasks.keys, (id) async {
        final task = _visibleTasks[id]!;
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
      })).failed,
    );
  }

  Future<List<String>> setLabels(Iterable<String> ids, List<String> labels) =>
      _run(
        () async => (await _each(ids, (id) async {
          (await _tasks.updateTask(
            id,
            UpdateTaskPatch(labelNames: labels),
          )).getOrThrow();
        })).failed,
      );

  Future<List<String>> setPriority(Iterable<String> ids, int priority) => _run(
    () async => (await _each(ids, (id) async {
      (await _tasks.updateTask(
        id,
        UpdateTaskPatch(priority: priority),
      )).getOrThrow();
    })).failed,
  );

  Future<BulkTaskChange> setCompleted(
    Iterable<String> selected, {
    required bool completed,
  }) async {
    final result = await _run(
      () => _each(selected, (id) async {
        (await (completed
                ? _tasks.completeTask(id)
                : _tasks.uncompleteTask(id)))
            .getOrThrow();
      }),
    );
    final tasks = <TaskItem>[];
    for (final id in result.succeeded) {
      try {
        final task = await _tasks.watchTask(id).first;
        if (task != null) tasks.add(task);
      } catch (_) {
        /* Committed changes do not become failures when motion snapshots fail. */
      }
    }
    return (
      succeeded: result.succeeded,
      failed: result.failed,
      tasks: List<TaskItem>.unmodifiable(tasks),
    );
  }

  /// Reverses a completed bulk action by committed task ID. Tasks completed by
  /// the preceding action are expected to have left the current open-task view.
  Future<BulkTaskChange> undoCompleted(
    Iterable<String> taskIds, {
    required bool completed,
  }) async {
    final result = await _run(
      () => _each(taskIds, (id) async {
        (await (completed
                ? _tasks.completeTask(id)
                : _tasks.uncompleteTask(id)))
            .getOrThrow();
      }, requireVisible: false),
    );
    final tasks = <TaskItem>[];
    for (final id in result.succeeded) {
      try {
        final task = await _tasks.watchTask(id).first;
        if (task != null) tasks.add(task);
      } catch (_) {
        /* The inverse write succeeded; motion snapshots are best-effort. */
      }
    }
    return (
      succeeded: result.succeeded,
      failed: result.failed,
      tasks: List<TaskItem>.unmodifiable(tasks),
    );
  }

  Future<List<String>> duplicate(
    Set<String> ids, {
    required bool includeSubtasks,
  }) async => _run(
    () async => (await _tasks.duplicateTasks(
      _validIds(ids).toSet(),
      includeSubtasks: includeSubtasks,
    )).getOrThrow(),
  );

  Future<BulkDeletion> delete(
    Iterable<TaskItem> selected, {
    required bool includeFollowing,
  }) async => _run(() async {
    final tasks = {for (final task in selected) task.id: task};
    final failed = <String>[];
    final batches = <DeletedTaskBatch>[];
    final current = [
      for (final id in _validIds(tasks.keys))
        if (_visibleTasks.containsKey(id)) tasks[id]!,
    ];
    final ordinary = current
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
    for (final task in current.where(
      (t) => t.schedule?.isRecurringOccurrence ?? false,
    )) {
      if (!_visibleTasks.containsKey(task.id)) continue;
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
  });

  Future<({Set<String> ids, int failures})> restore(
    Iterable<DeletedTaskBatch> batches,
  ) => _run(() async {
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
  });
}

final taskDuePanelViewModelProvider =
    NotifierProvider.autoDispose<TaskDuePanelViewModel, DateTime>(
      TaskDuePanelViewModel.new,
    );

class TaskDuePanelViewModel extends Notifier<DateTime> {
  @override
  DateTime build() => ref.watch(clockProvider).now().toLocal();
}
