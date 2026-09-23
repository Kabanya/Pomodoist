part of 'account_sync_engine.dart';

extension AccountSyncPull on AccountSyncEngine {
  Future<Set<String>> pullLatest() async {
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
        final imported = await importLocalSnapshotIfNeeded();
        if (imported) {
          await _broadcastSyncHint();
        }
        await _repairKanbanAfterFinalPull();
        return entityTypes;
      }
      await _applyPullResult(result);
      _checkSession();
      await _saveCursor(result.nextCursor);
      if (!result.hasMore || result.nextCursor <= sinceRevision) {
        await _repairKanbanAfterFinalPull();
        return entityTypes;
      }
      sinceRevision = result.nextCursor;
    }
  }

  Future<void> _applyPullResult(AccountSyncPullResult result) async {
    if (result.changes.isEmpty || _isSessionCurrent?.call() == false) {
      return;
    }

    await _db.transaction(() async {
      // `unshare` restores the whole subtree as personal rows and drops the
      // scope. Every restored row must be known before the first one is applied,
      // because removing the shared copy takes its children with it. Resolve
      // them in one pass so the removal can spare exactly what comes back.
      //
      // Each row is matched to the scope it still carries locally, never to the
      // scope of a row it points at: the project and its tasks come back in the
      // same batch, so a task would otherwise be judged by a project that has
      // already lost its scope and get swept away with it.
      final handedBack = <String, Map<String, String>>{};
      for (final change in result.changes) {
        if (change.deleted || change.data['scopeId'] != null) continue;
        final scopeId = await _localScopeIdOf(change);
        if (scopeId != null) {
          handedBack.putIfAbsent(scopeId, () => <String, String>{})[
              change.entityId] =
              change.entityType;
        }
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
        if (change.entityType == 'project') {
          final local = await _localScopeIdOf(change);
          final kept = handedBack[local];
          if (local != null) {
            // Still scoped here but unscoped on the server: the scope was
            // unshared and this change is the personal row that replaces it.
            // Drop the shared copy first, or the shared-entity guard below
            // skips the very row that has to land.
            if (change.data['scopeId'] != null) continue;
            await _removeSharedScope(
              local,
              keepEntityType: change.entityType,
              keepEntityIds: kept?.keys.toSet() ?? const {},
              keepProjectIds: kept?.keys.toSet() ?? const {},
            );
            // Every kept row keeps its shared marker through the removal, so
            // all of them must lose it before the guard below lets them land.
            for (final entry in kept?.entries ?? const Iterable.empty()) {
              await _clearSharedEntity(entry.value, entry.key);
            }
          }
        }
        if (!change.entityType.startsWith('focus_')) {
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
        if (change.deleted) {
          await _applyDelete(change);
        } else {
          await _applyUpsert(change);
        }
      }
    });
  }

  /// The scope a locally stored project still carries, which is what marks it as
  /// a shared copy the server may have just handed back as personal.
  Future<String?> _localScopeIdOf(AccountSyncEntity change) async {
    switch (change.entityType) {
      case 'project':
        return (await (_db.select(
          _db.projects,
        )..where((row) => row.id.equals(change.entityId))).getSingleOrNull())
            ?.scopeId;
      case 'task':
        final own = await (_db.select(
          _db.tasks,
        )..where((row) => row.id.equals(change.entityId))).getSingleOrNull();
        if (own?.scopeId != null) return own!.scopeId;
        // The row may already be gone when the scope's own batch arrives first,
        // so fall back to the project the task belongs to.
        final projectId = change.data['projectId'] as String?;
        if (projectId == null) return null;
        return (await (_db.select(
          _db.projects,
        )..where((row) => row.id.equals(projectId))).getSingleOrNull())
            ?.scopeId;
      case 'section':
        // A section carries no scope of its own; it belongs to a project that
        // does, so resolve through that project.
        final section = await (_db.select(
          _db.sections,
        )..where((row) => row.id.equals(change.entityId))).getSingleOrNull();
        final projectId = section?.projectId;
        if (projectId == null) return null;
        return (await (_db.select(
          _db.projects,
        )..where((row) => row.id.equals(projectId))).getSingleOrNull())
            ?.scopeId;
      default:
        return null;
    }
  }

  Future<void> _clearSharedEntity(String entityType, String entityId) async {
    await (_db.delete(_db.sharedEntities)..where(
          (row) =>
              row.entityType.equals(entityType) & row.entityId.equals(entityId),
        ))
        .go();
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
      case 'workspace':
        await _upsertWorkspace(entity.entityId, data);
        return;
      case 'project':
        await _upsertProject(entity.entityId, data);
        return;
      case 'section':
        await _upsertSection(entity.entityId, data);
        return;
      case 'task':
        await _upsertTask(entity.entityId, data);
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
    final now = entity.deletedAt ?? DateTime.now().toUtc();
    switch (entity.entityType) {
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
