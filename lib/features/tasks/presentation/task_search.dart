import '../domain/task_models.dart';

enum TaskSearchStatus { open, completed, all }

List<TaskItem> filterTaskSearch(
  Iterable<TaskItem> tasks, {
  required String query,
  String? projectId,
  TaskSearchStatus status = TaskSearchStatus.open,
  DateTime? completedTaskCutoff,
}) {
  final search = query.trim().toLowerCase();
  if (search.isEmpty) return [];
  final matches = tasks.where((task) {
    if (task.isDeleted || (projectId != null && task.projectId != projectId)) {
      return false;
    }
    if (status == TaskSearchStatus.open && task.isCompleted) return false;
    if (status == TaskSearchStatus.completed && !task.isCompleted) return false;
    if (task.isCompleted &&
        completedTaskCutoff != null &&
        (task.completedAt ?? task.updatedAt).toUtc().isBefore(
          completedTaskCutoff,
        )) {
      return false;
    }
    return task.content.toLowerCase().contains(search) ||
        (task.description ?? '').toLowerCase().contains(search);
  }).toList();
  matches.sort((a, b) {
    final dayOrder = (a.dayOrder ?? 999999).compareTo(b.dayOrder ?? 999999);
    return dayOrder != 0 ? dayOrder : a.orderKey.compareTo(b.orderKey);
  });
  return matches;
}
