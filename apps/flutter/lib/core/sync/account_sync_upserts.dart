part of 'account_sync_engine.dart';

extension AccountSyncUpserts on AccountSyncEngine {
  Future<void> _upsertFilter(String id, Map<String, dynamic> data) async {
    final existing = await (_db.select(
      _db.filters,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    final merged = syncMergeRow(existing?.toJson(), data);
    if (!syncHasRequired(merged, [
      'id',
      'userId',
      'name',
      'query',
      'isFavorite',
      'orderKey',
      'isDeleted',
      'createdAt',
      'updatedAt',
    ])) {
      return;
    }
    await _db
        .into(_db.filters)
        .insertOnConflictUpdate(FilterRow.fromJson(merged));
  }

  Future<void> _upsertFocusEvent(String id, Map<String, dynamic> data) async {
    final existing = await (_db.select(
      _db.focusEvents,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    final merged = syncMergeRow(existing?.toJson(), data);
    if (!syncHasRequired(merged, [
      'id',
      'runId',
      'type',
      'occurredAt',
      'createdAt',
    ])) {
      return;
    }
    await _db
        .into(_db.focusEvents)
        .insertOnConflictUpdate(FocusEventRow.fromJson(merged));
  }

  Future<void> _upsertFocusInterval(
    String id,
    Map<String, dynamic> data,
  ) async {
    final existing = await (_db.select(
      _db.focusIntervals,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    final merged = syncMergeRow(existing?.toJson(), data);
    if (!syncHasRequired(merged, [
      'id',
      'runId',
      'type',
      'status',
      'plannedSeconds',
      'startedAt',
      'pausedTotalSeconds',
      'sequenceNumber',
      'createdAt',
      'updatedAt',
      'isDeleted',
    ])) {
      return;
    }
    await _db
        .into(_db.focusIntervals)
        .insertOnConflictUpdate(FocusIntervalRow.fromJson(merged));
  }

  Future<void> _upsertFocusPreset(String id, Map<String, dynamic> data) async {
    final existing = await (_db.select(
      _db.focusPresets,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    final merged = syncMergeRow(existing?.toJson(), data);
    if (!syncHasRequired(merged, [
      'id',
      'userId',
      'name',
      'workSeconds',
      'shortBreakSeconds',
      'longBreakSeconds',
      'intervalsBeforeLongBreak',
      'autoStartBreaks',
      'autoStartWork',
      'allowPause',
      'strictMode',
      'isDefault',
      'isDeleted',
      'createdAt',
      'updatedAt',
    ])) {
      return;
    }
    await _db
        .into(_db.focusPresets)
        .insertOnConflictUpdate(FocusPresetRow.fromJson(merged));
  }

  Future<void> _upsertFocusRun(String id, Map<String, dynamic> data) async {
    final existing = await (_db.select(
      _db.focusRuns,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    final merged = syncMergeRow(existing?.toJson(), data);
    if (!syncHasRequired(merged, [
      'id',
      'userId',
      'presetId',
      'status',
      'startedAt',
      'targetWorkIntervals',
      'completedWorkIntervals',
      'createdAt',
      'updatedAt',
      'isDeleted',
    ])) {
      return;
    }
    await _db
        .into(_db.focusRuns)
        .insertOnConflictUpdate(FocusRunRow.fromJson(merged));
  }

  Future<void> _upsertGoogleCalendarConnection(
    String id,
    Map<String, dynamic> data,
  ) async {
    final existing = await (_db.select(
      _db.googleCalendarConnections,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    final merged = syncMergeRow(existing?.toJson(), data);
    if (!syncHasRequired(merged, [
      'id',
      'calendarName',
      'status',
      'createdAt',
      'updatedAt',
    ])) {
      return;
    }
    await _db
        .into(_db.googleCalendarConnections)
        .insertOnConflictUpdate(
          GoogleCalendarConnectionRow.fromJson(merged).toCompanion(false),
        );
  }

  Future<void> _upsertGoogleCalendarEventLink(
    String id,
    Map<String, dynamic> data,
  ) async {
    final existing = await (_db.select(
      _db.googleCalendarEventLinks,
    )..where((row) => row.taskId.equals(id))).getSingleOrNull();
    final merged = syncMergeRow(existing?.toJson(), data)
      ..putIfAbsent('taskId', () => id);
    if (!syncHasRequired(merged, [
      'taskId',
      'calendarId',
      'eventId',
      'createdAt',
      'updatedAt',
    ])) {
      return;
    }
    await _db
        .into(_db.googleCalendarEventLinks)
        .insertOnConflictUpdate(
          GoogleCalendarEventLinkRow.fromJson(merged).toCompanion(false),
        );
  }

  Future<void> _upsertKanbanSettings(
    String entityId,
    Map<String, dynamic> data,
    DateTime? entityUpdatedAt,
  ) async {
    const stableId = kanbanSettingsPrimaryId;
    final existing = await (_db.select(
      _db.kanbanSettings,
    )..where((row) => row.id.equals(stableId))).getSingleOrNull();
    final timestamp =
        syncDateTimeFromSyncValue(data['updatedAt']) ??
        entityUpdatedAt?.toUtc() ??
        DateTime.now().toUtc();
    final merged = syncMergeRow(existing?.toJson(), data)
      ..['id'] = stableId
      ..putIfAbsent('userId', () => localUserId)
      ..putIfAbsent(
        'selectedProjectIdsJson',
        () => jsonEncode([inboxProjectId]),
      )
      ..putIfAbsent('focusStatusLabelId', () => kanbanStatusInProgressId)
      ..putIfAbsent('createdAt', () => timestamp.toIso8601String())
      ..putIfAbsent('updatedAt', () => timestamp.toIso8601String());
    await _db
        .into(_db.kanbanSettings)
        .insertOnConflictUpdate(KanbanSettingsRow.fromJson(merged));
  }

  Future<void> _upsertLabel(String id, Map<String, dynamic> data) async {
    final existing = await (_db.select(
      _db.labels,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    final merged = syncMergeRow(existing?.toJson(), data)
      ..['kind'] ??= labelKindUser
      ..putIfAbsent('systemKey', () => null);
    if (!syncHasRequired(merged, [
      'id',
      'userId',
      'name',
      'orderKey',
      'isFavorite',
      'isDeleted',
      'createdAt',
      'updatedAt',
    ])) {
      return;
    }
    await _db
        .into(_db.labels)
        .insertOnConflictUpdate(LabelRow.fromJson(merged));
  }

  Future<void> _upsertProject(String id, Map<String, dynamic> data) async {
    final existing = await (_db.select(
      _db.projects,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    final merged = syncMergeRow(existing?.toJson(), data);
    if (!syncHasRequired(merged, [
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
    ])) {
      return;
    }
    await _db
        .into(_db.projects)
        .insertOnConflictUpdate(ProjectRow.fromJson(merged).toCompanion(false));
  }

  Future<void> _upsertReminder(String id, Map<String, dynamic> data) async {
    final existing = await (_db.select(
      _db.reminders,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    final merged = syncMergeRow(existing?.toJson(), data);
    if (!syncHasRequired(merged, [
      'id',
      'userId',
      'taskId',
      'type',
      'specJson',
      'isDeleted',
      'createdAt',
      'updatedAt',
    ])) {
      return;
    }
    await _db
        .into(_db.reminders)
        .insertOnConflictUpdate(ReminderRow.fromJson(merged));
  }

  Future<void> _upsertSection(String id, Map<String, dynamic> data) async {
    final existing = await (_db.select(
      _db.sections,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    final merged = syncMergeRow(existing?.toJson(), data);
    if (!syncHasRequired(merged, [
      'id',
      'projectId',
      'name',
      'orderKey',
      'isCollapsed',
      'isArchived',
      'isDeleted',
      'createdAt',
      'updatedAt',
    ])) {
      return;
    }
    await _db
        .into(_db.sections)
        .insertOnConflictUpdate(SectionRow.fromJson(merged));
  }

  Future<void> _upsertTask(String id, Map<String, dynamic> data) async {
    final existing = await (_db.select(
      _db.tasks,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    final incomingUpdatedAt = syncDateTimeFromSyncValue(data['updatedAt']);
    if (data['scopeId'] == null &&
        existing != null &&
        incomingUpdatedAt != null &&
        incomingUpdatedAt.isBefore(existing.updatedAt.toUtc())) {
      return;
    }
    final merged = syncMergeRow(existing?.toJson(), data);
    merged.putIfAbsent('assigneeIdsJson', () => '[]');
    merged['createdBy'] =
        data['createdBy'] ??
        existing?.createdBy ??
        _account.currentUserId ??
        localUserId;
    if (merged['scopeId'] == null && merged['createdBy'] == localUserId) {
      merged['createdBy'] = _account.currentUserId ?? localUserId;
    }
    final hasPendingDelete =
        await (_db.select(_db.syncCommands)..where(
              (row) =>
                  row.type.equals('task.delete') &
                  row.clientId.equals(id) &
                  row.status.equals('pending'),
            ))
            .getSingleOrNull() !=
        null;
    if (hasPendingDelete) {
      merged['isDeleted'] = true;
    }
    if (!syncHasRequired(merged, [
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
    ])) {
      return;
    }
    await _db
        .into(_db.tasks)
        .insertOnConflictUpdate(TaskRow.fromJson(merged).toCompanion(false));
  }

  Future<void> _upsertTaskCompletion(
    String id,
    Map<String, dynamic> data,
  ) async {
    final existing = await (_db.select(
      _db.taskCompletions,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    final merged = syncMergeRow(existing?.toJson(), data);
    if (!syncHasRequired(merged, [
      'id',
      'taskId',
      'userId',
      'completedAt',
      'createdAt',
    ])) {
      return;
    }
    await _db
        .into(_db.taskCompletions)
        .insertOnConflictUpdate(TaskCompletionRow.fromJson(merged));
  }

  Future<void> _upsertTaskKanbanStatus(
    String entityId,
    Map<String, dynamic> data,
    DateTime? entityUpdatedAt,
  ) async {
    final taskId = entityId.isNotEmpty
        ? entityId
        : data['taskId'] as String? ?? '';
    final labelId = data['labelId'] as String?;
    if (taskId.isEmpty || labelId == null || labelId.isEmpty) {
      return;
    }
    final changedAt =
        syncDateTimeFromSyncValue(data['changedAt']) ??
        entityUpdatedAt?.toUtc() ??
        DateTime.now().toUtc();
    await (_db.delete(_db.taskLabels)..where(
          (row) =>
              row.taskId.equals(taskId) &
              row.kind.equals(labelKindKanbanStatus),
        ))
        .go();
    await _db
        .into(_db.taskLabels)
        .insert(
          TaskLabelsCompanion.insert(
            taskId: taskId,
            labelId: labelId,
            kind: const Value(labelKindKanbanStatus),
            createdAt: changedAt,
          ),
        );
  }

  Future<void> _upsertTaskLabel(
    String entityId,
    Map<String, dynamic> data,
  ) async {
    final ids = syncTaskLabelIds(entityId, data);
    if (ids == null) {
      return;
    }
    final label = await (_db.select(
      _db.labels,
    )..where((row) => row.id.equals(ids.labelId))).getSingleOrNull();
    if (label?.kind == labelKindKanbanStatus) {
      return;
    }
    final existing =
        await (_db.select(_db.taskLabels)..where(
              (row) =>
                  row.taskId.equals(ids.taskId) &
                  row.labelId.equals(ids.labelId) &
                  row.kind.equals(labelKindUser),
            ))
            .getSingleOrNull();
    final merged = syncMergeRow(existing?.toJson(), data)
      ..putIfAbsent('taskId', () => ids.taskId)
      ..putIfAbsent('labelId', () => ids.labelId)
      ..['kind'] = labelKindUser;
    if (!syncHasRequired(merged, ['taskId', 'labelId', 'createdAt'])) {
      return;
    }
    await _db
        .into(_db.taskLabels)
        .insertOnConflictUpdate(TaskLabelRow.fromJson(merged));
  }

  Future<void> _upsertWorkspace(String id, Map<String, dynamic> data) async {
    final existing = await (_db.select(
      _db.workspaces,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    final merged = syncMergeRow(existing?.toJson(), data);
    if (!syncHasRequired(merged, [
      'id',
      'userId',
      'name',
      'createdAt',
      'updatedAt',
    ])) {
      return;
    }
    await _db
        .into(_db.workspaces)
        .insertOnConflictUpdate(WorkspaceRow.fromJson(merged));
  }
}
