import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/tasks/project_colors.dart';

enum NamedItemKind { project, label, renameProject }

typedef ProjectCreationState = ({List<ProjectItem> projects, String color});
final projectCreationViewModelProvider =
    NotifierProvider.autoDispose<
      ProjectCreationViewModel,
      ProjectCreationState
    >(ProjectCreationViewModel.new);

class ProjectCreationViewModel extends Notifier<ProjectCreationState> {
  @override
  ProjectCreationState build() {
    final projects = ref.watch(projectsProvider).value ?? const <ProjectItem>[];
    return (
      projects: List.unmodifiable(projects),
      color: nextProjectColor(projects),
    );
  }
}

final namedItemViewModelProvider = NotifierProvider.autoDispose
    .family<NamedItemViewModel, AsyncValue<void>, Object>(
      NamedItemViewModel.new,
    );

class NamedItemViewModel extends Notifier<AsyncValue<void>> {
  NamedItemViewModel(this.identity);
  final Object identity;
  @override
  AsyncValue<void> build() => const AsyncData(null);
  Future<bool> submit({
    required NamedItemKind kind,
    required String name,
    String? color,
    String? icon,
    String? parentId,
    String? projectId,
  }) async {
    if (state.isLoading || name.trim().isEmpty) return false;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      switch (kind) {
        case NamedItemKind.project:
          (await ref
                  .read(projectRepositoryProvider)
                  .createProject(name.trim(), color: color, parentId: parentId))
              .getOrThrow();
        case NamedItemKind.label:
          (await ref
                  .read(labelRepositoryProvider)
                  .createLabel(name.trim(), icon: icon))
              .getOrThrow();
        case NamedItemKind.renameProject:
          (await ref
                  .read(projectRepositoryProvider)
                  .updateProject(
                    projectId!,
                    UpdateProjectPatch(name: name.trim()),
                  ))
              .getOrThrow();
      }
    });
    if (ref.mounted) state = result;
    return !result.hasError;
  }
}
