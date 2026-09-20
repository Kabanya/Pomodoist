import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/billing_dependencies.dart';
import 'package:pomodoist/domain/use_cases/account/pomodoist_retention.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'task_search.dart';

final searchViewModelProvider = NotifierProvider.autoDispose
    .family<SearchViewModel, SearchState, (Object, String)>(
      SearchViewModel.new,
    );

class SearchState {
  SearchState({
    required this.query,
    required this.projectId,
    required this.status,
    required List<ProjectItem> projects,
    required List<TaskItem> allTasks,
    required List<TaskItem> items,
    required this.loading,
    required this.hasError,
  }) : projects = List.unmodifiable(projects),
       allTasks = List.unmodifiable(allTasks),
       items = List.unmodifiable(items);
  final String query;
  final String? projectId;
  final TaskSearchStatus status;
  final List<ProjectItem> projects;
  final List<TaskItem> allTasks;
  final List<TaskItem> items;
  final bool loading;
  final bool hasError;
}

class SearchViewModel extends Notifier<SearchState> {
  SearchViewModel(this.identity) : _query = identity.$2;
  final (Object, String) identity;
  String _query;
  String? _projectId;
  TaskSearchStatus _status = TaskSearchStatus.open;
  @override
  SearchState build() {
    final open = ref.watch(tasksByQueryProvider(const TaskQuery.all()));
    final completed = ref.watch(
      tasksByQueryProvider(const TaskQuery.completed()),
    );
    final projects =
        (ref.watch(projectsProvider).value ?? const <ProjectItem>[])
            .where((project) => !project.isDeleted)
            .toList();
    final projectId = projects.any((project) => project.id == _projectId)
        ? _projectId
        : null;
    final overview = ref.watch(accountOverviewProvider);
    final billing = ref.watch(billingAccessProvider).value;
    final cutoff = overview.hasValue && billing != null && !billing.loading
        ? pomodoistTaskHistoryCutoff(
            overview.value,
            hasLocalPaidEntitlement: billing.hasActiveEntitlement,
          )
        : null;
    final allTasks = <String, TaskItem>{
      for (final task in open.value ?? const <TaskItem>[]) task.id: task,
      for (final task in completed.value ?? const <TaskItem>[]) task.id: task,
    }.values.toList();
    final sources = [
      if (_status != TaskSearchStatus.completed) open,
      if (_status != TaskSearchStatus.open) completed,
    ];
    return SearchState(
      query: _query.trim(),
      projectId: projectId,
      status: _status,
      projects: projects,
      allTasks: allTasks,
      items: filterTaskSearch(
        allTasks,
        query: _query,
        projectId: projectId,
        status: _status,
        completedTaskCutoff: cutoff,
      ),
      loading: sources.any((s) => s.isLoading),
      hasError: sources.any((s) => s.hasError),
    );
  }

  void setQuery(String query) {
    _query = query;
    ref.invalidateSelf();
  }

  void setProject(String? id) {
    _projectId = id;
    ref.invalidateSelf();
  }

  void setStatus(TaskSearchStatus status) {
    _status = status;
    ref.invalidateSelf();
  }

  void clearFilters() {
    _projectId = null;
    _status = TaskSearchStatus.all;
    ref.invalidateSelf();
  }

  void retry() {
    ref.invalidate(tasksByQueryProvider(const TaskQuery.all()));
    ref.invalidate(tasksByQueryProvider(const TaskQuery.completed()));
  }
}
