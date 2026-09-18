part of 'account_sync_engine.dart';

extension AccountSyncOperations on AccountSyncEngine {
  Future<List<AccountSyncOperation>> _snapshotOperations() async {
    final operations = <AccountSyncOperation>[];
    final taskHistoryCutoff = await _taskHistoryCutoff();

    final sharedProjects = (await (_db.select(
      _db.projects,
    )..where((p) => p.scopeId.isNotNull())).get()).map((p) => p.id).toSet();
    final sharedTasks = (await (_db.select(
      _db.tasks,
    )..where((t) => t.scopeId.isNotNull())).get()).map((t) => t.id).toSet();
    final sharedEntityIds = (await _db.select(_db.sharedEntities).get())
        .map((e) => '${e.entityType}:${e.entityId}')
        .toSet();
    void add(
      String entityType,
      String entityId,
      Map<String, dynamic> data,
      DateTime updatedAt,
    ) {
      if (!entityType.startsWith('focus_') &&
          (data['scopeId'] != null ||
              sharedProjects.contains(data['projectId']) ||
              sharedTasks.contains(data['taskId']) ||
              sharedEntityIds.contains('$entityType:$entityId'))) {
        return;
      }
      operations.add(
        _operation(
          opId:
              'import:$entityType:$entityId:${updatedAt.toUtc().toIso8601String()}',
          entityType: entityType,
          entityId: entityId,
          operation: 'upsert',
          payload: data,
          clientUpdatedAt: updatedAt,
        ),
      );
    }

    for (final row in await _db.select(_db.workspaces).get()) {
      add('workspace', row.id, row.toJson(), row.updatedAt);
    }
    for (final row in await _db.select(_db.projects).get()) {
      add('project', row.id, row.toJson(), row.updatedAt);
    }
    for (final row in await _db.select(_db.sections).get()) {
      add('section', row.id, row.toJson(), row.updatedAt);
    }
    for (final row in await _db.select(_db.tasks).get()) {
      if (_taskRowPastHistoryCutoff(row, taskHistoryCutoff)) {
        continue;
      }
      add('task', row.id, row.toJson(), row.updatedAt);
    }
    for (final row in await _db.select(_db.taskCompletions).get()) {
      add('task_completion', row.id, row.toJson(), row.createdAt);
    }
    for (final row in await _db.select(_db.labels).get()) {
      add('label', row.id, row.toJson(), _snapshotClockForLabel(row));
    }
    for (final row in await _db.select(_db.taskLabels).get()) {
      if (row.kind == labelKindKanbanStatus) {
        add('task_kanban_status', row.taskId, {
          'taskId': row.taskId,
          'labelId': row.labelId,
          'changedAt': row.createdAt.toUtc().toIso8601String(),
        }, row.createdAt);
      } else {
        add(
          'task_label',
          syncTaskLabelEntityId(row.taskId, row.labelId),
          row.toJson(),
          row.createdAt,
        );
      }
    }
    for (final row in await _db.select(_db.kanbanSettings).get()) {
      add(
        'kanban_settings',
        row.id,
        row.toJson(),
        _snapshotClockForSettings(row),
      );
    }
    for (final row in await _db.select(_db.filters).get()) {
      add('filter', row.id, row.toJson(), row.updatedAt);
    }
    for (final row in await _db.select(_db.reminders).get()) {
      add('reminder', row.id, row.toJson(), row.updatedAt);
    }
    for (final row in await _db.select(_db.focusPresets).get()) {
      add('focus_preset', row.id, row.toJson(), row.updatedAt);
    }
    for (final row in await _db.select(_db.googleCalendarConnections).get()) {
      add('google_calendar_connection', row.id, row.toJson(), row.updatedAt);
    }
    for (final row in await _db.select(_db.googleCalendarEventLinks).get()) {
      add(
        'google_calendar_event_link',
        row.taskId,
        row.toJson(),
        row.updatedAt,
      );
    }

    final completedRuns =
        await (_db.select(_db.focusRuns)..where(
              (row) =>
                  row.endedAt.isNotNull() |
                  row.status.equals('completed') |
                  row.status.equals('stopped') |
                  row.status.equals('interrupted'),
            ))
            .get();
    final completedRunIds = completedRuns.map((row) => row.id).toList();
    for (final row in completedRuns) {
      add('focus_run', row.id, row.toJson(), row.updatedAt);
    }
    if (completedRunIds.isNotEmpty) {
      final intervals = await (_db.select(
        _db.focusIntervals,
      )..where((row) => row.runId.isIn(completedRunIds))).get();
      for (final row in intervals) {
        add('focus_interval', row.id, row.toJson(), row.updatedAt);
      }

      final events = await (_db.select(
        _db.focusEvents,
      )..where((row) => row.runId.isIn(completedRunIds))).get();
      for (final row in events) {
        add('focus_event', row.id, row.toJson(), row.createdAt);
      }
    }

    return operations;
  }

