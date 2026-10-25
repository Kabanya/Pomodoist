part of 'account_sync_engine.dart';

extension AccountSyncLegacyRecovery on AccountSyncEngine {
  Future<void> _checkRecoveryOwner(String userId) async {
    final owner = await SyncOwnerStore(_db, _uuid).owner();
    if (_account.currentUserId != userId || owner?.cursor != userId) {
      throw StateError('Account changed during legacy recovery');
    }
  }

  Future<LegacyRecoveryRequest?>
  legacyRecoveryRequest() => SyncOwnerStore.serialized(_db, () async {
    final userId = _account.currentUserId;
    if (userId == null) throw StateError('Synchronization is unavailable');
    await _checkRecoveryOwner(userId);
    final source = await AccountRecoveryStore(_db).legacyData();
    if (source == null) return null;
    final operations = await _snapshotOperations(source: source);
    // Decode the outbox before asking for ownership of an unreadable archive.
    await source.rows(_db.syncCommands);
    await _checkRecoveryOwner(userId);
    return LegacyRecoveryRequest(
      userId: userId,
      fingerprint: source.fingerprint,
      recordCount: operations.length,
    );
  });

  Future<void> recoverLegacyArchive(
    LegacyRecoveryRequest confirmation,
  ) => SyncOwnerStore.serialized(
    _db,
    () => _db.transaction(() async {
      await _checkRecoveryOwner(confirmation.userId);
      final recoveredId =
          'legacy-recovered:${confirmation.userId}:${confirmation.fingerprint}';
      if (await (_db.select(
            _db.accountRecoverySnapshots,
          )..where((r) => r.ownerId.equals(recoveredId))).getSingleOrNull() !=
          null) {
        return;
      }
      final source = await AccountRecoveryStore(_db).legacyData();
      if (source == null || source.fingerprint != confirmation.fingerprint) {
        throw StateError('Legacy recovery archive changed');
      }
      await _capturePendingOperations();
      final deviceId = await _ensureDeviceId();
      final snapshot = await _snapshotOperations(source: source);
      final sharedProjects = (await source.rows(
        _db.projects,
      )).where((r) => r.scopeId != null).map((r) => r.id).toSet();
      final sharedTasks = (await source.rows(_db.tasks))
          .where(
            (r) => r.scopeId != null || sharedProjects.contains(r.projectId),
          )
          .map((r) => r.id)
          .toSet();
      final sharedIds = (await source.rows(_db.sharedEntities))
          .where((r) => r.scopeId != '_account')
          .map((r) => '${r.entityType}:${r.entityId}')
          .toSet();
      final terminalRuns = snapshot
          .where((op) => op.entityType == 'focus_run')
          .map((op) => op.entityId)
          .toSet();
      bool personal(AccountSyncOperation op) =>
          AccountSyncRecovery._entityTypes.contains(op.entityType) &&
          !op.entityType.startsWith('google_calendar_') &&
          op.payload['scopeId'] == null &&
          !sharedProjects.contains(op.entityId) &&
          !sharedTasks.contains(op.entityId) &&
          !sharedProjects.contains(op.payload['projectId']) &&
          !sharedTasks.contains(op.payload['taskId']) &&
          !sharedIds.contains('${op.entityType}:${op.entityId}') &&
          (op.entityType != 'focus_run' ||
              terminalRuns.contains(op.entityId)) &&
          (!const {'focus_interval', 'focus_event'}.contains(op.entityType) ||
              terminalRuns.contains(op.payload['runId']));
      var sequence = 0;
      Future<void> enqueue(
        List<AccountSyncOperation> operations,
        String identity, {
        String status = 'pending',
        String? error,
      }) async {
        final id =
            'legacy:${(sequence++).toString().padLeft(12, '0')}:${_uuid.v5(Namespace.url.value, '${confirmation.userId}:${source.fingerprint}:$identity')}';
        await _db
            .into(_db.syncCommands)
            .insert(
              SyncCommandsCompanion.insert(
                id: id,
                uuid: id,
                type: 'sync.snapshot',
                clientId: Value(operations.firstOrNull?.entityId),
                payloadJson: jsonEncode({
                  '_syncDeviceIdV1': deviceId,
                  '_syncOperationsV1': operations
                      .map((op) => op.toJson())
                      .toList(),
                  'legacySource': source.fingerprint,
                  'legacyCommand': identity,
                }),
                status: Value(status),
                lastError: Value(error),
                createdAt: DateTime.utc(1970),
                updatedAt:
                    operations.firstOrNull?.clientUpdatedAt ??
                    source.snapshot.createdAt,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }

      for (final op in snapshot.where(personal)) {
        await enqueue([
          _operation(
            opId:
                'legacy:${_uuid.v5(Namespace.url.value, '${source.fingerprint}:${op.opId}')}',
            entityType: op.entityType,
            entityId: op.entityId,
            operation: op.operation,
            payload: Map<String, dynamic>.from(op.payload),
            clientUpdatedAt: op.clientUpdatedAt,
          ),
        ], op.opId);
      }
      final commands = (await source.rows(_db.syncCommands))
        ..sort((a, b) {
          final order = a.createdAt.compareTo(b.createdAt);
          return order == 0 ? a.id.compareTo(b.id) : order;
        });
      for (final command in commands) {
        if (command.scopeId != null ||
            const {
              'synced',
              'compacted',
              'superseded',
              'revoked',
            }.contains(command.status)) {
          continue;
        }
        try {
          final payload = Map<String, Object?>.from(
            jsonDecode(command.payloadJson) as Map,
          );
          if (!payload.containsKey('_syncOperationsV1') &&
              !_knownCommand(command.type)) {
            throw const FormatException('Unknown legacy command');
          }
          final operations = await _operationsFromCommand(
            command,
            null,
            sourceOperations: snapshot,
          );
          // Scoped cache/authorization and running focus are never imported.
          final retained = operations.where(personal).toList();
          if (retained.isEmpty && operations.isNotEmpty) continue;
          if (retained.isEmpty) continue;
          await enqueue(
            retained,
            command.uuid,
            status: command.status == 'pending' ? 'pending' : 'rejected',
            error: command.status == 'pending'
                ? null
                : 'legacy:${command.lastError ?? command.status}',
          );
        } on FormatException {
          await enqueue(
            [],
            command.uuid,
            status: 'rejected',
            error: 'invalid_legacy_command',
          );
        } on TypeError {
          await enqueue(
            [],
            command.uuid,
            status: 'rejected',
            error: 'invalid_legacy_command',
          );
        }
      }
      // Paused local sessions remain local, as in the normal snapshot importer.
      final pausedRuns = <String>{};
      for (final run in await source.rows(_db.focusRuns)) {
        if (_isTerminalFocusRun(run)) continue;
        if (await (_db.select(
              _db.focusRuns,
            )..where((r) => r.id.equals(run.id))).getSingleOrNull() !=
            null) {
          continue;
        }
        await _db
            .into(_db.focusRuns)
            .insert(
              run.copyWith(status: 'paused'),
              mode: InsertMode.insertOrIgnore,
            );
        pausedRuns.add(run.id);
      }
      for (final interval in await source.rows(_db.focusIntervals)) {
        if (!pausedRuns.contains(interval.runId)) continue;
        final running =
            interval.status == 'running' &&
            interval.completedAt == null &&
            interval.stoppedAt == null;
        await _db
            .into(_db.focusIntervals)
            .insert(
              running
                  ? interval.copyWith(
                      status: 'paused',
                      pausedAt: Value(source.snapshot.createdAt),
                    )
                  : interval,
              mode: InsertMode.insertOrIgnore,
            );
      }
      for (final event in await source.rows(_db.focusEvents)) {
        if (pausedRuns.contains(event.runId)) {
          await _db
              .into(_db.focusEvents)
              .insert(event, mode: InsertMode.insertOrIgnore);
        }
      }
      await _checkRecoveryOwner(confirmation.userId);
      await (_db.update(
        _db.accountRecoverySnapshots,
      )..where((r) => r.ownerId.equals('legacy-unowned'))).write(
        AccountRecoverySnapshotsCompanion(
          // Keep the source bytes intact; the key records its confirmed owner.
          ownerId: Value(recoveredId),
        ),
      );
    }),
  );
}
