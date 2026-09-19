import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

final priorityMatrixViewModelProvider =
    NotifierProvider.autoDispose<
      PriorityMatrixViewModel,
      AsyncValue<List<TaskItem>>
    >(PriorityMatrixViewModel.new);

class PriorityMatrixViewModel extends Notifier<AsyncValue<List<TaskItem>>> {
  @override
  AsyncValue<List<TaskItem>> build() =>
      ref.watch(tasksByQueryProvider(const TaskQuery.all()));
  Future<void> setPriority(String id, int priority) async {
    (await ref
            .read(taskRepositoryProvider)
            .updateTask(id, UpdateTaskPatch(priority: priority)))
        .getOrThrow();
  }
}

Map<int, List<TaskItem>> priorityBuckets(List<TaskItem> tasks) {
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
