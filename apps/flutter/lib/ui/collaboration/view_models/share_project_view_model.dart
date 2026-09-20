import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/collaboration_dependencies.dart';
import 'package:pomodoist/data/repositories/collaboration/collaboration_repository.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_conflict.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_responses.dart';
import 'package:pomodoist/utils/result.dart';

final class ShareProjectState {
  ShareProjectState({
    this.scope,
    this.actorId,
    this.busy = false,
    this.sharedJustNow = false,
    List<CollaborationInvitation> invitations = const [],
    List<CollaborationConflict> conflicts = const [],
  }) : invitations = List.unmodifiable(invitations),
       conflicts = List.unmodifiable(conflicts);
  final SharedScope? scope;
  final String? actorId;
  final bool busy;
  final bool sharedJustNow;
  final List<CollaborationInvitation> invitations;
  final List<CollaborationConflict> conflicts;
  ShareProjectState copyWith({
    SharedScope? scope,
    String? actorId,
    bool? busy,
    bool? sharedJustNow,
    List<CollaborationInvitation>? invitations,
    List<CollaborationConflict>? conflicts,
  }) => ShareProjectState(
    scope: scope ?? this.scope,
    actorId: actorId ?? this.actorId,
    busy: busy ?? this.busy,
    sharedJustNow: sharedJustNow ?? this.sharedJustNow,
    invitations: invitations ?? this.invitations,
    conflicts: conflicts ?? this.conflicts,
  );
}

final shareProjectViewModelProvider = NotifierProvider.autoDispose
    .family<ShareProjectViewModel, ShareProjectState, String>(
      ShareProjectViewModel.new,
    );

class ShareProjectViewModel extends Notifier<ShareProjectState> {
  ShareProjectViewModel(this.projectId);
  final String projectId;
  CollaborationRepository? _repository;
  var _generation = 0;
  @override
  ShareProjectState build() {
    _repository = ref.watch(collaborationRepositoryProvider);
    final generation = ++_generation;
    ref.onDispose(() => _generation++);
    ref.listen(sharedScopeForProjectProvider(projectId), (previous, next) {
      state = ShareProjectState(
        scope: next,
        actorId: state.actorId,
        busy: state.busy,
        sharedJustNow: state.sharedJustNow,
        invitations: state.invitations,
        conflicts: _conflicts(next?.id),
      );
      if (previous?.id != next?.id) _loadInvitations(generation);
    });
    ref.listen(collaborationActorIdProvider, (_, next) {
      state = state.copyWith(actorId: next.value);
    });
    ref.listen(collaborationConflictsProvider, (_, next) {
      state = state.copyWith(conflicts: _conflicts(state.scope?.id));
    });
    final scope = ref.read(sharedScopeForProjectProvider(projectId));
    Future.microtask(() => _loadInvitations(generation));
    return ShareProjectState(
      scope: scope,
      actorId: ref.read(collaborationActorIdProvider).value,
      conflicts: _conflicts(scope?.id),
    );
  }

  List<CollaborationConflict> _conflicts(String? scopeId) =>
      (ref.read(collaborationConflictsProvider).value ??
              const <CollaborationConflict>[])
          .where((row) => row.scopeId == scopeId)
          .toList();

  Future<void> _loadInvitations(int generation) async {
    final repository = _repository;
    final scope = state.scope;
    if (repository == null || scope == null || !scope.canManage) return;
    final result = await repository.members(scope.id);
    if (!ref.mounted ||
        generation != _generation ||
        state.scope?.id != scope.id) {
      return;
    }
    if (result case Success(:final value)) {
      state = state.copyWith(
        invitations: pendingInvitations(
          value.invitations,
          DateTime.now().toUtc(),
        ),
      );
    }
  }

  Future<Result<void>> share() => _run((repository) async {
    (await repository.share(projectId)).getOrThrow();
    if (ref.mounted) state = state.copyWith(sharedJustNow: true);
  });
  Future<Result<CollaborationInviteOutcome>> invite(
    String email,
    CollaborationRole role,
  ) => _run((repository) async {
    final result = (await repository.invite(
      _scopeId,
      email: email.trim(),
      role: role,
    )).getOrThrow();
    await _loadInvitations(_generation);
    return result;
  });
  Future<Result<void>> revokeInvitation(String id) => _run((repository) async {
    (await repository.revokeInvitation(_scopeId, id)).getOrThrow();
    await _loadInvitations(_generation);
  });
  Future<Result<void>> setRole(String userId, CollaborationRole role) =>
      _run((repository) async {
        (await repository.setMemberRole(_scopeId, userId, role)).getOrThrow();
      });
  Future<Result<void>> remove(String userId) => _run((repository) async {
    (await repository.removeMember(_scopeId, userId)).getOrThrow();
  });
  Future<Result<void>> transfer(String userId) => _run((repository) async {
    (await repository.transferOwnership(_scopeId, userId)).getOrThrow();
  });
  Future<Result<void>> leave() => _run((repository) async {
    (await repository.leaveScope(_scopeId)).getOrThrow();
  });
  Future<Result<void>> delete() => _run((repository) async {
    (await repository.deleteScope(_scopeId)).getOrThrow();
  });
  Future<Result<void>> unshare() => _run((repository) async {
    (await repository.unshare(_scopeId)).getOrThrow();
  });
  Future<Result<void>> resolveConflict(
    CollaborationConflict command, {
    required bool keepLocal,
  }) => _run((repository) async {
    (await repository.resolveConflict(
      command,
      keepLocal: keepLocal,
    )).getOrThrow();
  });
  String get _scopeId =>
      state.scope?.id ?? (throw const CollaborationException('unavailable'));
  Future<Result<T>> _run<T>(
    Future<T> Function(CollaborationRepository) action,
  ) async {
    if (state.busy) {
      return Failure(
        StateError('An operation is already running.'),
        StackTrace.current,
      );
    }
    final repository = _repository;
    if (repository == null) {
      final signedIn = ref.read(accountSignedInProvider);
      return Failure(
        CollaborationException(signedIn ? 'unavailable' : 'unauthenticated'),
        StackTrace.current,
      );
    }
    final generation = _generation;
    state = state.copyWith(busy: true);
    final result = await Result.capture(() => action(repository));
    if (ref.mounted && generation == _generation) {
      state = state.copyWith(busy: false);
    }
    return result;
  }
}

/// Keep one current, unanswered invitation per email, preferring its latest expiry.
List<CollaborationInvitation> pendingInvitations(
  List<CollaborationInvitation> invitations,
  DateTime now,
) {
  final byEmail = <String, CollaborationInvitation>{};
  for (final invitation in invitations) {
    if (!invitation.isPending(now)) continue;
    final email = invitation.email ?? '';
    final kept = byEmail[email];
    final expiresAt = invitation.expiresAt!;
    if (kept == null || !kept.expiresAt!.isAfter(expiresAt)) {
      byEmail[email] = invitation;
    }
  }
  return byEmail.values.toList();
}
