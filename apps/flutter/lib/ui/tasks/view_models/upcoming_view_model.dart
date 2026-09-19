import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

typedef UpcomingState = ({
  DateTime today,
  AsyncValue<List<ProjectItem>> projects,
  List<TaskItem> tasks,
  Object? error,
  bool loading,
});
final upcomingViewModelProvider =
    NotifierProvider.autoDispose<UpcomingViewModel, UpcomingState>(
      UpcomingViewModel.new,
    );

class UpcomingViewModel extends Notifier<UpcomingState> {
  @override
  UpcomingState build() {
    final now = ref.watch(clockProvider).now().toLocal();
    final open = ref.watch(tasksByQueryProvider(const TaskQuery.all()));
    final completed = ref.watch(
      tasksByQueryProvider(const TaskQuery.completed()),
    );
    final error = open.hasError
        ? open.error
        : completed.hasError
        ? completed.error
        : null;
    return (
      today: DateTime(now.year, now.month, now.day),
      projects: ref.watch(projectsProvider),
      tasks: mergeTasks(open.value ?? const [], completed.value ?? const []),
      error: error,
      loading: error == null && (!open.hasValue || !completed.hasValue),
    );
  }
}

Map<DateTime, int> scheduledTaskCounts(Iterable<TaskItem> tasks) {
  final counts = <DateTime, int>{};
  for (final task in tasks) {
    final schedule = task.schedule;
    if (schedule == null) {
      continue;
    }
    final date = _dateOnly(schedule.displayDate.toLocal());
    counts.update(date, (value) => value + 1, ifAbsent: () => 1);
  }
  return counts;
}

List<TaskItem> mergeTasks(
  Iterable<TaskItem> open,
  Iterable<TaskItem> completed,
) {
  final tasksById = <String, TaskItem>{};
  for (final task in open) {
    tasksById.putIfAbsent(task.id, () => task);
  }
  for (final task in completed) {
    tasksById.putIfAbsent(task.id, () => task);
  }
  return List<TaskItem>.unmodifiable(tasksById.values);
}

List<TaskItem> scheduledTasks(Iterable<TaskItem> tasks) {
  return [
    for (final task in tasks)
      if (!task.isDeleted && task.schedule != null) task,
  ];
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);
