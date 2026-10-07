part of 'account_sync_engine.dart';

extension AccountSyncPull on AccountSyncEngine {
  Future<Set<String>> pullLatest({
    Set<String> revokedScopeIds = const {},
  }) async {
    await _capturePendingOperations();
    await _applyDeferredIncoming();
    var scopesToRemove = revokedScopeIds;
    final deviceId = await _ensureDeviceId();
    final state = await _syncState();
    var sinceRevision = int.tryParse(state?.cursor ?? '') ?? 0;
    final entityTypes = <String>{};
    while (true) {
      if (_isSessionCurrent?.call() == false) {
        return entityTypes;
      }
      final result = await _account
          .pullChanges(
            appId: AccountAppId.pomodoist,
            deviceId: deviceId,
            sinceRevision: sinceRevision,
          )
          .timeout(_requestTimeout);
      _checkSession();
      entityTypes.addAll(result.changes.map((change) => change.entityType));
      if (result.nextCursor < sinceRevision) {
        _checkSession();
        await _saveCursor(result.nextCursor);
        await _resetImportState();
        final imported = await importLocalSnapshotIfNeeded(push: false);
        if (imported) {
          await _broadcastSyncHint();
        }
        await _repairKanbanAfterFinalPull();
        return entityTypes;
      }
      await _applyPullResult(result, revokedScopeIds: scopesToRemove);
      scopesToRemove = const {};
      _checkSession();
      if (!result.hasMore || result.nextCursor <= sinceRevision) {
        await _repairKanbanAfterFinalPull();
        return entityTypes;
      }
      sinceRevision = result.nextCursor;
    }
  }

  Future<void> _applyPullResult(
    AccountSyncPullResult result, {
    Set<String> revokedScopeIds = const {},
  }) async {
    _checkSession();
    await _db.transaction(() async {
      final removed = {...revokedScopeIds};
      // Inspect the complete page before applying rows: tasks may precede their
      // projects. A returned personal project replaces the old shared cache.
      for (final change in result.changes) {
        if (change.entityType != 'project' ||
            change.deleted ||
            change.data['scopeId'] != null) {
          continue;
        }
        final local = await (_db.select(
          _db.projects,
        )..where((row) => row.id.equals(change.entityId))).getSingleOrNull();
        if (local?.scopeId != null) removed.add(local!.scopeId!);
      }
      for (final scopeId in removed) {
        await removeSharedScope(_db, scopeId);
      }
      for (final change in result.changes) {
        _checkSession();
        if (change.entityType == 'task' &&
            (await (_db.select(_db.tasks)
                          ..where((r) => r.id.equals(change.entityId)))
                        .getSingleOrNull())
                    ?.scopeId !=
                null) {
          continue;
        }
        if (change.entityType == 'project' && change.data['scopeId'] != null) {
          continue;
        }
        if (!change.entityType.startsWith('focus_') &&
            change.entityType != 'attachment') {
          final scoped =
              await (_db.select(_db.sharedEntities)..where(
                    (row) =>
                        row.entityType.equals(change.entityType) &
                        row.entityId.equals(change.entityId),
                  ))
                  .get();
          if (scoped.any((row) => row.scopeId != '_account')) continue;
          final taskId =
              change.data['taskId'] as String? ??
              (change.entityType == 'task_kanban_status'
                  ? change.entityId
                  : null);
          if (taskId != null &&
              (await (_db.select(_db.tasks)
                            ..where((row) => row.id.equals(taskId)))
                          .getSingleOrNull())
                      ?.scopeId !=
                  null) {
            continue;
          }
        }
        if (await _deferIncoming(change)) continue;
        if (change.deleted) {
          await _applyDelete(change);
        } else {
          await _applyUpsert(change);
        }
      }
      _checkSession();
      await _saveCursor(result.nextCursor);
    });
  }

  Future<void> _repairKanbanAfterFinalPull() async {
    final timestamp = DateTime.now().toUtc();
    await _db.transaction(() async {
      await _repairKanban(timestamp: timestamp);
    });
  }