  Future<List<AccountSyncOperation>> _operationsFromCommand(
    SyncCommandRow command,
    DateTime? taskHistoryCutoff,
  ) async {
    final payload = jsonDecode(command.payloadJson);
    final payloadMap = payload is Map
        ? Map<String, Object?>.from(payload)
        : <String, Object?>{};
    final commandType = command.type;
    final focusLifecycleCommand =
        commandType.startsWith('focus.run.') ||
        commandType.startsWith('focus.interval.') ||
        commandType == 'focus.distraction.log';
    if (focusLifecycleCommand) {
      if (commandType == 'focus.run.complete' ||
          commandType == 'focus.run.stop') {
        return _terminalFocusOperations(command, payloadMap);
      }
      return const <AccountSyncOperation>[];
    }
    final entityType = syncEntityTypeForCommand(commandType);
    var entityId = syncEntityIdForCommand(
      (id: command.id, clientId: command.clientId, uuid: command.uuid),
      payloadMap,
      entityType,
    );
    final operation =
        commandType.endsWith('.delete') || payloadMap['isDeleted'] == true
        ? 'delete'
        : 'upsert';

    final operations = <AccountSyncOperation>[];
    var rowPayload = operation == 'delete'
        ? payloadMap
        : (syncUsesCapturedPatch(commandType) || command.scopeId != null)
        ? syncCapturedPatchPayload(commandType, payloadMap, command.updatedAt)
        : await _rowPayload(entityType, entityId, payloadMap);
    if (entityType == 'focus_event' && !rowPayload.containsKey('id')) {
      final event = await _latestFocusEvent(
        runId: payloadMap['runId'] as String? ?? command.clientId,
        type: 'distractionLogged',
      );
      if (event != null) {
        entityId = event.id;
        rowPayload = event.toJson();
      }
    }

    final skipTaskEntity =
        entityType == 'task' &&
        await _taskCommandPastHistoryCutoff(entityId, taskHistoryCutoff);
    if (!skipTaskEntity) {
      operations.add(
        _operation(
          opId: command.uuid,
          entityType: entityType,
          entityId: entityId,
          operation: operation,
          payload: {'commandType': commandType, ...rowPayload},
          clientUpdatedAt: command.updatedAt,
        ),
      );
    }

    if (commandType == 'task.complete') {
      final capturedCompletionId = payloadMap['completionId'] as String?;
      final completion =
          await (_db.select(_db.taskCompletions)
                ..where(
                  (row) => capturedCompletionId == null
                      ? row.taskId.equals(entityId)
                      : row.id.equals(capturedCompletionId),
                )
                ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
                ..limit(1))
              .getSingleOrNull();
      if (completion != null) {
        operations.add(
          _operation(
            opId: '${command.uuid}:completion:${completion.id}',
            entityType: 'task_completion',
            entityId: completion.id,
            operation: 'upsert',
            payload: completion.toJson(),
            clientUpdatedAt: completion.createdAt,
          ),
        );
      }
    }

    if (entityType == 'focus_interval') {
      final interval = await (_db.select(
        _db.focusIntervals,
      )..where((row) => row.id.equals(entityId))).getSingleOrNull();
      if (interval != null) {
        final run = await (_db.select(
          _db.focusRuns,
        )..where((row) => row.id.equals(interval.runId))).getSingleOrNull();
        if (run != null && run.endedAt != null) {
          operations.add(
            _operation(
              opId: '${command.uuid}:run:${run.id}',
              entityType: 'focus_run',
              entityId: run.id,
              operation: 'upsert',
              payload: run.toJson(),
              clientUpdatedAt: run.updatedAt,
            ),
          );
        }
      }
    }

    return operations;
  }

