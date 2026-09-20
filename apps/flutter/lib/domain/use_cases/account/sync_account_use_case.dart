import 'package:pomodoist/domain/models/account/history_policy.dart';
export 'package:pomodoist/domain/models/account/history_policy.dart';
import 'package:pomodoist/data/repositories/account/account_session_repository.dart';
import 'package:pomodoist/data/repositories/billing/billing_repository.dart';
import 'package:pomodoist/data/repositories/sync/sync_repository.dart';
import 'package:pomodoist/domain/models/account/account_overview.dart';
import 'package:pomodoist/domain/use_cases/account/pomodoist_retention.dart';
import 'package:pomodoist/utils/result.dart';

class SyncAccountUseCase {
  const SyncAccountUseCase({
    required AccountSessionRepository sessions,
    required SyncRepository sync,
    required BillingRepository access,
    required Future<PomodoistAccountOverview?> Function() loadOverview,
    required bool Function() selfHostedFeaturesUnlocked,
    required Future<PomodoistHistoryPolicy> Function() loadHistoryPolicy,
  }) : _sessions = sessions,
       _sync = sync,
       _access = access,
       _loadOverview = loadOverview,
       _selfHostedFeaturesUnlocked = selfHostedFeaturesUnlocked,
       _loadHistoryPolicy = loadHistoryPolicy;

  final AccountSessionRepository _sessions;
  final SyncRepository _sync;
  final BillingRepository _access;
  final Future<PomodoistAccountOverview?> Function() _loadOverview;
  final bool Function() _selfHostedFeaturesUnlocked;
  final Future<PomodoistHistoryPolicy> Function() _loadHistoryPolicy;

  Future<Result<Set<String>>> call() async {
    final session = _sessions.currentSession;
    if (session.userId == null) {
      return const Success(<String>{});
    }
    final retentionCutoff = await _retentionCutoff();
    if (_sessions.currentSession != session) return const Success(<String>{});
    final result = await _sync.syncNow(
      session: session,
      retentionCutoff: retentionCutoff,
    );
    final current = _sessions.currentSession;
    if (current.generation != session.generation) {
      return const Success(<String>{});
    }
    return result;
  }

  Future<DateTime?> _retentionCutoff() async {
    try {
      final access = _access.currentAccess;
      if (_selfHostedFeaturesUnlocked() || access.hasLocalStoreKitEntitlement) {
        return null;
      }
      final overview = await _loadOverview();
      final policy = await _loadHistoryPolicy();
      return pomodoistTaskHistoryCutoff(
        overview,
        historyUnlimited: policy.historyUnlimited,
        graceEndsAt: policy.graceEndsAt,
      );
    } catch (_) {
      // Server cleanup still enforces free retention; keep local data syncing
      // if entitlement lookup is temporarily unavailable.
      return null;
    }
  }
}
