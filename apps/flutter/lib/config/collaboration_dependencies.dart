import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/collaboration/collaboration_repository.dart';
import 'package:pomodoist/data/repositories/collaboration/drift_collaboration_repository.dart';
import 'package:pomodoist/data/services/collaboration/collaboration_api.dart';
import 'package:pomodoist/data/services/local/shared_access.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_conflict.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_responses.dart';

export 'package:pomodoist/config/providers.dart'
    show projectRepositoryProvider;

final collaborationRepositoryProvider = Provider<CollaborationRepository?>((
  ref,
) {
  final account = ref.watch(accountClientProvider);
  final authState = ref.watch(accountAuthStateProvider).value;
  final signedIn =
      (authState?.signedIn ?? false) || account?.currentUserId != null;
  if (account == null || !signedIn) return null;
  return DriftCollaborationRepository(
    db: ref.watch(appDatabaseProvider),
    api: CollaborationApi.account(account),
    queue: ref.watch(syncQueueRepositoryProvider),
    synchronize: () async {
      await ref.read(accountSyncEngineProvider)?.syncNow();
    },
  );
});

final sharedScopesProvider = StreamProvider<List<SharedScope>>(
  (ref) =>
      ref.watch(collaborationRepositoryProvider)?.watchScopes() ??
      Stream.value([]),
);

final collaborationCommentsProvider =
    StreamProvider.family<
      List<CollaborationComment>,
      ({String scopeId, String? taskId})
    >(
      (ref, query) =>
          ref
              .watch(collaborationRepositoryProvider)
              ?.watchComments(query.scopeId, taskId: query.taskId) ??
          Stream.value(const []),
    );

final collaborationFocusContributionsProvider =
    StreamProvider.family<
      List<CollaborationFocusContribution>,
      ({String scopeId, String? taskId})
    >(
      (ref, query) =>
          ref
              .watch(collaborationRepositoryProvider)
              ?.watchFocusContributions(query.scopeId, taskId: query.taskId) ??
          Stream.value(const []),
    );

final collaborationActorIdProvider = FutureProvider<String>(
  (ref) => SharedAccess(ref.watch(appDatabaseProvider)).actorId(),
);

final sharedScopeForProjectProvider = Provider.family<SharedScope?, String>((
  ref,
  projectId,
) {
  final scopes = ref.watch(sharedScopesProvider).value ?? const <SharedScope>[];
  for (final scope in scopes) {
    if (scope.rootProjectId == projectId) return scope;
  }
  return null;
});

final sharedScopeProvider = Provider.family<SharedScope?, String>((
  ref,
  scopeId,
) {
  final scopes = ref.watch(sharedScopesProvider).value ?? const <SharedScope>[];
  for (final scope in scopes) {
    if (scope.id == scopeId) return scope;
  }
  return null;
});

final scopeConflictsProvider =
    StreamProvider.family<List<CollaborationConflict>, String>((ref, scopeId) {
      final repository = ref.watch(collaborationRepositoryProvider);
      if (repository == null) return Stream.value(const []);
      return repository.watchConflicts().map(
        (rows) => rows.where((row) => row.scopeId == scopeId).toList(),
      );
    });

// Anonymous project links use the configured client without requiring a session.
final publicCollaborationRepositoryProvider =
    Provider<CollaborationRepository?>((ref) {
      final account = ref.watch(accountClientProvider);
      if (account == null) return null;
      return DriftCollaborationRepository(
        db: ref.watch(appDatabaseProvider),
        api: CollaborationApi.account(account),
        queue: ref.watch(syncQueueRepositoryProvider),
        synchronize: () async {},
      );
    });

final collaborationConflictsProvider =
    StreamProvider<List<CollaborationConflict>>(
      (ref) =>
          ref.watch(collaborationRepositoryProvider)?.watchConflicts() ??
          Stream.value(const []),
    );