  Future<List<AccountSyncOperation>> _terminalFocusOperations(
    SyncCommandRow command,
    Map<String, Object?> payload,
  ) async {
    final runId = payload['id'] as String? ?? command.clientId;
    if (runId == null) {
      return const <AccountSyncOperation>[];
    }
    final run = await (_db.select(
      _db.focusRuns,
    )..where((row) => row.id.equals(runId))).getSingleOrNull();
    if (run == null || !_isTerminalFocusRun(run)) {
      return const <AccountSyncOperation>[];
    }
    final intervals =
        await (_db.select(_db.focusIntervals)
              ..where((row) => row.runId.equals(run.id))
              ..orderBy([(row) => OrderingTerm.asc(row.sequenceNumber)]))
            .get();
    final events =
        await (_db.select(_db.focusEvents)
              ..where((row) => row.runId.equals(run.id))
              ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
            .get();
    final commandMetadata = <String, Object?>{'commandType': command.type};

    return [
      _operation(
        opId: '${command.uuid}:run:${run.id}',
        entityType: 'focus_run',
        entityId: run.id,
        operation: 'upsert',
        payload: {...commandMetadata, ...run.toJson()},
        clientUpdatedAt: run.updatedAt,
      ),
      for (final interval in intervals)
        _operation(
          opId: '${command.uuid}:interval:${interval.id}',
          entityType: 'focus_interval',
          entityId: interval.id,
          operation: 'upsert',
          payload: {...commandMetadata, ...interval.toJson()},
          clientUpdatedAt: interval.updatedAt,
        ),
      for (final event in events)
        _operation(
          opId: '${command.uuid}:event:${event.id}',
          entityType: 'focus_event',
          entityId: event.id,
          operation: 'upsert',
          payload: {...commandMetadata, ...event.toJson()},
          clientUpdatedAt: event.createdAt,
        ),
    ];
  }

  bool _isTerminalFocusRun(FocusRunRow run) {
    return run.endedAt != null ||
        run.status == 'completed' ||
        run.status == 'stopped' ||
        run.status == 'interrupted';
  }

  Future<DateTime?> _taskHistoryCutoff() async {
    try {
      if (await (_localPaidEntitlementLoader?.call() ?? Future.value(false))) {
        return null;
      }
      final overview =
          await (_overviewLoader == null
                  ? _account.getOverview()
                  : _overviewLoader())
              .timeout(_requestTimeout);
      final policy =
          await (_db.select(_db.sharedEntities)..where(
                (row) =>
                    row.scopeId.equals('_account') &
                    row.entityType.equals('history') &
                    row.entityId.equals('personal'),
              ))
              .getSingleOrNull();
      final data = policy == null
          ? <String, dynamic>{}
          : jsonDecode(policy.dataJson) as Map<String, dynamic>;
      return pomodoistTaskHistoryCutoff(
        overview,
        historyUnlimited: data['historyUnlimited'] == true,
        graceEndsAt: DateTime.tryParse(data['graceEndsAt']?.toString() ?? ''),
      );
    } catch (_) {
      // ponytail: server cleanup still enforces free retention; keep local data
      // syncing if entitlement lookup is temporarily unavailable.
      return null;
    }
  }

  Future<bool> _taskCommandPastHistoryCutoff(
    String taskId,
    DateTime? cutoff,
  ) async {
    if (cutoff == null) {
      return false;
    }
    final row = await (_db.select(
      _db.tasks,
    )..where((task) => task.id.equals(taskId))).getSingleOrNull();
    return row != null && _taskRowPastHistoryCutoff(row, cutoff);
  }

  bool _taskRowPastHistoryCutoff(TaskRow row, DateTime? cutoff) {
    if (cutoff == null) {
      return false;
    }
    if (row.isDeleted) {
      return row.updatedAt.toUtc().isBefore(cutoff);
    }
    if (row.status != 'completed') {
      return false;
    }
    return (row.completedAt ?? row.updatedAt).toUtc().isBefore(cutoff);
  }

  AccountSyncOperation _operation({
    required String opId,
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
    required DateTime clientUpdatedAt,
  }) {
    final syncPayload = Map<String, Object?>.from(payload);
    if (operation == 'delete') {
      return AccountSyncOperation.deleteV1(
        opId: opId,
        entityType: entityType,
        entityId: entityId,
        payload: syncPayload,
        clientUpdatedAt: clientUpdatedAt,
      );
    }
    return AccountSyncOperation.upsertV1(
      opId: opId,
      entityType: entityType,
      entityId: entityId,
      payload: syncPayload,
      clientUpdatedAt: clientUpdatedAt,
    );
  }

  Future<Map<String, Object?>> _rowPayload(
    String entityType,
    String entityId,
    Map<String, Object?> fallback,
  ) async {
    switch (entityType) {
      case 'workspace':
        final row = await (_db.select(
          _db.workspaces,
        )..where((row) => row.id.equals(entityId))).getSingleOrNull();
        return row?.toJson() ?? fallback;
      case 'project':
        final row = await (_db.select(
          _db.projects,
        )..where((row) => row.id.equals(entityId))).getSingleOrNull();
        return row?.toJson() ?? fallback;
      case 'section':
        final row = await (_db.select(
          _db.sections,
        )..where((row) => row.id.equals(entityId))).getSingleOrNull();
        return row?.toJson() ?? fallback;
      case 'task':
        final row = await (_db.select(
          _db.tasks,
        )..where((row) => row.id.equals(entityId))).getSingleOrNull();
        return row?.toJson() ?? fallback;
      case 'task_label':
        final taskId = fallback['taskId'] as String?;
        final labelId = fallback['labelId'] as String?;
        if (taskId == null || labelId == null) {
          return fallback;
        }
        final row =
            await (_db.select(_db.taskLabels)..where(
                  (row) =>
                      row.taskId.equals(taskId) &
                      row.labelId.equals(labelId) &
                      row.kind.equals(labelKindUser),
                ))
                .getSingleOrNull();
        return row?.toJson() ?? fallback;
      case 'task_kanban_status':
        final row =
            await (_db.select(_db.taskLabels)..where(
                  (row) =>
                      row.taskId.equals(entityId) &
                      row.kind.equals(labelKindKanbanStatus),
                ))
                .getSingleOrNull();
        return row == null
            ? fallback
            : {
                'taskId': row.taskId,
                'labelId': row.labelId,
                'changedAt': row.createdAt.toUtc().toIso8601String(),
              };
      case 'kanban_settings':
        final row = await (_db.select(
          _db.kanbanSettings,
        )..where((row) => row.id.equals(entityId))).getSingleOrNull();
        return row?.toJson() ?? fallback;
      case 'label':
        final row = await (_db.select(
          _db.labels,
        )..where((row) => row.id.equals(entityId))).getSingleOrNull();
        return row?.toJson() ?? fallback;
      case 'filter':
        final row = await (_db.select(
          _db.filters,
        )..where((row) => row.id.equals(entityId))).getSingleOrNull();
        return row?.toJson() ?? fallback;
      case 'reminder':
        final row = await (_db.select(
          _db.reminders,
        )..where((row) => row.id.equals(entityId))).getSingleOrNull();
        return row?.toJson() ?? fallback;
      case 'focus_preset':
        final row = await (_db.select(
          _db.focusPresets,
        )..where((row) => row.id.equals(entityId))).getSingleOrNull();
        return row?.toJson() ?? fallback;
      case 'focus_run':
        final row = await (_db.select(
          _db.focusRuns,
        )..where((row) => row.id.equals(entityId))).getSingleOrNull();
        return row?.toJson() ?? fallback;
      case 'focus_interval':
        final row = await (_db.select(
          _db.focusIntervals,
        )..where((row) => row.id.equals(entityId))).getSingleOrNull();
        return row?.toJson() ?? fallback;
      case 'focus_event':
        final row = await (_db.select(
          _db.focusEvents,
        )..where((row) => row.id.equals(entityId))).getSingleOrNull();
        return row?.toJson() ?? fallback;
      case 'google_calendar_connection':
        final row = await (_db.select(
          _db.googleCalendarConnections,
        )..where((row) => row.id.equals(entityId))).getSingleOrNull();
        return row?.toJson() ?? fallback;
      case 'google_calendar_event_link':
        final row = await (_db.select(
          _db.googleCalendarEventLinks,
        )..where((row) => row.taskId.equals(entityId))).getSingleOrNull();
        return row?.toJson() ?? fallback;
      default:
        return fallback;
    }
  }

  Future<FocusEventRow?> _latestFocusEvent({
    required String? runId,
    required String type,
  }) {
    if (runId == null || runId.isEmpty) {
      return Future.value();
    }
    return (_db.select(_db.focusEvents)
          ..where((row) => row.runId.equals(runId) & row.type.equals(type))
          ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
          ..limit(1))
        .getSingleOrNull();
  }
}
