part of 'account_sync_engine.dart';

extension AccountSyncPush on AccountSyncEngine {
  Future<Set<String>> pushPending() async {
    if (_isSessionCurrent?.call() == false) {
      return const <String>{};
    }
    await _deleteFinishedCommands();
    final deviceId = await _ensureDeviceId();
    final taskHistoryCutoff = _retentionCutoff;
    final readyAt = DateTime.now().toUtc();
    final deferredTaskIds =
        (await (_db.select(_db.syncCommands)..where(
                  (row) =>
                      row.scopeId.isNull() &
                      row.status.equals('pending') &
                      row.type.equals('task.delete') &
                      row.availableAt.isBiggerThanValue(readyAt),
                ))
                .get())
            .map((command) => command.clientId)
            .whereType<String>()
            .toSet();
    final pending =
        await (_db.select(_db.syncCommands)
              ..where(
                (row) =>
                    row.scopeId.isNull() &
                    row.status.equals('pending') &
                    (row.availableAt.isNull() |
                        row.availableAt.isSmallerOrEqualValue(readyAt)) &
                    (deferredTaskIds.isEmpty
                        ? const Constant(true)
                        : row.clientId.isNotIn(deferredTaskIds)),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.createdAt)])
              ..limit(100))
            .get();
    if (pending.isEmpty) {
      return const <String>{};
    }

    var retained = pending;
    try {
      retained = await _compactPendingTaskCommands(pending);
    } catch (_) {
      // Compaction is optional; the original commands remain authoritative.
      retained = pending;
    }

    final operations = <AccountSyncOperation>[];
    for (final command in retained) {
      operations.addAll(
        await _operationsFromCommand(command, taskHistoryCutoff),
      );
    }
    if (operations.isNotEmpty) {
      await _markAttemptStarted(retained);
    }
    await _pushInBatches(deviceId, operations);
    _checkSession();

    final now = DateTime.now().toUtc();
    await _db.batch((batch) {
      for (final command in retained) {
        batch.update(
          _db.syncCommands,
          SyncCommandsCompanion(
            status: const Value('synced'),
            updatedAt: Value(now),
          ),
          where: (row) => row.id.equals(command.id),
        );
      }
    });
    final entityTypes = operations
        .map((operation) => operation.entityType)
        .toSet();
    await _deleteFinishedCommands();
    if (operations.isNotEmpty) {
      await _broadcastSyncHint();
    }
    return entityTypes;
  }

  Future<void> _deleteFinishedCommands() async {
    await (_db.delete(_db.syncCommands)..where(
          (row) => row.status.equals('synced') | row.status.equals('compacted'),
        ))
        .go();
  }

  Future<List<SyncCommandRow>> _compactPendingTaskCommands(
    List<SyncCommandRow> pending,
  ) async {
    const safeTypes = {
      'task.create',
      'task.reorder',
      'task.delete',
      'task.kanbanStatus.set',
    };
    final retained = <SyncCommandRow>[];
    final discardedIds = <String>{};
    final updatedAtOverrides = <String, DateTime>{};

    bool isSafe(SyncCommandRow command) =>
        command.status == 'pending' &&
        command.attempts == 0 &&
        command.clientId != null &&
        safeTypes.contains(command.type);

    var index = 0;
    while (index < pending.length) {
      final first = pending[index];
      if (!isSafe(first)) {
        retained.add(first);
        index += 1;
        continue;
      }

      final run = <SyncCommandRow>[first];
      index += 1;
      while (index < pending.length &&
          isSafe(pending[index]) &&
          pending[index].clientId == first.clientId) {
        run.add(pending[index]);
        index += 1;
      }

      SyncCommandRow? lastOf(String type) {
        SyncCommandRow? result;
        for (final command in run) {
          if (command.type == type) {
            result = command;
          }
        }
        return result;
      }

      final create = run
          .where((command) => command.type == 'task.create')
          .firstOrNull;
      final delete = lastOf('task.delete');
      final keptIds = <String>{};
      if (create != null && delete != null) {
        // A never-attempted task has no cloud state to delete.
      } else if (delete != null) {
        keptIds.add(delete.id);
      } else {
        if (create != null) {
          keptIds.add(create.id);
          var latestTaskMutation = create.updatedAt;
          for (final command in run) {
            if (command.type != 'task.kanbanStatus.set' &&
                command.updatedAt.isAfter(latestTaskMutation)) {
              latestTaskMutation = command.updatedAt;
            }
          }
          if (latestTaskMutation != create.updatedAt) {
            updatedAtOverrides[create.id] = latestTaskMutation;
          }
        } else {
          final update = lastOf('task.update');
          final reorder = lastOf('task.reorder');
          if (update != null) keptIds.add(update.id);
          if (reorder != null) keptIds.add(reorder.id);
        }
        keptIds.addAll(
          run
              .where((command) => command.type == 'task.kanbanStatus.set')
              .map((command) => command.id),
        );
      }

      for (final command in run) {
        if (keptIds.contains(command.id)) {
          final updatedAt = updatedAtOverrides[command.id];
          retained.add(
            updatedAt == null
                ? command
                : command.copyWith(updatedAt: updatedAt),
          );
        } else {
          discardedIds.add(command.id);
        }
      }
    }

    if (discardedIds.isEmpty && updatedAtOverrides.isEmpty) {
      return retained;
    }
    await _db.transaction(() async {
      if (discardedIds.isNotEmpty) {
        await (_db.update(_db.syncCommands)
              ..where((row) => row.id.isIn(discardedIds)))
            .write(const SyncCommandsCompanion(status: Value('compacted')));
      }
      for (final entry in updatedAtOverrides.entries) {
        await (_db.update(_db.syncCommands)
              ..where((row) => row.id.equals(entry.key)))
            .write(SyncCommandsCompanion(updatedAt: Value(entry.value)));
      }
    });
    return retained;
  }

  Future<void> _markAttemptStarted(List<SyncCommandRow> commands) {
    return _db.batch((batch) {
      for (final command in commands) {
        batch.update(
          _db.syncCommands,
          SyncCommandsCompanion(attempts: Value(command.attempts + 1)),
          where: (row) => row.id.equals(command.id),
        );
      }
    });
  }

  Future<void> _pushInBatches(
    String deviceId,
    List<AccountSyncOperation> operations,
  ) async {
    const batchSize = 100;
    for (var index = 0; index < operations.length; index += batchSize) {
      final end = index + batchSize > operations.length
          ? operations.length
          : index + batchSize;
      await _pushBatch(deviceId, operations.sublist(index, end));
    }
  }

  Future<void> _pushBatch(
    String deviceId,
    List<AccountSyncOperation> operations,
  ) async {
    try {
      _checkSession();
      await _account
          .pushChanges(
            appId: AccountAppId.pomodoist,
            deviceId: deviceId,
            operations: operations,
          )
          .timeout(_requestTimeout);
      _checkSession();
    } on PostgrestException catch (error) {
      if (!{'PT413', '413'}.contains(error.code) || operations.length <= 1) {
        rethrow;
      }
      final middle = operations.length ~/ 2;
      // Keep IDs and order: an acknowledged half can safely be replayed if the
      // next half fails before the local command is marked as synchronized.
      await _pushBatch(deviceId, operations.sublist(0, middle));
      await _pushBatch(deviceId, operations.sublist(middle));
    }
  }
}
