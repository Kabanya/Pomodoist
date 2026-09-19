import 'package:pomodoist/domain/models/tasks/task_models.dart';

class TaskSubtaskProgress {
  const TaskSubtaskProgress({required this.completed, required this.total});

  final int completed;
  final int total;

  String get label => '$completed/$total';
}

Map<String, TaskSubtaskProgress> taskSubtaskProgressById(
  Iterable<TaskItem> tasks,
) {
  final byId = <String, TaskItem>{for (final task in tasks) task.id: task};
  final childrenByParent = <String, List<TaskItem>>{};
  for (final task in byId.values) {
    final parentId = task.parentId;
    if (parentId == null || !byId.containsKey(parentId)) {
      continue;
    }
    childrenByParent.putIfAbsent(parentId, () => []).add(task);
  }

  final cache = <String, TaskSubtaskProgress>{};
  TaskSubtaskProgress countFor(String id, Set<String> path) {
    final cached = cache[id];
    if (cached != null) {
      return cached;
    }

    var completed = 0;
    var total = 0;
    for (final child in childrenByParent[id] ?? const <TaskItem>[]) {
      if (!path.add(child.id)) {
        continue;
      }
      total += 1;
      if (child.isCompleted) {
        completed += 1;
      }
      final childProgress = countFor(child.id, path);
      completed += childProgress.completed;
      total += childProgress.total;
      path.remove(child.id);
    }

    final progress = TaskSubtaskProgress(completed: completed, total: total);
    cache[id] = progress;
    return progress;
  }

  final result = <String, TaskSubtaskProgress>{};
  for (final id in byId.keys) {
    final progress = countFor(id, {id});
    if (progress.total > 0) {
      result[id] = progress;
    }
  }
  return result;
}
