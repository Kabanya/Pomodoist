part of 'account_sync_engine.dart';

extension AccountSyncRecovery on AccountSyncEngine {
  static const _entityTypes = {
    'workspace',
    'project',
    'section',
    'task',
    'task_completion',
    'label',
    'task_label',
    'task_kanban_status',
    'kanban_settings',
    'filter',
    'reminder',
    'focus_preset',
    'focus_run',
    'focus_interval',
    'focus_event',
    'habit',
    'habit_check_in',
    'google_calendar_connection',
    'google_calendar_event_link',
  };
  static const _repairStateId = 'pomodoist-repair-v1';
  bool _knownCommand(String type) {
    if (_entityTypes.any(
      (entity) => const [
        'create',
        'update',
        'upsert',
        'delete',
        'reorder',
      ].any((action) => type == '$entity.$action'),
    )) {
      return true;
    }
    return const {
      'task.complete',
      'task.uncomplete',
      'task.move',
      'task.assign',
      'task.label.add',
      'task.label.delete',
      'task.kanbanStatus.set',
      'kanban.settings.focus.set',
      'kanban.settings.projects.set',
      'kanban.status.create',
      'kanban.status.delete',
      'kanban.status.rename',
      'kanban.status.reorder',
      'google_calendar.connection.upsert',
      'google_calendar.connection.delete',
      'google_calendar.link.upsert',
      'google_calendar.link.delete',
      'focus.preset.create',
      'focus.preset.update',
      'focus.preset.delete',
      'focus.run.start',
      'focus.run.pause',
      'focus.run.resume',
      'focus.run.complete',
      'focus.run.stop',
      'focus.interval.start',
      'focus.interval.pause',
      'focus.interval.resume',
      'focus.interval.complete',
      'focus.interval.stop',
      'focus.distraction.log',
      'focus_contribution.create',
    }.contains(type);
  }

  static const _required = {
    'task': [
      'id',
      'userId',
      'content',
      'projectId',
      'priority',
      'status',
      'completedFocusIntervals',
      'totalFocusSeconds',
      'orderKey',
      'isCollapsed',
      'isDeleted',
      'createdAt',
      'updatedAt',
    ],
    'project': [
      'id',
      'userId',
      'name',
      'viewStyle',
      'isFavorite',
      'isArchived',
      'isDeleted',
      'orderKey',
      'createdAt',
      'updatedAt',
    ],
  };

  Future<void> _capturePendingOperations() async {
    final deviceId = await _ensureDeviceId();
    await _db.transaction(() async {
      await _supersedeEditedRejections(deviceId);
      final query = _db.select(_db.syncCommands)
        ..where((r) => r.scopeId.isNull() & r.status.equals('pending'))
        ..orderBy([
          (r) => OrderingTerm.asc(r.createdAt),
          (r) => OrderingTerm.asc(r.id),
        ]);
      final now = DateTime.now().toUtc();
      await _compactPendingTaskCommands(
        (await query.get())
            .where(
              (r) =>
                  !r.payloadJson.contains('"_syncOperationsV1"') &&
                  (r.availableAt == null || !r.availableAt!.isAfter(now)),
            )
            .toList(),
      );
      for (final command in await query.get()) {
        _checkSession();
        try {
          final payload = Map<String, Object?>.from(
            jsonDecode(command.payloadJson) as Map,
          );
          if (payload.containsKey('_syncOperationsV1')) {
            _storedOperations(payload);
            if (payload['_syncDeviceIdV1'] != deviceId) {
              throw const FormatException('Device mismatch');
            }
            continue;
          }
          if (!_knownCommand(command.type)) {
            throw const FormatException('Unknown command');
          }
          final operations = await _operationsFromCommand(
            command,
            _retentionCutoff,
          );
          await (_db.update(
            _db.syncCommands,
          )..where((r) => r.id.equals(command.id))).write(
            SyncCommandsCompanion(
              payloadJson: Value(
                jsonEncode({
                  ...payload,
                  '_syncDeviceIdV1': deviceId,
                  '_syncOperationsV1': operations
                      .map((op) => op.toJson())
                      .toList(),
                }),
              ),
            ),
          );
        } on FormatException {
          await _rejectLocalCommand(command);
        } on TypeError {
          await _rejectLocalCommand(command);
        }
      }
    });
  }

