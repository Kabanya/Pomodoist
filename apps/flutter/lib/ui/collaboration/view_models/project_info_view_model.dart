import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/collaboration_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

final class ProjectInfoState {
  const ProjectInfoState({required this.project, this.scope, this.actorId});

  final ProjectItem project;
  final SharedScope? scope;
  final String? actorId;
  int get memberCount => scope?.members.length ?? 1;
}

final projectInfoViewModelProvider = NotifierProvider.autoDispose
    .family<ProjectInfoViewModel, AsyncValue<ProjectInfoState>, String>(
      ProjectInfoViewModel.new,
    );

class ProjectInfoViewModel extends Notifier<AsyncValue<ProjectInfoState>> {
  ProjectInfoViewModel(this.projectId);
  final String projectId;

  @override
  AsyncValue<ProjectInfoState> build() {
    final projects = ref.watch(projectsProvider);
    if (projects.hasError) {
      return AsyncError(projects.error!, projects.stackTrace!);
    }
    if (projects.isLoading) return const AsyncLoading();
    final project = projects.requireValue
        .where((project) => project.id == projectId && !project.isDeleted)
        .firstOrNull;
    if (project == null) {
      return AsyncError(
        const CollaborationException('unavailable'),
        StackTrace.current,
      );
    }
    if (project.scopeId == null) {
      return AsyncData(ProjectInfoState(project: project));
    }

    final scopes = ref.watch(sharedScopesProvider);
    final actor = ref.watch(collaborationActorIdProvider);
    for (final value in [scopes, actor]) {
      if (value.hasError) return AsyncError(value.error!, value.stackTrace!);
    }
    if (scopes.isLoading || actor.isLoading) return const AsyncLoading();
    final scope = scopes.requireValue
        .where((scope) => scope.id == project.scopeId)
        .firstOrNull;
    if (scope == null || scope.data['members'] == null) {
      return AsyncError(
        const CollaborationException('unavailable'),
        StackTrace.current,
      );
    }
    return AsyncData(
      ProjectInfoState(
        project: project,
        scope: scope,
        actorId: actor.requireValue,
      ),
    );
  }

  void reload() {
    ref.invalidate(projectsProvider);
    ref.invalidate(sharedScopesProvider);
    ref.invalidate(collaborationActorIdProvider);
  }
}
