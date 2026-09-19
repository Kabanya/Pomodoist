part of 'account_sync_engine.dart';

extension AccountSyncImport on AccountSyncEngine {
  Future<bool> prepareLocalAccountData({Future<void> Function()? onReset}) {
    return AccountSyncEngine._ownerTransitionQueueFor(
      _db,
    ).run(() => _prepareLocalAccountData(onReset: onReset));
  }

  Future<bool> _prepareLocalAccountData({
    Future<void> Function()? onReset,
  }) async {
    final userId = _account.currentUserId;
    if (userId == null || userId.isEmpty) {
      throw StateError('Account sync requires an authenticated user.');
    }
    final owner =
        await (_db.select(_db.syncState)..where(
              (row) => row.id.equals(AccountSyncEngine._accountOwnerStateId),
            ))
            .getSingleOrNull();
    if (owner?.cursor == userId) {
      await _db.backfillTaskCreators(accountUserId: userId);
      return false;
    }
    final importState =
        await (_db.select(_db.syncState)
              ..where((row) => row.id.equals(AccountSyncEngine._importStateId)))
            .getSingleOrNull();
    final syncState = await _syncState();
    final reset = owner != null || importState != null || syncState != null;
    if (reset) {
      await onReset?.call();
      await _db.resetAccountData();
    }
    final now = DateTime.now().toUtc();
    await _db
        .into(_db.syncState)
        .insertOnConflictUpdate(
          SyncStateCompanion.insert(
            id: AccountSyncEngine._accountOwnerStateId,
            deviceId: _uuid.v4(),
            cursor: Value(userId),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _db.backfillTaskCreators(accountUserId: userId);
    return reset;
  }

  Future<bool> importLocalSnapshotIfNeeded() async {
    final state =
        await (_db.select(_db.syncState)
              ..where((row) => row.id.equals(AccountSyncEngine._importStateId)))
            .getSingleOrNull();
    if (state?.cursor == AccountSyncEngine._importStateCursor) {
      return false;
    }

    final deviceId = await _ensureDeviceId();
    final operations = await _snapshotOperations();
    await _pushInBatches(deviceId, operations);

    final now = DateTime.now().toUtc();
    await _db
        .into(_db.syncState)
        .insertOnConflictUpdate(
          SyncStateCompanion.insert(
            id: AccountSyncEngine._importStateId,
            deviceId: deviceId,
            cursor: const Value(AccountSyncEngine._importStateCursor),
            lastPushedAt: Value(now),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return operations.isNotEmpty;
  }

  Future<void> _resetImportState() async {
    await (_db.delete(
      _db.syncState,
    )..where((row) => row.id.equals(AccountSyncEngine._importStateId))).go();
  }
}