  // Only a later, never-attempted user edit can replace a rejected single-row
  // upsert. Deletes and multi-operation history retain their original identity.
  Future<void> _supersedeEditedRejections(String deviceId) async {
    final rejected = await (_db.select(
      _db.syncCommands,
    )..where((r) => r.scopeId.isNull() & r.status.equals('rejected'))).get();
    for (final old in rejected) {
      if (old.clientId == null ||
          !(old.lastError?.startsWith('validation:') ?? false)) {
        continue;
      }
      final original = _storedOperations(
        Map<String, Object?>.from(jsonDecode(old.payloadJson) as Map),
      );
      if (original.length != 1 ||
          original.single.operation != 'upsert' ||
          !{'task', 'project', 'habit'}.contains(original.single.entityType)) {
        continue;
      }
      final edits =
          (await (_db.select(_db.syncCommands)
                    ..where(
                      (r) =>
                          r.scopeId.isNull() &
                          r.clientId.equals(old.clientId!) &
                          r.status.equals('pending'),
                    )
                    ..orderBy([
                      (r) => OrderingTerm.asc(r.createdAt),
                      (r) => OrderingTerm.asc(r.id),
                    ]))
                  .get())
              .where(
                (r) =>
                    syncEntityTypeForCommand(r.type) ==
                    original.single.entityType,
              )
              .toList();
      if (edits.isEmpty ||
          edits.any(
            (r) =>
                r.attempts != 0 ||
                !{
                  'task.update',
                  'project.update',
                  'habit.update',
                }.contains(r.type),
          )) {
        continue;
      }
      try {
        final type = original.single.entityType;
        final latest = edits.last;
        final latestPayload = Map<String, Object?>.from(
          jsonDecode(latest.payloadJson) as Map,
        );
        final source = await _rowPayload(type, old.clientId!, latestPayload);
        final payload = syncDataWithoutSyncMetadata(source)
          ..remove('_syncOperationsV1')
          ..remove('_syncDeviceIdV1')
          ..remove('commandType');
        if (payload['isDeleted'] == true) continue;
        if (type == 'habit') {
          Habit.fromJson(payload);
        } else if (!syncHasRequired(payload, _required[type]!)) {
          continue;
        } else if (type == 'task') {
          TaskRow.fromJson(payload);
        } else {
          ProjectRow.fromJson(payload);
        }
        final previous = syncDataWithoutSyncMetadata(original.single.payload)
          ..remove('commandType');
        if (jsonEncode(previous) == jsonEncode(payload)) continue;
        final id =
            'replacement:${_uuid.v5(Namespace.url.value, '${old.uuid}:${latest.uuid}')}';
        final operation = _operation(
          opId: id,
          entityType: type,
          entityId: old.clientId!,
          operation: 'upsert',
          payload: payload,
          clientUpdatedAt: latest.updatedAt,
        );
        await _db
            .into(_db.syncCommands)
            .insert(
              SyncCommandsCompanion.insert(
                id: id,
                uuid: id,
                type: 'sync.snapshot',
                clientId: Value(old.clientId),
                payloadJson: jsonEncode({
                  '_syncDeviceIdV1': deviceId,
                  '_syncOperationsV1': [operation.toJson()],
                }),
                createdAt: old.createdAt,
                updatedAt: latest.updatedAt,
              ),
            );
        await (_db.update(
          _db.syncCommands,
        )..where((r) => r.id.isIn([old.id, ...edits.map((r) => r.id)]))).write(
          SyncCommandsCompanion(
            status: const Value('superseded'),
            lastError: Value('replaced:$id'),
          ),
        );
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      } on ArgumentError {
        continue;
      }
    }
  }

  Future<void> _rejectLocalCommand(SyncCommandRow command) =>
      (_db.update(
        _db.syncCommands,
      )..where((r) => r.id.equals(command.id))).write(
        const SyncCommandsCompanion(
          status: Value('rejected'),
          lastError: Value('invalid_local_command'),
        ),
      );

