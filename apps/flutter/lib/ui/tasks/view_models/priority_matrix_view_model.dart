import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

typedef PriorityMatrixState = ({
  AsyncValue<List<TaskItem>> tasks,
  Map<int, List<TaskItem>> buckets,
  Map<String, TaskItem> tasksById,
});

final priorityMatrixViewModelProvider =
    NotifierProvider.autoDispose<PriorityMatrixViewModel, PriorityMatrixState>(
      PriorityMatrixViewModel.new,
    );

class PriorityMatrixViewModel extends Notifier<PriorityMatrixState> {
  @override
  PriorityMatrixState build() {
    final tasks = ref
        .watch(tasksByQueryProvider(const TaskQuery.all()))
        .whenData(
          (rows) => List<TaskItem>.unmodifiable(
            rows.where((task) => !task.isCompleted),
          ),
        );
    return (
      tasks: tasks,
      buckets: tasks.hasValue
          ? priorityBuckets(tasks.value!)
          : const <int, List<TaskItem>>{},
      tasksById: Map.unmodifiable({
        for (final task in tasks.value ?? const <TaskItem>[]) task.id: task,
      }),
    );
  }

  /// Rendering-only projection for rows that are animating out. Retained tasks
  /// keep their previous bucket until the exit animation finishes; actions
  /// still revalidate against the live repository by task ID.
  Map<int, List<TaskItem>> bucketsWithRetained(Iterable<TaskItem> retained) {
    if (retained.isEmpty) {
      return state.buckets;
    }
    final byId = <String, TaskItem>{
      for (final task in retained) task.id: task,
      for (final task in state.tasks.value ?? const <TaskItem>[]) task.id: task,
    };
    return priorityBuckets(byId.values);
  }

  Future<void> setPriority(String id, int priority) async {
    (await ref
            .read(taskRepositoryProvider)
            .updateTask(id, UpdateTaskPatch(priority: priority)))
        .getOrThrow();
  }
}

Map<int, List<TaskItem>> priorityBuckets(Iterable<TaskItem> tasks) {
  final result = {
    for (final priority in matrixPriorities) priority: <TaskItem>[],
  };
  for (final task in tasks) {
    result[priorityBucket(task.priority)]!.add(task);
  }
  for (final bucket in result.values) {
    bucket.sort(compareMatrixTaskOrder);
  }
  return Map.unmodifiable(
    result.map((k, v) => MapEntry(k, List<TaskItem>.unmodifiable(v))),
  );
}

const matrixPriorities = [1, 2, 3, 4];

int priorityBucket(int priority) {
  return priority >= 1 && priority <= 4 ? priority : 4;
}

int compareMatrixTaskOrder(TaskItem a, TaskItem b) {
  final aStart = a.schedule?.occurrenceStartLocal;
  final bStart = b.schedule?.occurrenceStartLocal;
  if (aStart != null && bStart != null) {
    final scheduleCompare = aStart.compareTo(bStart);
    if (scheduleCompare != 0) {
      return scheduleCompare;
    }
  } else if (aStart != null) {
    return -1;
  } else if (bStart != null) {
    return 1;
  }

  final dayOrderCompare = (a.dayOrder ?? 999999).compareTo(
    b.dayOrder ?? 999999,
  );
  if (dayOrderCompare != 0) {
    return dayOrderCompare;
  }
  return a.orderKey.compareTo(b.orderKey);
}
