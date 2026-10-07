part of 'account_sync_engine.dart';

extension AccountSyncImport on AccountSyncEngine {
  Future<bool> importLocalSnapshotIfNeeded({bool push = true}) async {
    final state =
        await (_db.select(_db.syncState)
              ..where((row) => row.id.equals(AccountSyncEngine._importStateId)))
            .getSingleOrNull();
    if (state?.cursor == AccountSyncEngine._importStateCursor) {
      return false;
    }

    final deviceId = await _ensureDeviceId();
    final imported = await _db.transaction(() async {
      final operations = await _snapshotOperations();
      _checkSession();
      final now = DateTime.now().toUtc();
      var sequence = 0;
      for (final op in operations) {
        await _db
            .into(_db.syncCommands)
            .insert(
              SyncCommandsCompanion.insert(
                id: 'snapshot:${(sequence++).toString().padLeft(12, '0')}:${_uuid.v5(Namespace.url.value, '$deviceId:${op.opId}')}',
                uuid: op.opId,
                type: 'sync.snapshot',
                clientId: Value(op.entityId),
                payloadJson: jsonEncode({
                  '_syncDeviceIdV1': deviceId,
                  '_syncOperationsV1': [op.toJson()],
                }),
                createdAt: DateTime.utc(1970),
                updatedAt: op.clientUpdatedAt,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
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
    });
    if (push) await pushPending();
    return imported;
  }

  Future<void> _resetImportState() async {
    await (_db.delete(
      _db.syncState,
    )..where((row) => row.id.equals(AccountSyncEngine._importStateId))).go();
  }
}
