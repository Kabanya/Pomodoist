import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

final taskListViewModelProvider = NotifierProvider.autoDispose
    .family<TaskListViewModel, TaskListState, TaskQuery>(TaskListViewModel.new);

class TaskListState {
  const TaskListState({required this.tasks, required this.allTasks});
  final AsyncValue<List<TaskItem>> tasks;
  final List<TaskItem> allTasks;

  List<TaskItem> visibleTasks(
    Iterable<TaskItem> retained,
    bool Function(TaskItem)? filter,
  ) {
    final result = <String, TaskItem>{
      for (final task in retained) task.id: task,
      for (final task in tasks.value ?? const <TaskItem>[])
        if (filter == null || filter(task)) task.id: task,
    }.values.toList()..sort(compareTaskOrder);
    return List.unmodifiable(result);
  }

  List<VisibleTaskRow> rows(List<TaskItem> visible) =>
      visibleTaskRows([...allTasks, ...visible], visible);
}

class TaskListViewModel extends Notifier<TaskListState> {
  TaskListViewModel(this.query);
  final TaskQuery query;
  @override
  TaskListState build() => TaskListState(
    tasks: ref.watch(tasksByQueryProvider(query)),
    allTasks: List.unmodifiable([
      ...?ref.watch(tasksByQueryProvider(const TaskQuery.all())).value,
      ...?ref.watch(tasksByQueryProvider(const TaskQuery.completed())).value,
    ]),
  );

  void retry() => ref.invalidate(tasksByQueryProvider(query));
  Future<void> makeRoot(String taskId) async {
    (await ref
            .read(taskRepositoryProvider)
            .moveTask(
              taskId,
              clearParentId: true,
              orderKey: ref
                  .read(clockProvider)
                  .now()
                  .toUtc()
                  .microsecondsSinceEpoch
                  .toString()
                  .padLeft(20, '0'),
            ))
        .getOrThrow();
  }
}

List<VisibleTaskRow> visibleTaskRows(
  List<TaskItem> allItems,
  List<TaskItem> visibleItems,
) {
  final byId = <String, TaskItem>{for (final task in allItems) task.id: task};
  final visibleIds = {for (final task in visibleItems) task.id};
  final childrenByParent = <String?, List<TaskItem>>{};
  for (final task in byId.values) {
    final parentId = byId.containsKey(task.parentId) ? task.parentId : null;
    childrenByParent.putIfAbsent(parentId, () => []).add(task);
  }
  for (final children in childrenByParent.values) {
    children.sort(compareTaskOrder);
  }

  final rows = <VisibleTaskRow>[];
  void walk(TaskItem task, int depth) {
    final children = childrenByParent[task.id] ?? const <TaskItem>[];
    final isVisible = visibleIds.contains(task.id);
    if (isVisible) {
      rows.add(VisibleTaskRow(task: task, depth: depth));
    }
    for (final child in children) {
      walk(child, depth + 1);
    }
  }

  for (final task in childrenByParent[null] ?? const <TaskItem>[]) {
    walk(task, 0);
  }
  return rows;
}

int compareTaskOrder(TaskItem a, TaskItem b) {
  final dayOrderCompare = (a.dayOrder ?? 999999).compareTo(
    b.dayOrder ?? 999999,
  );
  if (dayOrderCompare != 0) {
    return dayOrderCompare;
  }
  return a.orderKey.compareTo(b.orderKey);
}

class VisibleTaskRow {
  const VisibleTaskRow({required this.task, required this.depth});

  final TaskItem task;
  final int depth;
}
