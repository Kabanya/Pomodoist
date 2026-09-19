import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/billing_dependencies.dart';
import 'package:pomodoist/domain/use_cases/account/pomodoist_retention.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/productivity/productivity_models.dart';
import 'browse_summary.dart';
import 'package:pomodoist/domain/use_cases/tasks/project_list_data.dart';

typedef BrowseState = ({
  AsyncValue<ProductivitySummary> summary,
  BrowsePeriod period,
});
final browseViewModelProvider = NotifierProvider.autoDispose
    .family<BrowseViewModel, BrowseState, Object>(BrowseViewModel.new);

class BrowseViewModel extends Notifier<BrowseState> {
  BrowseViewModel(this.identity);
  final Object identity;
  BrowsePeriod _period = BrowsePeriod.today;
  @override
  BrowseState build() =>
      (summary: ref.watch(productivitySummaryProvider), period: _period);
  void setPeriod(BrowsePeriod period) {
    _period = period;
    ref.invalidateSelf();
  }

  void retry() => ref.invalidate(productivitySummaryProvider);
}

typedef BrowseProjectsState = ({
  AsyncValue<List<ProjectItem>> projects,
  AsyncValue<List<TaskItem>> tasks,
  List<ProjectListRow> rows,
  Map<String, int>? counts,
});
final browseProjectsViewModelProvider =
    NotifierProvider.autoDispose<BrowseProjectsViewModel, BrowseProjectsState>(
      BrowseProjectsViewModel.new,
    );

class BrowseProjectsViewModel extends Notifier<BrowseProjectsState> {
  @override
  BrowseProjectsState build() {
    final projects = ref.watch(projectsProvider);
    final tasks = ref.watch(tasksByQueryProvider(const TaskQuery.all()));
    return (
      projects: projects,
      tasks: tasks,
      rows: List.unmodifiable(
        projectRows([
          for (final p in projects.value ?? const <ProjectItem>[])
            if (p.id != inboxProjectId && !p.isArchived && !p.isDeleted) p,
        ]),
      ),
      counts: tasks.hasValue
          ? Map.unmodifiable(countOpenTasksByProject(tasks.value!))
          : null,
    );
  }

  void retryProjects() => ref.invalidate(projectsProvider);
  void retryTasks() =>
      ref.invalidate(tasksByQueryProvider(const TaskQuery.all()));
}

final browseLabelsViewModelProvider =
    NotifierProvider.autoDispose<
      BrowseLabelsViewModel,
      AsyncValue<List<LabelItem>>
    >(BrowseLabelsViewModel.new);

class BrowseLabelsViewModel extends Notifier<AsyncValue<List<LabelItem>>> {
  @override
  AsyncValue<List<LabelItem>> build() => ref.watch(labelsProvider);
  void retry() => ref.invalidate(labelsProvider);
}

final syncQueueViewModelProvider =
    NotifierProvider.autoDispose<SyncQueueViewModel, AsyncValue<int>>(
      SyncQueueViewModel.new,
    );

class SyncQueueViewModel extends Notifier<AsyncValue<int>> {
  @override
  AsyncValue<int> build() =>
      ref.watch(pendingSyncCommandsProvider).whenData((rows) => rows.length);
  void retry() => ref.invalidate(pendingSyncCommandsProvider);
}

final completedTasksViewModelProvider =
    NotifierProvider.autoDispose<CompletedTasksViewModel, DateTime?>(
      CompletedTasksViewModel.new,
    );

class CompletedTasksViewModel extends Notifier<DateTime?> {
  @override
  DateTime? build() {
    final overview = ref.watch(accountOverviewProvider);
    final billing = ref.watch(billingViewModelProvider);
    return overview.hasValue && !billing.loading
        ? pomodoistTaskHistoryCutoff(
            overview.value,
            hasLocalPaidEntitlement: billing.hasActiveEntitlement,
          )
        : null;
  }

  bool includes(TaskItem task) =>
      state == null ||
      !(task.completedAt ?? task.updatedAt).toUtc().isBefore(state!);
}

final overdueViewModelProvider =
    NotifierProvider.autoDispose<OverdueViewModel, AsyncValue<List<TaskItem>>>(
      OverdueViewModel.new,
    );

class OverdueViewModel extends Notifier<AsyncValue<List<TaskItem>>> {
  @override
  AsyncValue<List<TaskItem>> build() => ref.watch(overdueTasksProvider);
  void retry() => ref.invalidate(tasksByQueryProvider(const TaskQuery.all()));
}
