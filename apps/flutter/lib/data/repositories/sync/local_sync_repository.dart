import 'package:pomodoist/data/repositories/sync/sync_repository.dart';
import 'package:pomodoist/data/services/sync/account_sync_engine.dart';
import 'package:pomodoist/domain/models/account/account_session.dart';
import 'package:pomodoist/utils/result.dart';

final class LocalSyncRepository implements SyncRepository {
  LocalSyncRepository({
    required AccountSyncEngine Function() engine,
    required AccountSession Function() currentSession,
  }) : _engine = engine,
       _currentSession = currentSession;

  final AccountSyncEngine Function() _engine;
  final AccountSession Function() _currentSession;

  bool _isCurrent(AccountSession session) => _currentSession() == session;

  @override
  Future<Result<Set<String>>> syncNow({
    required AccountSession session,
    required DateTime? retentionCutoff,
  }) => Result.capture<Set<String>>(() async {
    if (!_isCurrent(session) || session.userId == null) {
      return const <String>{};
    }
    final entityTypes = await _engine().syncNow(
      retentionCutoff: retentionCutoff,
      isSessionCurrent: () => _isCurrent(session),
    );
    return _isCurrent(session) ? entityTypes : const <String>{};
  });
}
