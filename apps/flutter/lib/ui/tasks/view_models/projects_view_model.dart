import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/tasks/project_hierarchy.dart';
import 'package:pomodoist/domain/use_cases/tasks/project_list_data.dart';

typedef ProjectsState = ({
  AsyncValue<List<ProjectItem>> projects,
  AsyncValue<List<LabelItem>> labels,
  Map<String, int> taskCounts,
  bool archivedOnly,
});
final projectsViewModelProvider = NotifierProvider.autoDispose
    .family<ProjectsViewModel, ProjectsState, Object>(ProjectsViewModel.new);

class ProjectsViewModel extends Notifier<ProjectsState> {
  ProjectsViewModel(this.identity);
  final Object identity;
  String _search = '';
  bool _archivedOnly = false;
  @override
  ProjectsState build() {
    final search = _search.trim().toLowerCase();
    return (
      projects: ref
          .watch(projectsProvider)
          .whenData(
            (items) => List.unmodifiable(
              items.where(
                (p) =>
                    p.id != inboxProjectId &&
                    p.isArchived == _archivedOnly &&
                    (search.isEmpty || p.name.toLowerCase().contains(search)),
              ),
            ),
          ),
      labels: ref
          .watch(labelsProvider)
          .whenData(
            (items) => List.unmodifiable(
              items.where(
                (l) => search.isEmpty || l.name.toLowerCase().contains(search),
              ),
            ),
          ),
      taskCounts: Map.unmodifiable(
        countOpenTasksByProject(
          ref.watch(tasksByQueryProvider(const TaskQuery.all())).value ??
              const [],
        ),
      ),
      archivedOnly: _archivedOnly,
    );
  }

  void search(String text) {
    _search = text;
    ref.invalidateSelf();
  }

  void setArchivedOnly(bool value) {
    _archivedOnly = value;
    ref.invalidateSelf();
  }

  Future<void> deleteLabel(String id) async {
    (await ref.read(labelRepositoryProvider).deleteLabel(id)).getOrThrow();
  }
}

typedef ProjectContextState = ({
  List<ProjectItem> projects,
  Map<String, String?> parents,
  List<ProjectItem> siblings,
  int index,
  bool hasChildren,
});
final projectContextViewModelProvider = NotifierProvider.autoDispose
    .family<ProjectContextViewModel, ProjectContextState, String>(
      ProjectContextViewModel.new,
    );

class ProjectContextViewModel extends Notifier<ProjectContextState> {
  ProjectContextViewModel(this.projectId);
  final String projectId;
  @override
  ProjectContextState build() {
    final projects = ref.watch(projectsProvider).value ?? const <ProjectItem>[];
    final parents = projectParents(projects);
    final siblings =
        projects
            .where(
              (p) =>
                  p.id != inboxProjectId &&
                  !p.isDeleted &&
                  parents[p.id] == parents[projectId],
            )
            .toList()
          ..sort(compareProjects);
    return (
      projects: List.unmodifiable(projects),
      parents: Map.unmodifiable(parents),
      siblings: List.unmodifiable(siblings),
      index: siblings.indexWhere((p) => p.id == projectId),
      hasChildren: projects.any((p) => p.parentId == projectId && !p.isDeleted),
    );
  }

  Future<void> delete() async {
    (await ref.read(projectRepositoryProvider).deleteProject(projectId))
        .getOrThrow();
  }

  Future<void> update(UpdateProjectPatch patch) async {
    (await ref.read(projectRepositoryProvider).updateProject(projectId, patch))
        .getOrThrow();
  }
}

final projectTreeViewModelProvider =
    NotifierProvider.autoDispose<
      ProjectTreeViewModel,
      AsyncValue<List<ProjectItem>>
    >(ProjectTreeViewModel.new);

class ProjectTreeViewModel extends Notifier<AsyncValue<List<ProjectItem>>> {
  @override
  AsyncValue<List<ProjectItem>> build() => ref.watch(projectsProvider);
  Future<void> move(String id, ProjectMoveTarget target) async {
    (await ref
            .read(projectRepositoryProvider)
            .moveProject(
              id,
              parentId: target.parentId,
              beforeProjectId: target.beforeProjectId,
            ))
        .getOrThrow();
  }
}
