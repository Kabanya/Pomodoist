import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/collaboration_dependencies.dart';
import 'package:pomodoist/data/repositories/collaboration/collaboration_repository.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_responses.dart';
import 'package:pomodoist/utils/result.dart';

final class TaskCollaborationState {
  TaskCollaborationState({
    this.scope,
    this.actorId,
    List<CollaborationComment> comments = const [],
  }) : comments = List.unmodifiable(comments);
  final SharedScope? scope;
  final String? actorId;
  final List<CollaborationComment> comments;
  List<CollaborationMember> get editors => [
    for (final member in scope?.members ?? const <CollaborationMember>[])
      if (member.role.canEdit) member,
  ];
  bool canDeleteComment(CollaborationComment comment) =>
      scope != null &&
      scope!.canEdit &&
      (comment.createdBy == actorId || scope!.canManage);
}

typedef TaskCollaborationQuery = ({String taskId, String? scopeId});
final taskCollaborationViewModelProvider = NotifierProvider.autoDispose
    .family<
      TaskCollaborationViewModel,
      TaskCollaborationState,
      TaskCollaborationQuery
    >(TaskCollaborationViewModel.new);

class TaskCollaborationViewModel extends Notifier<TaskCollaborationState> {
  TaskCollaborationViewModel(this.query);
  final TaskCollaborationQuery query;
  CollaborationRepository? _repository;
  @override
  TaskCollaborationState build() {
    final scopeId = query.scopeId;
    if (scopeId == null) {
      _repository = null;
      return TaskCollaborationState();
    }
    _repository = ref.watch(collaborationRepositoryProvider);
    return TaskCollaborationState(
      scope: ref.watch(sharedScopeProvider(scopeId)),
      actorId: ref.watch(collaborationActorIdProvider).value,
      comments:
          ref
              .watch(
                collaborationCommentsProvider((
                  scopeId: scopeId,
                  taskId: query.taskId,
                )),
              )
              .value ??
          const [],
    );
  }

  Future<Result<bool>> sendComment(String text) async {
    final repository = _repository;
    final scopeId = query.scopeId;
    final body = text.trim();
    if (repository == null || scopeId == null || body.isEmpty) {
      return const Success(false);
    }
    return Result.capture(() async {
      (await repository.comment(scopeId, query.taskId, body)).getOrThrow();
      return true;
    });
  }

  Future<Result<void>> deleteComment(String id) async {
    final repository = _repository;
    final scopeId = query.scopeId;
    if (repository == null || scopeId == null) return const Success(null);
    return repository.deleteComment(scopeId, id);
  }

  Future<Result<void>> setAssignees(Set<String> ids) async =>
      _repository == null
      ? const Success(null)
      : _repository!.setAssignees(query.taskId, ids);
}
