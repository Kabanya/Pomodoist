import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'today_tasks.dart';

typedef TodayState = ({DateTime day, bool hasCompleted});
final todayViewModelProvider =
    NotifierProvider.autoDispose<TodayViewModel, TodayState>(
      TodayViewModel.new,
    );

class TodayViewModel extends Notifier<TodayState> {
  @override
  TodayState build() {
    final clock = ref.watch(clockProvider);
    final day = ref.watch(
      focusTickerProvider.select((ticker) {
        final now = (ticker.value ?? clock.now()).toLocal();
        return DateTime(now.year, now.month, now.day);
      }),
    );
    final completed = ref.watch(
      tasksByQueryProvider(const TaskQuery.completed()),
    );
    return (
      day: day,
      hasCompleted: completedTasksForDay(
        completed.value ?? const [],
        day,
      ).isNotEmpty,
    );
  }
}

typedef TodayContextState = ({
  bool showSummary,
  bool showFocus,
  int tasks,
  int plannedIntervals,
  int focusSeconds,
});
final todayContextViewModelProvider = NotifierProvider.autoDispose
    .family<TodayContextViewModel, TodayContextState, TaskQuery>(
      TodayContextViewModel.new,
    );

class TodayContextViewModel extends Notifier<TodayContextState> {
  TodayContextViewModel(this.query);
  final TaskQuery query;
  @override
  TodayContextState build() {
    final tasks = ref.watch(tasksByQueryProvider(query));
    final summary = ref.watch(productivitySummaryProvider);
    return (
      showSummary:
          !tasks.isLoading &&
          !tasks.hasError &&
          tasks.hasValue &&
          !summary.isLoading &&
          !summary.hasError &&
          summary.hasValue,
      showFocus: ref.watch(todayFocusStripVisibleProvider),
      tasks: tasks.value?.length ?? 0,
      plannedIntervals: summary.value?.plannedFocusIntervals ?? 0,
      focusSeconds: summary.value?.totalFocusSeconds ?? 0,
    );
  }
}

final completedTodayViewModelProvider = NotifierProvider.autoDispose
    .family<CompletedTodayViewModel, List<TaskItem>, DateTime>(
      CompletedTodayViewModel.new,
    );

class CompletedTodayViewModel extends Notifier<List<TaskItem>> {
  CompletedTodayViewModel(this.day);
  final DateTime day;
  @override
  List<TaskItem> build() {
    final completed = ref.watch(
      tasksByQueryProvider(const TaskQuery.completed()),
    );
    return completed.isLoading || completed.hasError
        ? const []
        : List.unmodifiable(
            completedTasksForDay(completed.value ?? const [], day),
          );
  }
}
