import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

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
