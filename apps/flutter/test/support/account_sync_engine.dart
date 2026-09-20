import 'package:app_account/app_account.dart';
import 'package:uuid/uuid.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/data/services/sync/account_sync_engine.dart';
import 'package:pomodoist/data/services/collaboration/collaboration_api.dart';
import 'package:pomodoist/data/repositories/local/kanban_transition_coordinator.dart';
import 'package:pomodoist/data/repositories/local/sync_ownership_coordinator.dart';
export 'package:pomodoist/data/repositories/local/sync_ownership_coordinator.dart';
export 'package:pomodoist/data/services/sync/account_sync_engine.dart';

AccountSyncEngine testSyncEngine({
  required AppDatabase db,
  required AccountClient account,
  required Uuid uuid,
  CollaborationApi? collaboration,
  Duration requestTimeout = const Duration(seconds: 30),
}) => AccountSyncEngine(
  db: db,
  account: account,
  uuid: uuid,
  collaboration: collaboration,
  requestTimeout: requestTimeout,
  prepareAccount: SyncOwnershipCoordinator(
    db,
    uuid,
    () => account.currentUserId,
  ).prepareAccount,
  repairKanban: KanbanTransitionCoordinator(
    db,
    DriftOutboxService(db),
    uuid: uuid,
  ).repairAfterRemotePullInTransaction,
);
