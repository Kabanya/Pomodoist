import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'dart:convert';

import 'package:app_account/app_account.dart';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:uuid/uuid.dart';

import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/sync_owner_store.dart';
import 'package:pomodoist/data/services/sync/account_sync_mapping.dart';
import 'package:pomodoist/data/services/collaboration/collaboration_api.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';
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
    required Future<bool> Function({Future<void> Function()? onReset})
    prepareAccount,
    required Future<void> Function({required DateTime timestamp}) repairKanban,
    Duration requestTimeout = const Duration(seconds: 30),
  }) : _db = db,
       _account = account,
       _uuid = uuid,
       _collaboration = collaboration,
       _requestTimeout = requestTimeout,
       _prepareAccount = prepareAccount,
       _repairKanban = repairKanban;

  static const _syncStateId = 'pomodoist';

  static const _importStateId = 'pomodoist-import';

  static const _importStateCursor = 'done-v3';

  static final _seedSnapshotClock = DateTime.utc(2000);

  final CollaborationApi? _collaboration;
  final AppDatabase _db;
  final AccountClient _account;
  final Uuid _uuid;
  final Duration _requestTimeout;
  final Future<bool> Function({Future<void> Function()? onReset})
  _prepareAccount;
  final Future<void> Function({required DateTime timestamp}) _repairKanban;
  DateTime? _retentionCutoff;
  bool Function()? _isSessionCurrent;
  String? _syncUserId;
  void _checkSession() {
    if (_isSessionCurrent?.call() == false ||
        (_syncUserId != null && _account.currentUserId != _syncUserId)) {
      throw const _StaleSyncSession();
    }
  }

  Future<Map<String, dynamic>> _callCollaboration(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    _checkSession();
    final result = await _collaboration!.call(action, payload);
    _checkSession();
    return result;
  }

  Future<Set<String>> syncNow({
    DateTime? retentionCutoff,
    bool Function()? isSessionCurrent,
  }) {
    final userId = _account.currentUserId;
    return SyncOwnerStore.serialized(_db, () async {
      _syncUserId = userId;
      _retentionCutoff = retentionCutoff;
      _isSessionCurrent = isSessionCurrent;
      try {
        _checkSession();
        await _prepareAccount();
        _checkSession();
        final imported = await importLocalSnapshotIfNeeded();
        if (imported) {
          await _broadcastSyncHint();
        }
        return <String>{
          ...await syncShared(),
          ...await pushPending(),
          ...await pullLatest(),
        };
      } on _StaleSyncSession {
        return <String>{};
      } finally {
        _syncUserId = null;
        _retentionCutoff = null;
        _isSessionCurrent = null;
      }
    });
  }

  Future<bool> prepareLocalAccountData({Future<void> Function()? onReset}) =>
      SyncOwnerStore.serialized(_db, () => _prepareAccount(onReset: onReset));
}

class _StaleSyncSession implements Exception {
  const _StaleSyncSession();
}