  List<AccountSyncOperation> _storedOperations(Map<String, Object?> payload) {
    final raw = payload['_syncOperationsV1'];
    if (raw is! List) throw const FormatException('Invalid stored operations');
    return raw.map((value) {
      if (value is! Map) {
        throw const FormatException('Invalid stored operation');
      }
      final op = Map<String, Object?>.from(value);
      if (op['opId'] is! String ||
          (op['opId'] as String).isEmpty ||
          op['entityId'] is! String ||
          (op['entityId'] as String).isEmpty ||
          !_entityTypes.contains(op['entityType']) ||
          op['payload'] is! Map ||
          !{'upsert', 'delete'}.contains(op['operation']) ||
          op['clientUpdatedAt'] is! String ||
          DateTime.tryParse(op['clientUpdatedAt'] as String) == null) {
        throw const FormatException('Invalid stored operation');
      }
      return AccountSyncOperation.fromJson(op);
    }).toList();
  }

  Map<String, Object?> _entityJson(AccountSyncEntity entity) => {
    'entityType': entity.entityType,
    'entityId': entity.entityId,
    'serverRevision': entity.serverRevision,
    'data': entity.data,
    'updatedAt': entity.updatedAt?.toIso8601String(),
    'deletedAt': entity.deletedAt?.toIso8601String(),
  };

  Future<SharedEntityRow?> _recoveryMarker(
    String kind,
    AccountSyncEntity entity,
  ) =>
      (_db.select(_db.sharedEntities)..where(
            (r) =>
                r.scopeId.equals('_account') &
                r.entityType.equals('$kind:${entity.entityType}') &
                r.entityId.equals(entity.entityId),
          ))
          .getSingleOrNull();

  Future<void> _writeRecoveryMarker(
    String kind,
    AccountSyncEntity entity, {
    bool resolved = false,
    List<String> missingFields = const [],
  }) async {
    final old = await _recoveryMarker(kind, entity);
    if (old != null && old.serverRevision > entity.serverRevision) return;
    await _db
        .into(_db.sharedEntities)
        .insertOnConflictUpdate(
          SharedEntitiesCompanion.insert(
            scopeId: '_account',
            entityType: '$kind:${entity.entityType}',
            entityId: entity.entityId,
            dataJson: jsonEncode({
              ..._entityJson(entity),
              'missingFields': missingFields,
            }),
            serverRevision: Value(entity.serverRevision),
            isDeleted: Value(resolved),
          ),
        );
  }

  Future<void> _retainUnreadableEntity(
    AccountSyncEntity entity,
    List<String> missingFields,
  ) =>
      _writeRecoveryMarker('sync_repair', entity, missingFields: missingFields);

  Future<void> _resolveUnreadableEntity(AccountSyncEntity entity) async {
    if (!{'task', 'project'}.contains(entity.entityType)) return;
    if (await _recoveryMarker('sync_repair', entity) == null) return;
    await _writeRecoveryMarker('sync_repair', entity, resolved: true);
  }

  Future<void> _applyRequiredEntity(
    AccountSyncEntity entity,
    Future<bool> Function() apply,
  ) async {
    final old = await _recoveryMarker('sync_repair', entity);
    if (old != null && old.serverRevision > entity.serverRevision) return;
    var valid = false;
    try {
      valid = await apply();
    } on FormatException {
      /* Retain invalid values as well as missing fields. */
    } on TypeError {
      /* Drift JSON decoding can reject a field type. */
    }
    if (valid) {
      await _resolveUnreadableEntity(entity);
    } else {
      await _retainUnreadableEntity(entity, ['required_fields_or_types']);
    }
  }

  Future<bool> _hasUnsentEntity(AccountSyncEntity entity) async {
    final commands =
        await (_db.select(_db.syncCommands)..where(
              (r) =>
                  r.scopeId.isNull() &
                  (r.status.equals('pending') |
                      r.status.equals('rejected') |
                      r.status.equals('conflict')),
            ))
            .get();
    for (final command in commands) {
      try {
        final payload = Map<String, Object?>.from(
          jsonDecode(command.payloadJson) as Map,
        );
        if (payload.containsKey('_syncOperationsV1')) {
          if (_storedOperations(payload).any(
            (op) =>
                op.entityType == entity.entityType &&
                op.entityId == entity.entityId,
          )) {
            return true;
          }
        } else if (command.clientId == entity.entityId &&
            syncEntityTypeForCommand(command.type) == entity.entityType) {
          return true;
        }
      } on Object {
        if (command.clientId == entity.entityId) return true;
      }
    }
    return false;
  }

