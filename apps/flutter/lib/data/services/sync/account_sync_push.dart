part of 'account_sync_engine.dart';

extension AccountSyncPush on AccountSyncEngine {
  Future<Set<String>> pushPending() async {
    if (_isSessionCurrent?.call() == false) {
      return const <String>{};
    }
    await _deleteFinishedCommands();
    await _capturePendingOperations();
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
              ..orderBy([
                (row) => OrderingTerm.asc(row.createdAt),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    _pushRequestsLeft = 64;
    final blocked =
        (await (_db.select(_db.syncCommands)..where(
                  (r) =>
                      r.scopeId.isNull() &
                      (r.status.equals('rejected') |
                          r.status.equals('conflict')),
                ))
                .get())
            .map((r) => r.clientId)
            .whereType<String>()
            .toSet();
    final types = <String>{};
    final group = <SyncCommandRow>[];
    var size = 0;
    // ponytail: linear queue scan; use persisted keyset pages if local queues
    // grow beyond memory. Network work is limited to 64 requests per cycle.
    for (final command in pending) {
      final operations = await _operationsFromCommand(
        command,
        taskHistoryCutoff,
      );
      final references = <String>{
        if (command.clientId != null) command.clientId!,
        for (final op in operations) ...[
          op.entityId,
          for (final key in [
            'projectId',
            'taskId',
            'parentId',
            'sectionId',
            'habitId',
            'runId',
          ])
            if (op.payload[key] is String) op.payload[key] as String,
        ],
      };
      if (references.any(blocked.contains)) {
        if (command.clientId != null) blocked.add(command.clientId!);
        continue;
      }
      if (group.isNotEmpty && size + operations.length > 100) {
        types.addAll(await _pushCommandGroup(deviceId, group, blocked));
        group.clear();
        size = 0;
      }
      group.add(command);
      size += operations.length;
    }
    if (group.isNotEmpty) {
      types.addAll(await _pushCommandGroup(deviceId, group, blocked));
    }
    await _deleteFinishedCommands();
    if (types.isNotEmpty) await _broadcastSyncHint();
    return types;
  }

  Future<Set<String>> _pushCommandGroup(
    String deviceId,
    List<SyncCommandRow> commands,
    Set<String> blocked,
  ) async {
    final retained = <SyncCommandRow>[];
    final operations = <AccountSyncOperation>[];
    for (final command in commands) {
      final ops = await _operationsFromCommand(command, _retentionCutoff);
      if (ops.any(
            (op) =>
                blocked.contains(op.entityId) ||
                [
                  'projectId',
                  'taskId',
                  'parentId',
                  'sectionId',
                  'habitId',
                  'runId',
                ].any((key) => blocked.contains(op.payload[key])),
          ) ||
          blocked.contains(command.clientId)) {
        continue;
      }
      retained.add(command);
      operations.addAll(ops);
    }
    if (retained.isEmpty) return {};
    await _markAttemptStarted(retained);
    try {
      await _pushInBatches(deviceId, operations);
    } on PostgrestException catch (error) {
      if (!_permanentPayloadError(error)) rethrow;
      if (retained.length > 1) {
        final mid = retained.length ~/ 2;
        return {
          ...await _pushCommandGroup(
            deviceId,
            retained.sublist(0, mid),
            blocked,
          ),
          ...await _pushCommandGroup(deviceId, retained.sublist(mid), blocked),
        };
      }
      _checkSession();
      final command = retained.single;
      await (_db.update(
        _db.syncCommands,
      )..where((r) => r.id.equals(command.id))).write(
        SyncCommandsCompanion(
          status: const Value('rejected'),
          lastError: Value('validation:${error.message}'),
        ),
      );
      if (command.clientId != null) blocked.add(command.clientId!);
      return {};
    }
    _checkSession();
    await (_db.update(
      _db.syncCommands,
    )..where((r) => r.id.isIn(retained.map((r) => r.id)))).write(
      SyncCommandsCompanion(
        status: const Value('synced'),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
    final types = operations.map((op) => op.entityType).toSet();
    _committedTypes.addAll(types);
    return types;
  }

  bool _permanentPayloadError(PostgrestException error) =>
      error.code == '22023' &&
      const {
        'Invalid habit identity',
        'Invalid habit field',
        'Invalid habit timestamp',
        'Invalid habit icon',
        'Invalid habit title',
        'Invalid habit reminder',
        'Invalid habit schedule',
        'Invalid habit day period',
        'Invalid habit period targets',
        'Invalid habit weekdays',
        'Invalid check-in day period',
        'Invalid check-in habit',
        'Incomplete task entity',
        'Incomplete project entity',
      }.contains(error.message);

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
      if (_pushRequestsLeft-- <= 0) {
        throw StateError('Sync request budget reached');
      }
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
