part of 'account_sync_engine.dart';

extension SharedAccountSync on AccountSyncEngine {
  Future<Set<String>> syncShared() async {
    final api = _collaboration;
    if (api == null || _isSessionCurrent?.call() == false) return {};
    late Map<String, dynamic> state;
    try {
      state = await _callCollaboration('state');
    } on CollaborationException catch (error) {
      // Older servers keep the existing personal API usable until this endpoint is installed.
      if (error.code == 'function_not_found' &&
          (await _db.select(_db.sharedScopes).get()).isEmpty) {
        return {};
      }
      rethrow;
    }
    final scopes = collaborationMaps(state['scopes']);
    if (state['personalHistory'] is Map) {
      await _db
          .into(_db.sharedEntities)
          .insertOnConflictUpdate(
            SharedEntitiesCompanion.insert(
              scopeId: '_account',
              entityType: 'history',
              entityId: 'personal',
              dataJson: jsonEncode(state['personalHistory']),
            ),
          );
    }
    final ids = scopes.map((scope) => scope['id'] as String).toSet();
    final oldScopes = await _db.select(_db.sharedScopes).get();
    final revoked = oldScopes
        .where((scope) => !ids.contains(scope.id))
        .map((scope) => scope.id)
        .toList();
    // `unshare` restores the subtree as personal rows and drops the scope, so
    // pull the personal side before removing the shared copy. Otherwise the
    // removal deletes rows the server just handed back, and the user loses the
    // project they only meant to unshare.
    for (final scopeId in revoked) {
      await pullLatest();
      await _removeSharedScope(scopeId);
    }
    await _db.transaction(() async {
      for (final scope in scopes) {
        final id = scope['id'] as String;
        final old = oldScopes.where((row) => row.id == id).firstOrNull;
        final oldData = old == null
            ? <String, dynamic>{}
            : jsonDecode(old.dataJson) as Map<String, dynamic>;
        await _db
            .into(_db.sharedScopes)
            .insertOnConflictUpdate(
              SharedScopesCompanion.insert(
                id: id,
                dataJson: jsonEncode({...oldData, ...scope}),
                cursor: Value(old?.cursor ?? 0),
              ),
            );
      }
      for (final (key, type) in [
        ('notifications', 'notification'),
        ('invitations', 'invitation'),
      ]) {
        await (_db.delete(_db.sharedEntities)..where(
              (row) =>
                  row.scopeId.equals('_account') & row.entityType.equals(type),
            ))
            .go();
        for (final item in collaborationMaps(state[key])) {
          final id = item['id']?.toString();
          if (id == null) continue;
          await _db
              .into(_db.sharedEntities)
              .insert(
                SharedEntitiesCompanion.insert(
                  scopeId: '_account',
                  entityType: type,
                  entityId: id,
                  dataJson: jsonEncode(item),
                ),
              );
        }
      }
    });
    final types = <String>{};
    for (final scopeData in scopes) {
      final scope = SharedScope.fromJson(scopeData);
      try {
        // Pull first: membership and server revision precede any offline replay.
        await _pushSharedPreferences(scope.id);
        types.addAll(await _pullSharedScope(scope.id));
        if (scope.canEdit) {
          await _enqueueSharedFocus(scope.id);
          types.addAll(await _pushSharedScope(scope.id));
        } else {
          await (_db.update(_db.syncCommands)..where(
                (row) =>
                    row.scopeId.equals(scope.id) & row.status.equals('pending'),
              ))
              .write(
                const SyncCommandsCompanion(
                  status: Value('rejected'),
                  lastError: Value('forbidden'),
                ),
              );
        }
      } on CollaborationException catch (error) {
        if (error.code == '42501') {
          final current = await _callCollaboration('state');
          if (!collaborationMaps(
            current['scopes'],
          ).any((item) => item['id'] == scope.id)) {
            await _removeSharedScope(scope.id);
            continue;
          }
        }
        rethrow;
      }
    }
    return types;
  }

