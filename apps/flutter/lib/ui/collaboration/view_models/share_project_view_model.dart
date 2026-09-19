import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/collaboration_dependencies.dart';
import 'package:pomodoist/data/repositories/collaboration/collaboration_repository.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_conflict.dart';
import 'package:pomodoist/utils/result.dart';

final class ShareProjectState {
  ShareProjectState({
    this.scope,
    this.actorId,
    this.busy = false,
    this.sharedJustNow = false,
    List<Map<String, dynamic>> invitations = const [],
    List<CollaborationConflict> conflicts = const [],
  }) : invitations = List.unmodifiable(
         invitations.map(Map<String, dynamic>.unmodifiable),
       ),
       conflicts = List.unmodifiable(conflicts);
  final SharedScope? scope;
  final String? actorId;
  final bool busy;
  final bool sharedJustNow;
  final List<Map<String, dynamic>> invitations;
  final List<CollaborationConflict> conflicts;
  ShareProjectState copyWith({
    SharedScope? scope,
    String? actorId,
    bool? busy,
    bool? sharedJustNow,
    List<Map<String, dynamic>>? invitations,
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
    final result = await repository.action('members', {'scopeId': scope.id});
    if (!ref.mounted ||
        generation != _generation ||
        state.scope?.id != scope.id) {
      return;
    }
    if (result case Success(:final value)) {
      state = state.copyWith(
        invitations: pendingInvitations(
          collaborationMaps(value['invitations']),
          DateTime.now().toUtc(),
        ),
      );
    }
  }

  Future<Result<Map<String, dynamic>>> share() => _run((repository) async {
    final result = (await repository.share(projectId)).getOrThrow();
    if (ref.mounted) state = state.copyWith(sharedJustNow: true);
    return result;
  });
  Future<Result<Map<String, dynamic>>> invite(String email, String role) =>
      _run((repository) async {
        final result = (await repository.action('invite', {
          'scopeId': _scopeId,
          'email': email.trim(),
          'role': role,
        })).getOrThrow();
        await _loadInvitations(_generation);
        return result;
      });
  Future<Result<Map<String, dynamic>>> revokeInvitation(String id) =>
      _run((repository) async {
        final result = (await repository.action('invite', {
          'scopeId': _scopeId,
          'invitationId': id,
          'revoke': 'true',
        })).getOrThrow();
        await _loadInvitations(_generation);
        return result;
      });
  Future<Result<Map<String, dynamic>>> setRole(String userId, String role) =>
      _action('role', {'userId': userId, 'role': role});
  Future<Result<Map<String, dynamic>>> remove(String userId) =>
      _action('remove', {'userId': userId});
  Future<Result<Map<String, dynamic>>> transfer(String userId) =>
      _action('transfer', {'userId': userId});
  Future<Result<Map<String, dynamic>>> leave() => _action('leave');
  Future<Result<Map<String, dynamic>>> delete() => _action('delete');
  Future<Result<Map<String, dynamic>>> unshare() => _run(
    (repository) async => (await repository.unshare(_scopeId)).getOrThrow(),
  );
  Future<Result<Map<String, dynamic>>> resolveConflict(
    CollaborationConflict command, {
    required bool keepLocal,
  }) => _run((repository) async {
    (await repository.resolveConflict(
      command,
      keepLocal: keepLocal,
    )).getOrThrow();
    return const {};
  });
  String get _scopeId =>
      state.scope?.id ?? (throw const CollaborationException('unavailable'));
  Future<Result<Map<String, dynamic>>> _action(
    String action, [
    Map<String, dynamic> args = const {},
  ]) => _run(
    (repository) async => (await repository.action(action, {
      'scopeId': _scopeId,
      ...args,
    })).getOrThrow(),
  );
  Future<Result<Map<String, dynamic>>> _run(
    Future<Map<String, dynamic>> Function(CollaborationRepository) action,
  ) async {
    if (state.busy) {
      return Failure(
        StateError('An operation is already running.'),
        StackTrace.current,
      );
    }
    final repository = _repository;
    if (repository == null) {
      final signedIn =
          (ref.read(accountAuthStateProvider).value?.signedIn ?? false) ||
          ref.read(accountClientProvider)?.currentUserId != null;
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
List<Map<String, dynamic>> pendingInvitations(
  List<Map<String, dynamic>> rows,
  DateTime now,
) {
  final byEmail = <String, Map<String, dynamic>>{};
  DateTime? expiry(Map<String, dynamic> row) => row['expiresAt'] is String
      ? DateTime.tryParse(row['expiresAt'])?.toUtc()
      : null;
  for (final invitation in rows) {
    if (invitation['revokedAt'] != null || invitation['acceptedAt'] != null) {
      continue;
    }
    final expiresAt = expiry(invitation);
    if (expiresAt == null || !expiresAt.isAfter(now)) continue;
    final email = invitation['email'] as String? ?? '';
    final kept = byEmail[email];
    final keptExpiry = kept == null ? null : expiry(kept);
    if (keptExpiry == null || !keptExpiry.isAfter(expiresAt)) {
      byEmail[email] = invitation;
    }
  }
  return byEmail.values.toList();
}