  Future<bool> _deferIncoming(AccountSyncEntity entity) async {
    if (!await _hasUnsentEntity(entity)) return false;
    if (entity.deleted && entity.entityType == 'task') {
      // A cloud tombstone cancels Undo, but the captured delete still replays
      // with its original identity until acknowledged.
      await (_db.update(_db.syncCommands)..where(
            (r) =>
                r.scopeId.isNull() &
                r.clientId.equals(entity.entityId) &
                r.type.equals('task.delete') &
                r.status.equals('pending'),
          ))
          .write(const SyncCommandsCompanion(availableAt: Value(null)));
    }
    await _writeRecoveryMarker('sync_incoming', entity);
    return true;
  }

  Future<void> _applyDeferredIncoming() async {
    final rows =
        await (_db.select(_db.sharedEntities)..where(
              (r) =>
                  r.scopeId.equals('_account') &
                  r.entityType.like('sync_incoming:%'),
            ))
            .get();
    for (final row in rows) {
      _checkSession();
      final entity = AccountSyncEntity.fromJson(
        Map<String, Object?>.from(jsonDecode(row.dataJson) as Map),
      );
      await _db.transaction(() async {
        if (await _hasUnsentEntity(entity)) return;
        // Reuse shared-scope guards as well as typed upserts. Keep the normal
        // cursor unchanged while applying a previously committed incoming row.
        final state = await _syncState();
        await _applyPullResult(
          AccountSyncPullResult(
            changes: [entity],
            nextCursor: int.tryParse(state?.cursor ?? '') ?? 0,
            hasMore: false,
          ),
        );
        await (_db.delete(_db.sharedEntities)..where(
              (r) =>
                  r.scopeId.equals('_account') &
                  r.entityType.equals(row.entityType) &
                  r.entityId.equals(row.entityId),
            ))
            .go();
      });
    }
  }

  Future<void> requestRecoveryScan() async {
    final userId = _account.currentUserId;
    await SyncOwnerStore.serialized(
      _db,
      () => _db.transaction(() async {
        final owner = await SyncOwnerStore(_db, _uuid).owner();
        if (userId == null ||
            _account.currentUserId != userId ||
            owner?.cursor != userId) {
          throw StateError('Account changed during recovery request');
        }
        await (_db.delete(
          _db.syncState,
        )..where((r) => r.id.equals(_repairStateId))).go();
      }),
    );
  }

  /// Bounded scan for records skipped by older clients. Never moves the normal
  /// cursor or imports old valid rows over current local intent.
  Future<Set<String>> recoverUnreadable() async {
    final deviceId = await _ensureDeviceId();
    var state = await (_db.select(
      _db.syncState,
    )..where((r) => r.id.equals(_repairStateId))).getSingleOrNull();
    var cursor = int.tryParse(state?.cursor ?? '') ?? 0;
    for (
      var page = 0;
      page < 4 && !(state?.cursor?.startsWith('done:') ?? false);
      page++
    ) {
      _checkSession();
      final result = await _account
          .pullChanges(
            appId: AccountAppId.pomodoist,
            deviceId: deviceId,
            sinceRevision: cursor,
            limit: 100,
          )
          .timeout(_requestTimeout);
      _checkSession();
      final done = !result.hasMore || result.nextCursor <= cursor;
      await _db.transaction(() async {
        for (final entity in result.changes) {
          final required = _required[entity.entityType];
          if (required == null || entity.data['scopeId'] != null) continue;
          if (entity.deleted) {
            await _resolveUnreadableEntity(entity);
            continue;
          }
          final old = await _recoveryMarker('sync_repair', entity);
          if (old != null && old.serverRevision > entity.serverRevision) {
            continue;
          }
          final missing = required
              .where((key) => entity.data[key] == null)
              .toList();
          if (missing.isEmpty) {
            try {
              final data = syncDataWithoutSyncMetadata(entity.data);
              if (entity.entityType == 'task') {
                TaskRow.fromJson(data);
              } else {
                ProjectRow.fromJson(data);
              }
              await _resolveUnreadableEntity(entity);
              continue;
            } on FormatException {
              missing.add('invalid_field_type');
            } on TypeError {
              missing.add('invalid_field_type');
            }
          }
          // Do not overwrite a repair's queued-operation marker on a repeat scan.
          if (old == null ||
              old.serverRevision != entity.serverRevision ||
              old.isDeleted) {
            await _retainUnreadableEntity(entity, missing);
          }
        }
        final now = DateTime.now().toUtc();
        await _db
            .into(_db.syncState)
            .insertOnConflictUpdate(
              SyncStateCompanion.insert(
                id: _repairStateId,
                deviceId: deviceId,
                cursor: Value(
                  done ? 'done:${result.nextCursor}' : '${result.nextCursor}',
                ),
                createdAt: now,
                updatedAt: now,
              ),
            );
      });
      cursor = result.nextCursor;
      if (done) break;
    }
    final unresolved =
        await (_db.select(_db.sharedEntities)..where(
              (r) =>
                  r.scopeId.equals('_account') &
                  r.entityType.like('sync_repair:%') &
                  r.isDeleted.equals(false),
            ))
            .get();
    for (final marker in unresolved) {
      _checkSession();
      await _db.transaction(() => _queueRepairFromLocal(marker, deviceId));
    }
    return {};
  }

