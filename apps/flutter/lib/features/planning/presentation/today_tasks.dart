import '../../tasks/domain/task_models.dart';

List<TaskItem> completedTasksForDay(Iterable<TaskItem> tasks, DateTime day) {
  final localDay = day.toLocal();
  return tasks.where((task) {
    if (task.isDeleted || !task.isCompleted) return false;
    final completed = (task.completedAt ?? task.updatedAt).toLocal();
    return completed.year == localDay.year &&
        completed.month == localDay.month &&
        completed.day == localDay.day;
  }).toList();
}
