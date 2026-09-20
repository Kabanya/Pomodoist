import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'task_search.dart';

/// Stable identities keep keyboard selection attached to the same local result.
List<({String id, String title})> taskSearchPaletteResults(
  Iterable<TaskItem> tasks,
  Iterable<ProjectItem> projects,
  String query, {
  String Function(ProjectItem project)? projectTitle,
}) {
  final search = query.trim().toLowerCase();
  return [
    if (search.isNotEmpty) ...[
      for (final task in filterTaskSearch(tasks, query: query).take(6))
        (id: 'task:${task.id}', title: task.content),
      for (final project
          in projects
              .where(
                (project) =>
                    !project.isDeleted &&
                    !project.isArchived &&
                    (project.name.toLowerCase().contains(search) ||
                        (projectTitle != null &&
                            projectTitle(
                              project,
                            ).toLowerCase().contains(search))),
              )
              .take(3))
        (
          id: 'project:${project.id}',
          title: projectTitle == null ? project.name : projectTitle(project),
        ),
    ],
  ];
}

String? taskSearchPaletteSelection(
  List<String> ids,
  String? selected,
  int offset,
) {
  if (ids.isEmpty) return null;
  final index = ids.indexOf(selected ?? '');
  if (index < 0) {
    return offset == 0 ? null : (offset < 0 ? ids.last : ids.first);
  }
  return ids[(index + offset) % ids.length];
}

bool taskSearchPaletteCanActivate(
  List<String> currentIds,
  String id,
  String renderedQuery,
  String currentQuery,
) => renderedQuery == currentQuery && currentIds.contains(id);

final class TaskSearchPaletteState {
  const TaskSearchPaletteState({
    this.tasks = const [],
    this.projects = const [],
    this.focusRunning = false,
    this.loading = false,
    this.hasError = false,
  });

  final List<TaskItem> tasks;
  final List<ProjectItem> projects;
  final bool focusRunning;
  final bool loading;
  final bool hasError;
}

final taskSearchPaletteViewModelProvider =
    NotifierProvider.autoDispose<
      TaskSearchPaletteViewModel,
      TaskSearchPaletteState
    >(TaskSearchPaletteViewModel.new);

class TaskSearchPaletteViewModel extends Notifier<TaskSearchPaletteState> {
  @override
  TaskSearchPaletteState build() {
    final tasks = ref.watch(tasksByQueryProvider(const TaskQuery.all()));
    final projects = ref.watch(projectsProvider);
    final run = ref.watch(activeFocusRunProvider);
    ref.watch(lastFocusPresetIdProvider);
    return TaskSearchPaletteState(
      tasks: tasks.value ?? const [],
      projects: projects.value ?? const [],
      focusRunning: run.value != null,
      loading: tasks.isLoading || projects.isLoading || run.isLoading,
      hasError: tasks.hasError || projects.hasError || run.hasError,
    );
  }

  List<({String id, String title})> results(
    String query, {
    String Function(ProjectItem project)? projectTitle,
  }) => taskSearchPaletteResults(
    state.tasks,
    state.projects,
    query,
    projectTitle: projectTitle,
  );

  bool resultExists(String id) {
    if (id.startsWith('task:')) {
      final taskId = id.substring(5);
      return state.tasks.any(
        (task) => task.id == taskId && !task.isDeleted && !task.isCompleted,
      );
    }
    if (id.startsWith('project:')) {
      final projectId = id.substring(8);
      return state.projects.any(
        (project) =>
            project.id == projectId &&
            !project.isDeleted &&
            !project.isArchived,
      );
    }
    return true;
  }

  Future<void> startFocusIfNeeded() async {
    if (state.focusRunning) return;
    final presets = await ref.read(focusPresetsProvider.future);
    if (!ref.mounted) return;
    final preset = selectedFocusPresetOrDefault(
      presets,
      ref.read(lastFocusPresetIdProvider),
    );
    final repository = ref.read(focusRepositoryProvider);
    if (await repository.watchActiveRun().first == null) {
      (await repository.startRun(
        StartFocusRunInput(presetId: preset?.id),
      )).getOrThrow();
    }
  }

  void retry() {
    ref.invalidate(tasksByQueryProvider(const TaskQuery.all()));
    ref.invalidate(projectsProvider);
    ref.invalidate(activeFocusRunProvider);
  }
}
