import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/config/account_providers.dart';
import '../../../app/config/providers.dart';
import '../../../core/db/app_database.dart';
import '../data/collaboration_api.dart';
import '../data/collaboration_repository.dart';
import '../data/shared_access.dart';
import '../domain/collaboration_models.dart';

final collaborationRepositoryProvider = Provider<CollaborationRepository?>((
  ref,
) {
  final account = ref.watch(accountClientProvider);
  final authState = ref.watch(accountAuthStateProvider).value;
  final signedIn =
      (authState?.signedIn ?? false) || account?.currentUserId != null;
  if (account == null || !signedIn) return null;
  return CollaborationRepository(
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

final collaborationEntitiesProvider =
    StreamProvider.family<
      List<Map<String, dynamic>>,
      ({String scopeId, String type, String? taskId})
    >(
      (ref, query) =>
          ref
              .watch(collaborationRepositoryProvider)
              ?.watchEntities(
                query.scopeId,
                query.type,
                taskId: query.taskId,
              ) ??
          Stream.value([]),
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
    StreamProvider.family<List<SyncCommandRow>, String>((ref, scopeId) {
      final repository = ref.watch(collaborationRepositoryProvider);
      if (repository == null) return Stream.value(const []);
      return repository.watchConflicts().map(
        (rows) => rows.where((row) => row.scopeId == scopeId).toList(),
      );
    });
