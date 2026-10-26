import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/data/repositories/account/ai_quota_repository.dart';
import 'package:pomodoist/data/repositories/account/remote_ai_quota_repository.dart';

final aiQuotaRepositoryProvider = Provider<AiQuotaRepository?>((ref) {
  final auth = ref.watch(accountAuthStateProvider).value;
  final account = ref.watch(accountClientProvider);
  final owner = account?.currentUserId;
  if (owner == null ||
      auth?.signedIn == false ||
      auth?.session?.userId != null && auth!.session!.userId != owner) {
    return null;
  }
  return RemoteAiQuotaRepository(
    client: ref.watch(accountOverviewSupabaseClientProvider),
    owner: owner,
    currentUserId: () => account?.currentUserId,
    timeout: ref.watch(accountRequestTimeoutProvider),
  );
});
