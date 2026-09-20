import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'upcoming_day_groups.dart';

typedef UpcomingState = ({
  DateTime today,
  DateTime? selectedDay,
  AsyncValue<List<ProjectItem>> projects,
  List<TaskItem> tasks,
  List<UpcomingDayGroup> groups,
  Map<DateTime, int> scheduledCounts,
  Object? error,
  bool loading,
});
final upcomingViewModelProvider = NotifierProvider.autoDispose
    .family<UpcomingViewModel, UpcomingState, DateTime?>(UpcomingViewModel.new);

class UpcomingViewModel extends Notifier<UpcomingState> {
  UpcomingViewModel(this.selectedDay);

  final DateTime? selectedDay;

  @override
  UpcomingState build() {
    final now =
        (ref.watch(taskTimeTickerProvider).value ??
                ref.read(clockProvider).now())
            .toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final open = ref.watch(tasksByQueryProvider(const TaskQuery.all()));
    final completed = ref.watch(
      tasksByQueryProvider(const TaskQuery.completed()),
    );
    final error = open.hasError
        ? open.error
        : completed.hasError
        ? completed.error
        : null;
    final tasks = mergeTasks(
      open.value ?? const [],
      completed.value ?? const [],
    );
    final scheduled = scheduledTasks(tasks);
    return (
      today: today,
      selectedDay: selectedDay,
      projects: ref.watch(projectsProvider),
      tasks: tasks,
      groups: List.unmodifiable(
        buildUpcomingDayGroups(
          scheduled,
          selectedDate: selectedDay,
          visibleFromDate: selectedDay ?? today,
        ),
      ),
      scheduledCounts: Map.unmodifiable(scheduledTaskCounts(scheduled)),
      error: error,
      loading: error == null && (!open.hasValue || !completed.hasValue),
    );
  }

  /// Rendering-only projection for rows that are animating out. Retained tasks
  /// may appear temporarily, but actions revalidate against the live
  /// repository by task ID, so a retained copy never makes a stale action.
  List<UpcomingDayGroup> groupsWithRetained(Iterable<TaskItem> retained) {
    if (retained.isEmpty) {
      return state.groups;
    }
    return buildUpcomingDayGroups(
      scheduledTasks(mergeTasks(state.tasks, retained)),
      selectedDate: state.selectedDay,
      visibleFromDate: state.selectedDay ?? state.today,
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
