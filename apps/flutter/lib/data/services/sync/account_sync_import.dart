part of 'account_sync_engine.dart';

extension AccountSyncImport on AccountSyncEngine {
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
    _checkSession();

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
