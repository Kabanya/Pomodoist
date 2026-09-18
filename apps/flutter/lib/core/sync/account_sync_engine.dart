import 'dart:convert';

import 'package:app_account/app_account.dart';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import '../../features/tasks/data/kanban_transition_coordinator.dart';
import 'pomodoist_retention.dart';
import 'account_sync_mapping.dart';
import 'sync_queue_repository.dart';
import '../../features/collaboration/data/collaboration_api.dart';
import '../../features/collaboration/domain/collaboration_models.dart';
part 'shared_account_sync.dart';
part 'account_sync_import.dart';
part 'account_sync_push.dart';
part 'account_sync_operations.dart';
part 'account_sync_pull.dart';
part 'account_sync_upserts.dart';
part 'account_sync_state.dart';

class AccountSyncEngine {
  AccountSyncEngine({
    required AppDatabase db,
    required AccountClient account,
    required Uuid uuid,
    CollaborationApi? collaboration,
    Future<AccountOverview?> Function()? overviewLoader,
    Future<bool> Function()? localPaidEntitlementLoader,
    KanbanTransitionCoordinator? kanbanTransitions,
    Duration requestTimeout = const Duration(seconds: 30),
  }) : _db = db,
       _account = account,
       _uuid = uuid,
       _collaboration = collaboration,
       _overviewLoader = overviewLoader,
       _localPaidEntitlementLoader = localPaidEntitlementLoader,
       _requestTimeout = requestTimeout,
       _kanbanTransitions =
           kanbanTransitions ??
           KanbanTransitionCoordinator(db, DriftSyncQueueRepository(db));

  static const _syncStateId = 'pomodoist';

  static const _importStateId = 'pomodoist-import';

  static const _accountOwnerStateId = 'pomodoist-account-owner-v1';

  static const _importStateCursor = 'done-v3';

  static const _guestOwnerCursor = 'guest';

  static final _seedSnapshotClock = DateTime.utc(2000);

  static final _ownerTransitionQueues = Expando<_OwnerTransitionQueue>(
    'account-owner-transition',
  );

  final CollaborationApi? _collaboration;
  final AppDatabase _db;
  final AccountClient _account;
  final Uuid _uuid;
  final Future<AccountOverview?> Function()? _overviewLoader;
  final Future<bool> Function()? _localPaidEntitlementLoader;
  final Duration _requestTimeout;
  final KanbanTransitionCoordinator _kanbanTransitions;

  Future<Set<String>> syncNow() {
    return _ownerTransitionQueueFor(_db).run(() async {
      await _prepareLocalAccountData();
      final imported = await importLocalSnapshotIfNeeded();
      if (imported) {
        await _broadcastSyncHint();
      }
      return <String>{
        ...await syncShared(),
        ...await pushPending(),
        ...await pullLatest(),
      };
    });
  }

  static Future<bool> prepareGuestLocalData({
    required AppDatabase db,
    required Uuid uuid,
    bool Function()? shouldPrepare,
    Future<void> Function()? onReset,
  }) {
    return _ownerTransitionQueueFor(db).run(() async {
      if (shouldPrepare != null && !shouldPrepare()) {
        return false;
      }
      final owner = await (db.select(
        db.syncState,
      )..where((row) => row.id.equals(_accountOwnerStateId))).getSingleOrNull();
      if (owner?.cursor == _guestOwnerCursor) {
        return false;
      }
      final reset = owner != null;
      if (reset) {
        await onReset?.call();
        await db.resetAccountData();
      }
      final now = DateTime.now().toUtc();
      await db
          .into(db.syncState)
          .insertOnConflictUpdate(
            SyncStateCompanion.insert(
              id: _accountOwnerStateId,
              deviceId: uuid.v4(),
              cursor: const Value(_guestOwnerCursor),
              createdAt: now,
              updatedAt: now,
            ),
          );
      return reset;
    });
  }

  static _OwnerTransitionQueue _ownerTransitionQueueFor(AppDatabase db) {
    final existing = _ownerTransitionQueues[db];
    if (existing != null) {
      return existing;
    }
    final created = _OwnerTransitionQueue();
    _ownerTransitionQueues[db] = created;
    return created;
  }
}

class _OwnerTransitionQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