  Future<void> _applyUpsert(AccountSyncEntity entity) async {
    final data = syncDataWithoutSyncMetadata(entity.data);
    switch (entity.entityType) {
      case 'habit':
      case 'habit_check_in':
        await _applyHabitEntity(entity);
        return;
      case 'attachment':
        final cached =
            await (_db.select(_db.sharedEntities)..where(
                  (row) =>
                      row.scopeId.equals('_account') &
                      row.entityType.equals('attachment') &
                      row.entityId.equals(entity.entityId),
                ))
                .getSingleOrNull();
        if (cached != null &&
            (cached.serverRevision > entity.serverRevision ||
                cached.serverRevision == entity.serverRevision &&
                    cached.isDeleted)) {
          return;
        }
        await (_db.delete(_db.sharedEntities)..where(
              (row) =>
                  row.entityType.equals('attachment') &
                  row.entityId.equals(entity.entityId) &
                  row.scopeId.equals('_account').not(),
            ))
            .go();
        await _db
            .into(_db.sharedEntities)
            .insertOnConflictUpdate(
              SharedEntitiesCompanion.insert(
                scopeId: '_account',
                entityType: 'attachment',
                entityId: entity.entityId,
                dataJson: jsonEncode({
                  ...data,
                  'id': entity.entityId,
                  'scopeId': null,
                }),
                serverRevision: Value(entity.serverRevision),
              ),
            );
        return;
      case 'workspace':
        await _upsertWorkspace(entity.entityId, data);
        return;
      case 'project':
        await _applyRequiredEntity(
          entity,
          () => _upsertProject(entity.entityId, data),
        );
        return;
      case 'section':
        await _upsertSection(entity.entityId, data);
        return;
      case 'task':
        await _applyRequiredEntity(
          entity,
          () => _upsertTask(entity.entityId, data),
        );
        return;
      case 'task_completion':
        await _upsertTaskCompletion(entity.entityId, data);
        return;
      case 'label':
        await _upsertLabel(entity.entityId, data);
        return;
      case 'task_label':
        await _upsertTaskLabel(entity.entityId, data);
        return;
      case 'task_kanban_status':
        await _upsertTaskKanbanStatus(entity.entityId, data, entity.updatedAt);
        return;
      case 'kanban_settings':
        await _upsertKanbanSettings(entity.entityId, data, entity.updatedAt);
        return;
      case 'filter':
        await _upsertFilter(entity.entityId, data);
        return;
      case 'reminder':
        await _upsertReminder(entity.entityId, data);
        return;
      case 'focus_preset':
        await _upsertFocusPreset(entity.entityId, data);
        return;
      case 'focus_run':
        if (_isActiveFocusRunData(data)) {
          return;
        }
        await _upsertFocusRun(entity.entityId, data);
        return;
      case 'focus_interval':
        if (_isActiveFocusIntervalData(data)) {
          return;
        }
        await _upsertFocusInterval(entity.entityId, data);
        return;
      case 'focus_event':
        await _upsertFocusEvent(entity.entityId, data);
        return;
      case 'google_calendar_connection':
        await _upsertGoogleCalendarConnection(entity.entityId, data);
        return;
      case 'google_calendar_event_link':
        await _upsertGoogleCalendarEventLink(entity.entityId, data);
        return;
    }
  }