  Future<void> _queueRepairFromLocal(
    SharedEntityRow marker,
    String deviceId,
  ) async {
    final envelope = Map<String, Object?>.from(
      jsonDecode(marker.dataJson) as Map,
    );
    final entity = AccountSyncEntity.fromJson(envelope);
    if (await _hasUnsentEntity(entity)) return;
    Map<String, Object?>? source;
    if (entity.entityType == 'task') {
      source =
          (await (_db.select(
                _db.tasks,
              )..where((r) => r.id.equals(entity.entityId))).getSingleOrNull())
              ?.toJson();
    } else if (entity.entityType == 'project') {
      source =
          (await (_db.select(
                _db.projects,
              )..where((r) => r.id.equals(entity.entityId))).getSingleOrNull())
              ?.toJson();
    }
    if (source == null ||
        source['scopeId'] != null ||
        source['isDeleted'] == true) {
      return;
    }
    // Only fill absent fields. The current cloud values and clock win.
    final payload = {
      ...source,
      ...syncDataWithoutSyncMetadata(entity.data),
      'id': entity.entityId,
    };
    final required = _required[entity.entityType];
    if (required == null) return;
    for (final key in required) {
      if (payload[key] == null) payload[key] = source[key];
    }
    if (!syncHasRequired(payload, required)) return;
    try {
      if (entity.entityType == 'task') {
        TaskRow.fromJson(payload);
      } else {
        ProjectRow.fromJson(payload);
      }
    } on FormatException {
      return;
    } on TypeError {
      return;
    }
    final timestamp = syncDateTimeFromSyncValue(payload['updatedAt']);
    if (timestamp == null) return;
    final id =
        'repair:${_uuid.v5(Namespace.url.value, jsonEncode([_account.currentUserId, entity.entityType, entity.entityId, entity.serverRevision, payload]))}';
    if (envelope['repairOperationId'] == id) return;
    final operation = _operation(
      opId: id,
      entityType: entity.entityType,
      entityId: entity.entityId,
      operation: 'upsert',
      payload: payload,
      clientUpdatedAt: timestamp,
    );
    await _db.transaction(() async {
      _checkSession();
      if (await _hasUnsentEntity(entity)) return;
      await _db
          .into(_db.syncCommands)
          .insert(
            SyncCommandsCompanion.insert(
              id: id,
              uuid: id,
              type: 'sync.snapshot',
              clientId: Value(entity.entityId),
              payloadJson: jsonEncode({
                '_syncDeviceIdV1': deviceId,
                '_syncOperationsV1': [operation.toJson()],
              }),
              createdAt: DateTime.now().toUtc(),
              updatedAt: timestamp,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      await (_db.update(_db.sharedEntities)..where(
            (r) =>
                r.scopeId.equals('_account') &
                r.entityType.equals(marker.entityType) &
                r.entityId.equals(marker.entityId),
          ))
          .write(
            SharedEntitiesCompanion(
              dataJson: Value(
                jsonEncode({...envelope, 'repairOperationId': id}),
              ),
            ),
          );
    });
  }
}
