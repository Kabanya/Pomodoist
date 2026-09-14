import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/account_providers.dart';
import '../../../app/providers.dart';
import '../data/collaboration_api.dart';
import '../data/collaboration_repository.dart';
import '../domain/collaboration_models.dart';

final collaborationRepositoryProvider = Provider<CollaborationRepository?>((
  ref,
) {
  final account = ref.watch(accountClientProvider);
  if (account == null || account.currentUserId == null) return null;
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