  Future<void> _applyDelete(AccountSyncEntity entity) async {
    await _resolveUnreadableEntity(entity);
    final now = entity.deletedAt ?? DateTime.now().toUtc();
    switch (entity.entityType) {
      case 'habit':
      case 'habit_check_in':
        await _applyHabitEntity(entity);
        return;
      case 'attachment':
        await _db
            .into(_db.sharedEntities)
            .insertOnConflictUpdate(
              SharedEntitiesCompanion.insert(
                scopeId: '_account',
                entityType: 'attachment',
                entityId: entity.entityId,
                dataJson: jsonEncode(entity.data),
                isDeleted: const Value(true),
                serverRevision: Value(entity.serverRevision),
              ),
            );
        return;
      case 'workspace':
        await (_db.update(
          _db.workspaces,
        )..where((row) => row.id.equals(entity.entityId))).write(
          WorkspacesCompanion(
            isDeleted: const Value(true),
            updatedAt: Value(now),
          ),
        );
        return;
      case 'project':
        await (_db.update(
          _db.projects,
        )..where((row) => row.id.equals(entity.entityId))).write(
          ProjectsCompanion(
            isDeleted: const Value(true),
            updatedAt: Value(now),
          ),
        );
        return;
      case 'section':
        await (_db.update(
          _db.sections,
        )..where((row) => row.id.equals(entity.entityId))).write(
          SectionsCompanion(
            isDeleted: const Value(true),
            updatedAt: Value(now),
          ),
        );
        return;
      case 'task':
        await (_db.delete(_db.syncCommands)..where(
              (row) =>
                  row.type.equals('task.delete') &
                  row.clientId.equals(entity.entityId) &
                  row.status.equals('pending'),
            ))
            .go();
        await (_db.update(
          _db.tasks,
        )..where((row) => row.id.equals(entity.entityId))).write(
          TasksCompanion(isDeleted: const Value(true), updatedAt: Value(now)),
        );
        return;
      case 'label':
        if (entity.entityId == kanbanStatusBacklogId ||
            entity.entityId == kanbanStatusDoneId) {
          return;
        }
        await (_db.update(
          _db.labels,
        )..where((row) => row.id.equals(entity.entityId))).write(
          LabelsCompanion(isDeleted: const Value(true), updatedAt: Value(now)),
        );
        return;
      case 'filter':
        await (_db.update(
          _db.filters,
        )..where((row) => row.id.equals(entity.entityId))).write(
          FiltersCompanion(isDeleted: const Value(true), updatedAt: Value(now)),
        );
        return;
      case 'reminder':
        await (_db.update(
          _db.reminders,
        )..where((row) => row.id.equals(entity.entityId))).write(
          RemindersCompanion(
            isDeleted: const Value(true),
            updatedAt: Value(now),
          ),
        );
        return;
      case 'focus_preset':
        await (_db.update(
          _db.focusPresets,
        )..where((row) => row.id.equals(entity.entityId))).write(
          FocusPresetsCompanion(
            isDeleted: const Value(true),
            updatedAt: Value(now),
          ),
        );
        return;
      case 'focus_run':
        await (_db.update(
          _db.focusRuns,
        )..where((row) => row.id.equals(entity.entityId))).write(
          FocusRunsCompanion(
            isDeleted: const Value(true),
            updatedAt: Value(now),
          ),
        );
        return;
      case 'focus_interval':
        await (_db.update(
          _db.focusIntervals,
        )..where((row) => row.id.equals(entity.entityId))).write(
          FocusIntervalsCompanion(
            isDeleted: const Value(true),
            updatedAt: Value(now),
          ),
        );
        return;
      case 'task_label':
        final ids = syncTaskLabelIdsFromEntity(entity);
        if (ids != null) {
          await (_db.delete(_db.taskLabels)..where(
                (row) =>
                    row.taskId.equals(ids.taskId) &
                    row.labelId.equals(ids.labelId) &
                    row.kind.equals(labelKindUser),
              ))
              .go();
        }
        return;
      case 'task_kanban_status':
        await (_db.delete(_db.taskLabels)..where(
              (row) =>
                  row.taskId.equals(entity.entityId) &
                  row.kind.equals(labelKindKanbanStatus),
            ))
            .go();
        return;
      case 'kanban_settings':
        await (_db.delete(
          _db.kanbanSettings,
        )..where((row) => row.id.equals(entity.entityId))).go();
        return;
      case 'task_completion':
        await (_db.delete(
          _db.taskCompletions,
        )..where((row) => row.id.equals(entity.entityId))).go();
        return;
      case 'focus_event':
        await (_db.delete(
          _db.focusEvents,
        )..where((row) => row.id.equals(entity.entityId))).go();
        return;
      case 'google_calendar_connection':
        await (_db.delete(
          _db.googleCalendarConnections,
        )..where((row) => row.id.equals(entity.entityId))).go();
        return;
      case 'google_calendar_event_link':
        await (_db.delete(
          _db.googleCalendarEventLinks,
        )..where((row) => row.taskId.equals(entity.entityId))).go();
        return;
    }
  }

  bool _isActiveFocusRunData(Map<String, dynamic> data) {
    final status = data['status'];
    return status == 'active' || status == 'paused';
  }

  bool _isActiveFocusIntervalData(Map<String, dynamic> data) {
    final status = data['status'];
    return status == 'running' || status == 'paused' || status == 'ready';
  }
}