  Future<Set<String>> _pullSharedScope(String scopeId) async {
    final types = <String>{};
    while (true) {
      final scope = await (_db.select(
        _db.sharedScopes,
      )..where((s) => s.id.equals(scopeId))).getSingle();
      final response = await _callCollaboration('pull', {
        'scopeId': scopeId,
        'sinceRevision': scope.cursor,
        'deviceId': await _ensureDeviceId(),
      });
      final changes = collaborationMaps(response['changes']);
      final next = (response['nextCursor'] as num?)?.toInt() ?? scope.cursor;
      if (_isSessionCurrent?.call() == false) {
        return types;
      }
      await _db.transaction(() async {
        for (final change in changes) {
          await _applySharedChange(scopeId, change);
          types.add(change['entityType'] as String);
        }
        await _applySharedPreferences(
          scopeId,
          collaborationMaps(response['preferences']),
        );
        final data = jsonDecode(scope.dataJson) as Map<String, dynamic>;
        if (response['members'] != null) data['members'] = response['members'];
        await (_db.update(
          _db.sharedScopes,
        )..where((s) => s.id.equals(scopeId))).write(
          SharedScopesCompanion(
            cursor: Value(next),
            dataJson: Value(jsonEncode(data)),
          ),
        );
      });
      if (response['hasMore'] != true || next <= scope.cursor) break;
    }
    return types;
  }

