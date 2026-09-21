import 'package:pomodoist/data/repositories/sync/sync_repository.dart';
import 'package:pomodoist/domain/models/account/account_session.dart';
import 'package:pomodoist/utils/result.dart';

import 'strict_fake.dart';

/// In-memory [SyncRepository] double.
///
/// Succeeding calls answer from the mutable fields below, every call is
/// recorded in its `<method>Calls` list, and a call whose `<method>Error`
/// field is non-null fails with that error instead of succeeding.
class FakeSyncRepository extends StrictFake implements SyncRepository {
  final syncNowCalls =
      <({AccountSession session, DateTime? retentionCutoff})>[];

  /// Answer of [syncNow] unless [onSync] or [syncNowError] takes over.
  Result<Set<String>> syncResult = const Success({'task'});

  /// When set, [syncNow] delegates to it instead of answering from
  /// [syncResult].
  Future<Result<Set<String>>> Function(AccountSession session)? onSync;

  /// When non-null, [syncNow] fails with it unless [onSync] takes over.
  Object? syncNowError;

  @override
  Future<Result<Set<String>>> syncNow({
    required AccountSession session,
    required DateTime? retentionCutoff,
  }) async {
    syncNowCalls.add((session: session, retentionCutoff: retentionCutoff));
    final delegate = onSync;
    if (delegate != null) return delegate(session);
    final error = syncNowError;
    if (error != null) return Result.error(error, StackTrace.current);
    return syncResult;
  }
}