  Future<void> _pushSharedPreferences(String scopeId) async {
    final commands =
        await (_db.select(_db.syncCommands)
              ..where(
                (row) =>
                    row.scopeId.equals(scopeId) &
                    row.type.equals('private.preferences') &
                    row.status.equals('pending'),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
            .get();
    for (final command in commands) {
      await _callCollaboration(
        'preferences',
        jsonDecode(command.payloadJson) as Map<String, dynamic>,
      );
      await (_db.delete(
        _db.syncCommands,
      )..where((row) => row.id.equals(command.id))).go();
    }
  }

  Future<void> _applySharedPreferences(
    String scopeId,
    List<Map<String, dynamic>> preferences,
  ) async {
    for (final preference in preferences) {
      final id = preference['entityId'] as String;
      final data = Map<String, dynamic>.from(preference['data'] as Map);
      switch (preference['entityType']) {
        case 'task':
          await (_db.update(_db.tasks)..where(
                (row) => row.scopeId.equals(scopeId) & row.id.equals(id),
              ))
              .write(
                TasksCompanion(
                  isCollapsed: data.containsKey('isCollapsed')
                      ? Value(data['isCollapsed'] as bool)
                      : const Value.absent(),
                  dayOrder: data.containsKey('dayOrder')
                      ? Value((data['dayOrder'] as num?)?.toInt())
                      : const Value.absent(),
                ),
              );
        case 'project':
          await (_db.update(_db.projects)..where(
                (row) => row.scopeId.equals(scopeId) & row.id.equals(id),
              ))
              .write(
                ProjectsCompanion(
                  isFavorite: data.containsKey('isFavorite')
                      ? Value(data['isFavorite'] as bool)
                      : const Value.absent(),
                  viewStyle: data.containsKey('viewStyle')
                      ? Value(data['viewStyle'] as String)
                      : const Value.absent(),
                ),
              );
        case 'scope':
          final scope = await (_db.select(
            _db.sharedScopes,
          )..where((row) => row.id.equals(scopeId))).getSingle();
          final rootId =
              (jsonDecode(scope.dataJson) as Map)['rootProjectId'] as String;
          if (data.containsKey('rootParentId')) {
            await (_db.update(
              _db.projects,
            )..where((row) => row.id.equals(rootId))).write(
              ProjectsCompanion(
                parentId: Value(data['rootParentId'] as String?),
                orderKey:
                    (data['viewPreferences'] as Map?)?['orderKey'] is String
                    ? Value(
                        (data['viewPreferences'] as Map)['orderKey'] as String,
                      )
                    : const Value.absent(),
              ),
            );
          }
      }
    }
  }

  Future<void> _applySharedChange(
    String scopeId,
    Map<String, dynamic> change,
  ) async {
    final type = change['entityType'] as String;
    final id = change['entityId'] as String;
    final data = Map<String, dynamic>.from(change['data'] as Map? ?? {})
      ..putIfAbsent('updatedAt', () => change['updatedAt']);
    final revision = (change['serverRevision'] as num?)?.toInt() ?? 0;
    final deleted = change['deletedAt'] != null || data['isDeleted'] == true;
    final previous =
        await (_db.select(_db.sharedEntities)..where(
              (row) =>
                  row.scopeId.equals(scopeId) &
                  row.entityType.equals(type) &
                  row.entityId.equals(id),
            ))
            .getSingleOrNull();
    if (previous != null && revision < previous.serverRevision) return;
    if (type == 'comment' && !deleted) {
      final local =
          await (_db.select(_db.syncCommands)..where(
                (row) =>
                    row.scopeId.equals(scopeId) &
                    row.clientId.equals(id) &
                    (row.status.equals('pending') |
                        row.status.equals('conflict')),
              ))
              .get();
      if (local.isNotEmpty) return;
    }
    await _db
        .into(_db.sharedEntities)
        .insertOnConflictUpdate(
          SharedEntitiesCompanion.insert(
            scopeId: scopeId,
            entityType: type,
            entityId: id,
            dataJson: jsonEncode(data),
            serverRevision: Value(revision),
            isDeleted: Value(deleted),
          ),
        );
    if (!{
      'project',
      'section',
      'task',
      'label',
      'task_label',
      'task_kanban_status',
      'task_completion',
    }.contains(type)) {
      return;
    }
    final pending =
        await (_db.select(_db.syncCommands)
              ..where(
                (row) =>
                    row.scopeId.equals(scopeId) &
                    (row.status.equals('pending') |
                        row.status.equals('conflict')),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
            .get();
    if (type == 'task_completion' && data['userId'] != _account.currentUserId) {
      return;
    }
    final normalized = <String, dynamic>{
      'id': id,
      'userId': localUserId,
      'createdAt': data['createdAt'] ?? change['updatedAt'],
      'updatedAt': change['updatedAt'] ?? data['updatedAt'],
      'isDeleted': deleted,
      'isArchived': false,
      'isCollapsed': false,
      'isFavorite': false,
      'viewStyle': 'list',
      'orderKey': id,
      'priority': 4,
      'status': 'open',
      'completedFocusIntervals': 0,
      'totalFocusSeconds': 0,
      ...data,
      if (type == 'project' || type == 'task' || type == 'label')
        'scopeId': scopeId,
      if (type == 'task')
        'assigneeIdsJson': jsonEncode(data['assigneeIds'] ?? []),
    };
    // Overlay only this entity's remaining field patches onto the canonical copy.
    // Relation commands must not suppress unrelated task fields as cursors advance.
    if (!deleted) {
      for (final command in pending) {
        final payload = jsonDecode(command.payloadJson) as Map<String, dynamic>;
        if (syncEntityTypeForCommand(command.type) != type ||
            syncEntityIdForCommand(
                  (
                    id: command.id,
                    clientId: command.clientId,
                    uuid: command.uuid,
                  ),
                  payload,
                  type,
                ) !=
                id) {
          continue;
        }
        if (command.type == 'task.assign') {
          final assignees =
              collaborationIds(normalized['assigneeIdsJson'] as String).toSet()
                ..removeAll((payload['remove'] as List? ?? []).cast<String>())
                ..addAll((payload['add'] as List? ?? []).cast<String>());
          normalized['assigneeIdsJson'] = jsonEncode(
            assignees.toList()..sort(),
          );
        } else {
          normalized.addAll(_sharedCommandPatch(command));
        }
      }
    }
    if (type == 'task_completion' && normalized['snapshotJson'] is Map) {
      final snapshot = Map<String, dynamic>.from(
        normalized['snapshotJson'] as Map,
      );
      // Older servers returned only task fields and dropped workflow history.
      if (!snapshot.containsKey('version') && !snapshot.containsKey('kanban')) {
        final local = await (_db.select(
          _db.taskCompletions,
        )..where((row) => row.id.equals(id))).getSingleOrNull();
        try {
          final previous = jsonDecode(local?.snapshotJson ?? 'null');
          if (previous is Map && previous['version'] == 1) {
            final kanban = previous['kanban'];
            if (kanban is Map &&
                kanban['previousStatusLabelId'] is String &&
                (kanban['previousStatusLabelId'] as String).trim().isNotEmpty) {
              snapshot.addAll({'version': 1, 'kanban': kanban});
            }
          }
        } on FormatException {
          // A malformed local snapshot must not block canonical history sync.
        }
      }
      normalized['snapshotJson'] = jsonEncode(snapshot);
    }
    if (type == 'project') {
      final local = await (_db.select(
        _db.projects,
      )..where((p) => p.id.equals(id))).getSingleOrNull();
      normalized['isFavorite'] = local?.isFavorite ?? false;
      normalized['viewStyle'] = local?.viewStyle ?? 'list';
    }
    if (type == 'task') {
      final local = await (_db.select(
        _db.tasks,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      normalized['isCollapsed'] = local?.isCollapsed ?? false;
      normalized['dayOrder'] = local?.dayOrder;
    }
    for (final key in ['createdAt', 'updatedAt', 'completedAt', 'changedAt']) {
      if (normalized[key] != null) {
        normalized[key] = syncDateTimeFromSyncValue(
          normalized[key],
        )?.millisecondsSinceEpoch;
      }
    }
    final entity = AccountSyncEntity.fromJson({...change, 'data': normalized});
    if (deleted) {
      await _applyDelete(entity);
      await (_db.update(_db.syncCommands)..where(
            (row) =>
                row.scopeId.equals(scopeId) &
                row.clientId.equals(id) &
                row.status.equals('pending'),
          ))
          .write(
            const SyncCommandsCompanion(
              status: Value('rejected'),
              lastError: Value('deleted'),
            ),
          );
    } else {
      await _applyUpsert(entity);
    }
  }

  Future<Set<String>> _pushSharedScope(String scopeId) async {
    final types = <String>{};
    // ponytail: serialize commands within a scope for dependent revisions; batch independent entities if latency matters.
    for (var round = 0; round < 100; round++) {
      final commands =
          await (_db.select(_db.syncCommands)
                ..where(
                  (row) =>
                      row.scopeId.equals(scopeId) &
                      row.type.equals('private.preferences').not() &
                      row.status.equals('pending') &
                      (row.availableAt.isNull() |
                          row.availableAt.isSmallerOrEqualValue(
                            DateTime.now().toUtc(),
                          )),
                )
                ..orderBy([(row) => OrderingTerm.asc(row.createdAt)])
                ..limit(100))
              .get();
      if (commands.isEmpty) break;
      final command = commands.first;
      final payload = jsonDecode(command.payloadJson) as Map<String, dynamic>;
      var operations = await _operationsFromCommand(command, null);
      if (command.type == 'focus_contribution.create') {
        operations = [
          AccountSyncOperation(
            opId: command.uuid,
            entityType: 'focus_interval',
            entityId: command.clientId!,
            operation: 'upsert',
            payload: payload,
            clientUpdatedAt: command.updatedAt,
          ),
        ];
      }
      if (command.type == 'task.assign') {
        operations = [
          AccountSyncOperation(
            opId: command.uuid,
            entityType: 'task',
            entityId: command.clientId!,
            operation: 'assign',
            payload: payload,
            clientUpdatedAt: command.updatedAt,
          ),
        ];
      }
      final response = await _callCollaboration('push', {
        'scopeId': scopeId,
        'deviceId': await _ensureDeviceId(),
        'operations': operations.map((op) {
          final data = Map<String, dynamic>.from(op.payload)
            ..remove('isFavorite')
            ..remove('isCollapsed')
            ..remove('dayOrder')
            ..remove('viewStyle')
            // The shared scope accepts entity fields only; schemaVersion is envelope metadata.
            ..remove('schemaVersion');
          if (op.entityType != 'task_label' &&
              op.entityType != 'task_kanban_status') {
            data.remove('changedAt');
          }
          if (data['assigneeIdsJson'] is String) {
            data['assigneeIds'] = jsonDecode(
              data.remove('assigneeIdsJson') as String,
            );
          }
          if (payload['recurrenceSourceId'] != null) {
            data['recurrenceSourceId'] = payload['recurrenceSourceId'];
            data['occurrenceKey'] = payload['occurrenceKey'];
          }
          return {
            ...op.toJson(),
            'payload': data,
            'baseRevision': command.baseRevision,
          };
        }).toList(),
      });
      final conflicts = collaborationMaps(response['conflicts']);
      final rejected = collaborationMaps(response['rejected']);
      final applied = collaborationMaps(response['applied']);
      final acknowledged = applied.map((item) => item['opId']).toSet();
      if (conflicts.isNotEmpty || rejected.isNotEmpty) {
        await (_db.update(
          _db.syncCommands,
        )..where((row) => row.id.equals(command.id))).write(
          SyncCommandsCompanion(
            status: Value(conflicts.isNotEmpty ? 'conflict' : 'rejected'),
            lastError: Value(
              jsonEncode(
                conflicts.isNotEmpty ? conflicts.first : rejected.first,
              ),
            ),
          ),
        );
      } else if (operations.every((op) => acknowledged.contains(op.opId))) {
        await (_db.delete(
          _db.syncCommands,
        )..where((row) => row.id.equals(command.id))).go();
        // Advance only patches wholly covered by our accepted fields. A scalar
        // revision must never waive conflicts on another member's unseen fields.
        final acceptedFields = _sharedCommandPatch(command).keys.toSet();
        final entityType = syncEntityTypeForCommand(command.type);
        final later =
            await (_db.select(_db.syncCommands)..where(
                  (row) =>
                      row.scopeId.equals(scopeId) &
                      row.clientId.equals(command.clientId ?? '') &
                      row.status.equals('pending'),
                ))
                .get();
        for (final next in later) {
          if (next.baseRevision < command.baseRevision ||
              syncEntityTypeForCommand(next.type) != entityType ||
              !acceptedFields.containsAll(_sharedCommandPatch(next).keys) ||
              !command.type.endsWith('.create') &&
                  !command.type.endsWith('.update') &&
                  !syncUsesCapturedPatch(command.type) ||
              !next.type.endsWith('.update') &&
                  !syncUsesCapturedPatch(next.type)) {
            continue;
          }
          final accepted = applied
              .where((item) => item['opId'] == command.uuid)
              .firstOrNull;
          final revision = (accepted?['serverRevision'] as num?)?.toInt();
          if (revision == null || revision <= next.baseRevision) continue;
          await (_db.update(_db.syncCommands)
                ..where((row) => row.id.equals(next.id)))
              .write(SyncCommandsCompanion(baseRevision: Value(revision)));
        }
      } else {
        throw const CollaborationException('incomplete_acknowledgement');
      }
      types.addAll(await _pullSharedScope(scopeId));
      // A rejection/ack may leave no newer server change for the affected entity.
      for (final operation in operations) {
        final cached =
            await (_db.select(_db.sharedEntities)..where(
                  (row) =>
                      row.scopeId.equals(scopeId) &
                      row.entityType.equals(operation.entityType) &
                      row.entityId.equals(operation.entityId),
                ))
                .getSingleOrNull();
        if (cached == null) continue;
        final data = jsonDecode(cached.dataJson) as Map<String, dynamic>;
        await _applySharedChange(scopeId, {
          'entityType': cached.entityType,
          'entityId': cached.entityId,
          'serverRevision': cached.serverRevision,
          'data': data,
          'updatedAt': syncDateTimeFromSyncValue(
            data['updatedAt'],
          )?.toIso8601String(),
          'deletedAt': cached.isDeleted
              ? command.updatedAt.toIso8601String()
              : null,
        });
      }
    }
    return types;
  }

  Map<String, Object?> _sharedCommandPatch(SyncCommandRow command) {
    return syncCapturedPatchPayload(
      command.type,
      jsonDecode(command.payloadJson) as Map<String, dynamic>,
      command.updatedAt,
    )..removeWhere(
      (key, _) => {
        'id',
        'scopeId',
        'createdBy',
        'userId',
        'createdAt',
        'updatedAt',
        'changedAt',
        'commandType',
      }.contains(key),
    );
  }

  Future<void> _enqueueSharedFocus(String scopeId) async {
    final tasks = await (_db.select(
      _db.tasks,
    )..where((row) => row.scopeId.equals(scopeId))).get();
    final ids = tasks.map((row) => row.id).toList();
    if (ids.isEmpty) return;
    final intervals =
        await (_db.select(_db.focusIntervals)..where(
              (row) =>
                  row.taskId.isIn(ids) &
                  row.type.equals('work') &
                  row.status.equals('completed') &
                  row.isDeleted.equals(false),
            ))
            .get();
    for (final interval in intervals) {
      final existing =
          await (_db.select(_db.sharedEntities)..where(
                (row) =>
                    row.scopeId.equals(scopeId) &
                    row.entityType.equals('focus_interval') &
                    row.entityId.equals(interval.id),
              ))
              .getSingleOrNull();
      final pending =
          await (_db.select(_db.syncCommands)..where(
                (row) =>
                    row.scopeId.equals(scopeId) &
                    row.clientId.equals(interval.id),
              ))
              .get();
      if (existing != null || pending.isNotEmpty) continue;
      await DriftOutboxService(_db).enqueue(
        type: 'focus_contribution.create',
        clientId: interval.id,
        payload: {
          ...interval.toJson(),
          'scopeId': scopeId,
          'userId': _account.currentUserId,
          'durationSeconds':
              ((interval.completedAt!.difference(interval.startedAt).inSeconds -
                      interval.pausedTotalSeconds)
                  .clamp(0, 2147483647)),
        },
      );
    }
  }

  /// [keepEntityType], [keepEntityIds] and [keepProjectIds] are the rows the
  /// server has already handed back as personal data in the same pull. They are
  /// spared so that unsharing restores the subtree instead of deleting it.
  Future<void> _removeSharedScope(
    String scopeId, {
    String? keepEntityType,
    Set<String> keepEntityIds = const {},
    Set<String> keepProjectIds = const {},
  }) async {
    await _db.transaction(() async {
      final tasks = await (_db.select(
        _db.tasks,
      )..where((row) => row.scopeId.equals(scopeId))).get();
      final ids = tasks.map((row) => row.id).toList();
      final projects = await (_db.select(
        _db.projects,
      )..where((row) => row.scopeId.equals(scopeId))).get();
      final projectIds = [
        for (final project in projects)
          if (!(keepEntityType == 'project' &&
              keepProjectIds.contains(project.id)))
            project.id,
      ];
      await (_db.delete(
        _db.taskLabels,
      )..where((row) => row.taskId.isIn(ids))).go();
      await (_db.delete(
        _db.taskCompletions,
      )..where((row) => row.taskId.isIn(ids))).go();
      await (_db.delete(
        _db.reminders,
      )..where((row) => row.taskId.isIn(ids))).go();
      // A kept project is also where the server reassigned the tasks it handed
      // back, so only the projects that are actually going away lose sections.
      await (_db.delete(
        _db.sections,
      )..where((row) => row.projectId.isIn(projectIds))).go();
      await (_db.delete(
        _db.tasks,
      )..where((row) => row.scopeId.equals(scopeId))).go();
      await (_db.delete(_db.projects)..where(
            (row) => row.scopeId.equals(scopeId) & row.id.isNotIn(projectIds),
          ))
          .go();
      // Keep only the user's unsent text; do not retain cached shared snapshots.
      final pending = await (_db.select(
        _db.syncCommands,
      )..where((row) => row.scopeId.equals(scopeId))).get();
      for (final command in pending) {
        final payload = jsonDecode(command.payloadJson) as Map<String, dynamic>;
        final ownText = <String, dynamic>{
          for (final key in ['content', 'description', 'body'])
            if (payload[key] is String) key: payload[key],
        };
        if (ownText.isEmpty) {
          await (_db.delete(
            _db.syncCommands,
          )..where((row) => row.id.equals(command.id))).go();
        } else {
          await (_db.update(
            _db.syncCommands,
          )..where((row) => row.id.equals(command.id))).write(
            SyncCommandsCompanion(
              status: const Value('revoked'),
              payloadJson: Value(jsonEncode(ownText)),
              lastError: const Value('access_revoked'),
            ),
          );
        }
      }
      await (_db.delete(
        _db.labels,
      )..where((row) => row.scopeId.equals(scopeId))).go();
      // The handed-back rows keep their shared entity marker; dropping it here
      // would let the shared-entity guard in the pull accept a later change for
      // the same id, so the same guard clears it when the row is applied.
      await (_db.delete(_db.sharedEntities)..where(
            (row) =>
                row.scopeId.equals(scopeId) &
                row.entityType.equals(keepEntityType ?? '') &
                row.entityId.isIn(keepEntityIds),
          ))
          .go();
      await (_db.delete(
        _db.sharedScopes,
      )..where((row) => row.id.equals(scopeId))).go();
    });
  }
}
