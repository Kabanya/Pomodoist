import 'dart:convert';

import 'package:app_account/app_account.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import '../../features/tasks/data/kanban_transition_coordinator.dart';
import 'pomodoist_retention.dart';
import 'sync_queue_repository.dart';

class AccountSyncEngine {
  AccountSyncEngine({
    required AppDatabase db,
    required AccountClient account,
    required Uuid uuid,
    Future<AccountOverview?> Function()? overviewLoader,
    Future<bool> Function()? localPaidEntitlementLoader,
    KanbanTransitionCoordinator? kanbanTransitions,
    Duration requestTimeout = const Duration(seconds: 30),
  }) : _db = db,
       _account = account,
       _uuid = uuid,
       _overviewLoader = overviewLoader,
       _localPaidEntitlementLoader = localPaidEntitlementLoader,
       _requestTimeout = requestTimeout,
       _kanbanTransitions =
           kanbanTransitions ??
           KanbanTransitionCoordinator(db, DriftSyncQueueRepository(db));

  static const _syncStateId = 'pomodoist';
  static const _importStateId = 'pomodoist-import';
  static const _accountOwnerStateId = 'pomodoist-account-owner-v1';
  static const _importStateCursor = 'done-v3';
  static const _guestOwnerCursor = 'guest';
  static final _seedSnapshotClock = DateTime.utc(2000);
  static final _ownerTransitionQueues = Expando<_OwnerTransitionQueue>(
    'account-owner-transition',
  );

  final AppDatabase _db;
  final AccountClient _account;
  final Uuid _uuid;
  final Future<AccountOverview?> Function()? _overviewLoader;
  final Future<bool> Function()? _localPaidEntitlementLoader;
  final Duration _requestTimeout;
  final KanbanTransitionCoordinator _kanbanTransitions;

  Future<String> deviceId() => _ensureDeviceId();

  Future<Set<String>> syncNow() async {
    await prepareLocalAccountData();
    final imported = await importLocalSnapshotIfNeeded();
    if (imported) {
      await _broadcastSyncHint();
    }
    return <String>{...await pushPending(), ...await pullLatest()};
  }

  static Future<bool> prepareGuestLocalData({
    required AppDatabase db,
    required Uuid uuid,
    bool Function()? shouldPrepare,
  }) {
    return _ownerTransitionQueueFor(db).run(() async {
      if (shouldPrepare != null && !shouldPrepare()) {
        return false;
      }
      final owner = await (db.select(
        db.syncState,
      )..where((row) => row.id.equals(_accountOwnerStateId))).getSingleOrNull();
      if (owner?.cursor == _guestOwnerCursor) {
        return false;
      }
      final reset = owner != null;
      if (reset) {
        await db.resetAccountData();
      }
      final now = DateTime.now().toUtc();
      await db
          .into(db.syncState)
          .insertOnConflictUpdate(
            SyncStateCompanion.insert(
              id: _accountOwnerStateId,
              deviceId: uuid.v4(),
              cursor: const Value(_guestOwnerCursor),
              createdAt: now,
              updatedAt: now,
            ),
          );
      return reset;
    });
  }

  Future<bool> prepareLocalAccountData() {
    return _ownerTransitionQueueFor(_db).run(() async {
      final userId = _account.currentUserId;
      if (userId == null || userId.isEmpty) {
        throw StateError('Account sync requires an authenticated user.');
      }
      final owner = await (_db.select(
        _db.syncState,
      )..where((row) => row.id.equals(_accountOwnerStateId))).getSingleOrNull();
      if (owner?.cursor == userId) {
        return false;
      }
      final importState = await (_db.select(
        _db.syncState,
      )..where((row) => row.id.equals(_importStateId))).getSingleOrNull();
      final syncState = await _syncState();
      final reset = owner != null || importState != null || syncState != null;
      if (reset) {
        await _db.resetAccountData();
      }
      final now = DateTime.now().toUtc();
      await _db
          .into(_db.syncState)
          .insertOnConflictUpdate(
            SyncStateCompanion.insert(
              id: _accountOwnerStateId,
              deviceId: _uuid.v4(),
              cursor: Value(userId),
              createdAt: now,
              updatedAt: now,
            ),
          );
      return reset;
    });
  }

  static _OwnerTransitionQueue _ownerTransitionQueueFor(AppDatabase db) {
    final existing = _ownerTransitionQueues[db];
    if (existing != null) {
      return existing;
    }
    final created = _OwnerTransitionQueue();
    _ownerTransitionQueues[db] = created;
    return created;
  }

  Future<bool> importLocalSnapshotIfNeeded() async {
    final state = await (_db.select(
      _db.syncState,
    )..where((row) => row.id.equals(_importStateId))).getSingleOrNull();
    if (state?.cursor == _importStateCursor) {
      return false;
    }

    final deviceId = await _ensureDeviceId();
    final operations = await _snapshotOperations();
    await _pushInBatches(deviceId, operations);

    final now = DateTime.now().toUtc();
    await _db
        .into(_db.syncState)
        .insertOnConflictUpdate(
          SyncStateCompanion.insert(
            id: _importStateId,
            deviceId: deviceId,
            cursor: const Value(_importStateCursor),
            lastPushedAt: Value(now),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return operations.isNotEmpty;
  }

  Future<Set<String>> pushPending() async {
    await _deleteFinishedCommands();
    final deviceId = await _ensureDeviceId();
    final taskHistoryCutoff = await _taskHistoryCutoff();
    final readyAt = DateTime.now().toUtc();
    final deferredTaskIds =
        (await (_db.select(_db.syncCommands)..where(
                  (row) =>
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
      'task.update',
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

  Future<Set<String>> pullLatest() async {
    final deviceId = await _ensureDeviceId();
    final state = await _syncState();
    var sinceRevision = int.tryParse(state?.cursor ?? '') ?? 0;
    final entityTypes = <String>{};
    while (true) {
      final result = await _account
          .pullChanges(
            appId: AccountAppId.pomodoist,
            deviceId: deviceId,
            sinceRevision: sinceRevision,
          )
          .timeout(_requestTimeout);
      entityTypes.addAll(result.changes.map((change) => change.entityType));
      if (result.nextCursor < sinceRevision) {
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
      await _saveCursor(result.nextCursor);
      if (!result.hasMore || result.nextCursor <= sinceRevision) {
        await _repairKanbanAfterFinalPull();
        return entityTypes;
      }
      sinceRevision = result.nextCursor;
    }
  }

  Future<List<AccountSyncOperation>> _snapshotOperations() async {
    final operations = <AccountSyncOperation>[];
    final taskHistoryCutoff = await _taskHistoryCutoff();

    void add(
      String entityType,
      String entityId,
      Map<String, dynamic> data,
      DateTime updatedAt,
    ) {
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
          _taskLabelEntityId(row.taskId, row.labelId),
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
    final entityType = _entityTypeForCommand(commandType);
    var entityId = _entityIdForCommand(command, payloadMap, entityType);
    final operation =
        commandType.endsWith('.delete') || payloadMap['isDeleted'] == true
        ? 'delete'
        : 'upsert';

    final operations = <AccountSyncOperation>[];
    var rowPayload = operation == 'delete'
        ? payloadMap
        : _usesCapturedPatch(commandType)
        ? payloadMap
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
      return pomodoistTaskHistoryCutoff(overview);
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

  Future<void> _pushInBatches(
    String deviceId,
    List<AccountSyncOperation> operations,
  ) async {
    const batchSize = 100;
    for (var index = 0; index < operations.length; index += batchSize) {
      final end = index + batchSize > operations.length
          ? operations.length
          : index + batchSize;
      await _account
          .pushChanges(
            appId: AccountAppId.pomodoist,
            deviceId: deviceId,
            operations: operations.sublist(index, end),
          )
          .timeout(_requestTimeout);
    }
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

  Future<void> _applyPullResult(AccountSyncPullResult result) async {
    if (result.changes.isEmpty) {
      return;
    }

    await _db.transaction(() async {
      for (final change in result.changes) {
        if (change.deleted) {
          await _applyDelete(change);
        } else {
          await _applyUpsert(change);
        }
      }
    });
  }

  Future<void> _repairKanbanAfterFinalPull() async {
    final timestamp = DateTime.now().toUtc();
    await _db.transaction(() async {
      await _kanbanTransitions.repairAfterRemotePullInTransaction(
        timestamp: timestamp,
      );
    });
  }

  Future<void> _applyUpsert(AccountSyncEntity entity) async {
    final data = _dataWithoutSyncMetadata(entity.data);
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

  bool _isActiveFocusRunData(Map<String, dynamic> data) {
    final status = data['status'];
    return status == 'active' || status == 'paused';
  }

  bool _isActiveFocusIntervalData(Map<String, dynamic> data) {
    final status = data['status'];
    return status == 'running' || status == 'paused' || status == 'ready';
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
        final ids = _taskLabelIdsFromEntity(entity);
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
        await (_db.update(
          _db.googleCalendarConnections,
        )..where((row) => row.id.equals(entity.entityId))).write(
          GoogleCalendarConnectionsCompanion(
            status: const Value('disconnected'),
            updatedAt: Value(now),
          ),
        );
        return;
      case 'google_calendar_event_link':
        await (_db.delete(
          _db.googleCalendarEventLinks,
        )..where((row) => row.taskId.equals(entity.entityId))).go();
        return;
    }
  }

  Future<void> _upsertWorkspace(String id, Map<String, dynamic> data) async {
    final existing = await (_db.select(
      _db.workspaces,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    final merged = _mergeRow(existing?.toJson(), data);
    if (!_hasRequired(merged, [
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

  Future<void> _upsertProject(String id, Map<String, dynamic> data) async {
    final existing = await (_db.select(
      _db.projects,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    final merged = _mergeRow(existing?.toJson(), data);
    if (!_hasRequired(merged, [
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
        .insertOnConflictUpdate(ProjectRow.fromJson(merged));
  }

  Future<void> _upsertSection(String id, Map<String, dynamic> data) async {
    final existing = await (_db.select(
      _db.sections,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    final merged = _mergeRow(existing?.toJson(), data);
    if (!_hasRequired(merged, [
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
    final merged = _mergeRow(existing?.toJson(), data);
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
    if (!_hasRequired(merged, [
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
    await _db.into(_db.tasks).insertOnConflictUpdate(TaskRow.fromJson(merged));
  }

  Future<void> _upsertTaskCompletion(
    String id,
    Map<String, dynamic> data,
  ) async {
    final existing = await (_db.select(
      _db.taskCompletions,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    final merged = _mergeRow(existing?.toJson(), data);
    if (!_hasRequired(merged, [
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

  Future<void> _upsertLabel(String id, Map<String, dynamic> data) async {
    final existing = await (_db.select(
      _db.labels,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    final merged = _mergeRow(existing?.toJson(), data)
      ..['kind'] ??= labelKindUser
      ..putIfAbsent('systemKey', () => null);
    if (!_hasRequired(merged, [
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

  Future<void> _upsertTaskLabel(
    String entityId,
    Map<String, dynamic> data,
  ) async {
    final ids = _taskLabelIds(entityId, data);
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
    final merged = _mergeRow(existing?.toJson(), data)
      ..putIfAbsent('taskId', () => ids.taskId)
      ..putIfAbsent('labelId', () => ids.labelId)
      ..['kind'] = labelKindUser;
    if (!_hasRequired(merged, ['taskId', 'labelId', 'createdAt'])) {
      return;
    }
    await _db
        .into(_db.taskLabels)
        .insertOnConflictUpdate(TaskLabelRow.fromJson(merged));
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
        _dateTimeFromSyncValue(data['changedAt']) ??
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
        _dateTimeFromSyncValue(data['updatedAt']) ??
        entityUpdatedAt?.toUtc() ??
        DateTime.now().toUtc();
    final merged = _mergeRow(existing?.toJson(), data)
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

  Future<void> _upsertFilter(String id, Map<String, dynamic> data) async {
    final existing = await (_db.select(
      _db.filters,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    final merged = _mergeRow(existing?.toJson(), data);
    if (!_hasRequired(merged, [
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

  Future<void> _upsertReminder(String id, Map<String, dynamic> data) async {
    final existing = await (_db.select(
      _db.reminders,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    final merged = _mergeRow(existing?.toJson(), data);
    if (!_hasRequired(merged, [
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

  Future<void> _upsertFocusPreset(String id, Map<String, dynamic> data) async {
    final existing = await (_db.select(
      _db.focusPresets,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    final merged = _mergeRow(existing?.toJson(), data);
    if (!_hasRequired(merged, [
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
    final merged = _mergeRow(existing?.toJson(), data);
    if (!_hasRequired(merged, [
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

  Future<void> _upsertFocusInterval(
    String id,
    Map<String, dynamic> data,
  ) async {
    final existing = await (_db.select(
      _db.focusIntervals,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    final merged = _mergeRow(existing?.toJson(), data);
    if (!_hasRequired(merged, [
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

  Future<void> _upsertFocusEvent(String id, Map<String, dynamic> data) async {
    final existing = await (_db.select(
      _db.focusEvents,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    final merged = _mergeRow(existing?.toJson(), data);
    if (!_hasRequired(merged, [
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

  Future<void> _upsertGoogleCalendarConnection(
    String id,
    Map<String, dynamic> data,
  ) async {
    final existing = await (_db.select(
      _db.googleCalendarConnections,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    final merged = _mergeRow(existing?.toJson(), data);
    if (!_hasRequired(merged, [
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
        .insertOnConflictUpdate(GoogleCalendarConnectionRow.fromJson(merged));
  }

  Future<void> _upsertGoogleCalendarEventLink(
    String id,
    Map<String, dynamic> data,
  ) async {
    final existing = await (_db.select(
      _db.googleCalendarEventLinks,
    )..where((row) => row.taskId.equals(id))).getSingleOrNull();
    final merged = _mergeRow(existing?.toJson(), data)
      ..putIfAbsent('taskId', () => id);
    if (!_hasRequired(merged, [
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
        .insertOnConflictUpdate(GoogleCalendarEventLinkRow.fromJson(merged));
  }

  Map<String, dynamic> _dataWithoutSyncMetadata(JsonMap data) {
    return Map<String, dynamic>.from(data)
      ..remove('schemaVersion')
      ..remove('commandType');
  }

  Map<String, dynamic> _mergeRow(
    Map<String, dynamic>? existing,
    Map<String, dynamic> incoming,
  ) {
    return <String, dynamic>{...?existing, ...incoming};
  }

  DateTime? _dateTimeFromSyncValue(Object? value) {
    return switch (value) {
      final DateTime dateTime => dateTime.toUtc(),
      final int milliseconds => DateTime.fromMillisecondsSinceEpoch(
        milliseconds,
        isUtc: true,
      ),
      final num milliseconds => DateTime.fromMillisecondsSinceEpoch(
        milliseconds.toInt(),
        isUtc: true,
      ),
      final String text => DateTime.tryParse(text)?.toUtc(),
      _ => null,
    };
  }

  bool _hasRequired(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      if (!data.containsKey(key) || data[key] == null) {
        return false;
      }
    }
    return true;
  }

  String _entityTypeForCommand(String commandType) {
    if (commandType == 'task.kanbanStatus.set') {
      return 'task_kanban_status';
    }
    if (commandType.startsWith('kanban.settings.')) {
      return 'kanban_settings';
    }
    if (commandType.startsWith('kanban.status.')) {
      return 'label';
    }
    if (commandType == 'google_calendar.connection.upsert' ||
        commandType == 'google_calendar.connection.delete') {
      return 'google_calendar_connection';
    }
    if (commandType == 'google_calendar.link.upsert' ||
        commandType == 'google_calendar.link.delete') {
      return 'google_calendar_event_link';
    }
    if (commandType == 'task.label.add' || commandType == 'task.label.delete') {
      return 'task_label';
    }
    if (commandType.startsWith('focus.run.')) {
      return 'focus_run';
    }
    if (commandType.startsWith('focus.interval.')) {
      return 'focus_interval';
    }
    if (commandType.startsWith('focus.preset.')) {
      return 'focus_preset';
    }
    if (commandType == 'focus.distraction.log') {
      return 'focus_event';
    }
    return switch (commandType.split('.').first) {
      'project' => 'project',
      'section' => 'section',
      'task' => 'task',
      'label' => 'label',
      'filter' => 'filter',
      'reminder' => 'reminder',
      _ => commandType.split('.').first,
    };
  }

  String _entityIdForCommand(
    SyncCommandRow command,
    Map<String, Object?> payload,
    String entityType,
  ) {
    if (entityType == 'task_kanban_status') {
      return payload['taskId'] as String? ?? command.clientId ?? command.id;
    }
    if (entityType == 'kanban_settings') {
      return payload['id'] as String? ?? kanbanSettingsPrimaryId;
    }
    if (entityType == 'task_label') {
      final taskId = payload['taskId'] as String? ?? command.clientId ?? '';
      final labelId = payload['labelId'] as String? ?? '';
      return _taskLabelEntityId(taskId, labelId);
    }
    if (entityType == 'focus_event') {
      return (payload['id'] as String?) ?? command.uuid;
    }
    if (entityType == 'google_calendar_connection') {
      return (payload['id'] as String?) ?? 'primary';
    }
    if (entityType == 'google_calendar_event_link') {
      return (payload['taskId'] as String?) ?? command.clientId ?? command.id;
    }
    return (payload['id'] as String?) ??
        (payload['runId'] as String?) ??
        command.clientId ??
        command.id;
  }

  _TaskLabelIds? _taskLabelIdsFromEntity(AccountSyncEntity entity) {
    return _taskLabelIds(
      entity.entityId,
      _dataWithoutSyncMetadata(entity.data),
    );
  }

  _TaskLabelIds? _taskLabelIds(String entityId, Map<String, dynamic> data) {
    final taskId = data['taskId'] as String?;
    final labelId = data['labelId'] as String?;
    if (taskId != null && labelId != null) {
      return _TaskLabelIds(taskId, labelId);
    }
    final separator = entityId.indexOf(':');
    if (separator <= 0 || separator == entityId.length - 1) {
      return null;
    }
    return _TaskLabelIds(
      entityId.substring(0, separator),
      entityId.substring(separator + 1),
    );
  }

  String _taskLabelEntityId(String taskId, String labelId) =>
      '$taskId:$labelId';

  bool _usesCapturedPatch(String commandType) {
    return commandType == 'task.kanbanStatus.set' ||
        commandType == 'task.reorder' ||
        commandType == 'kanban.status.rename' ||
        commandType == 'kanban.status.reorder' ||
        commandType.startsWith('kanban.settings.');
  }

  DateTime _snapshotClockForLabel(LabelRow row) {
    const seeds = <String, ({String name, String systemKey, String orderKey})>{
      kanbanStatusBacklogId: (
        name: 'Backlog',
        systemKey: kanbanSystemKeyBacklog,
        orderKey: '00000000000000000000',
      ),
      kanbanStatusTodoId: (
        name: 'To do',
        systemKey: kanbanSystemKeyTodo,
        orderKey: '00000000000000001000',
      ),
      kanbanStatusInProgressId: (
        name: 'In progress',
        systemKey: kanbanSystemKeyInProgress,
        orderKey: '00000000000000002000',
      ),
      kanbanStatusDoneId: (
        name: 'Done',
        systemKey: kanbanSystemKeyDone,
        orderKey: '00004503599627370496',
      ),
    };
    final seed = seeds[row.id];
    final untouched =
        seed != null &&
        row.updatedAt == row.createdAt &&
        row.userId == localUserId &&
        row.name == seed.name &&
        row.color == null &&
        row.kind == labelKindKanbanStatus &&
        row.systemKey == seed.systemKey &&
        row.orderKey == seed.orderKey &&
        !row.isFavorite &&
        !row.isDeleted;
    if (untouched) {
      return _seedSnapshotClock;
    }
    return row.updatedAt;
  }

  DateTime _snapshotClockForSettings(KanbanSettingsRow row) {
    final untouched =
        row.updatedAt == row.createdAt &&
        row.userId == localUserId &&
        row.selectedProjectIdsJson == jsonEncode([inboxProjectId]) &&
        row.focusStatusLabelId == kanbanStatusInProgressId;
    return untouched ? _seedSnapshotClock : row.updatedAt;
  }

  Future<SyncStateRow?> _syncState() {
    return (_db.select(
      _db.syncState,
    )..where((row) => row.id.equals(_syncStateId))).getSingleOrNull();
  }

  Future<String> _ensureDeviceId() async {
    final state = await _syncState();
    if (state != null) {
      return state.deviceId;
    }
    final now = DateTime.now().toUtc();
    final deviceId = _uuid.v4();
    await _db
        .into(_db.syncState)
        .insert(
          SyncStateCompanion.insert(
            id: _syncStateId,
            deviceId: deviceId,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return deviceId;
  }

  Future<void> _saveCursor(int cursor) async {
    final now = DateTime.now().toUtc();
    final state = await _syncState();
    if (state == null) {
      await _db
          .into(_db.syncState)
          .insert(
            SyncStateCompanion.insert(
              id: _syncStateId,
              deviceId: _uuid.v4(),
              cursor: Value('$cursor'),
              lastPulledAt: Value(now),
              createdAt: now,
              updatedAt: now,
            ),
          );
      return;
    }
    await (_db.update(
      _db.syncState,
    )..where((row) => row.id.equals(_syncStateId))).write(
      SyncStateCompanion(
        cursor: Value('$cursor'),
        lastPulledAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> _resetImportState() async {
    await (_db.delete(
      _db.syncState,
    )..where((row) => row.id.equals(_importStateId))).go();
  }

  Future<void> _broadcastSyncHint() async {
    try {
      await _account
          .broadcastSyncHint(
            appId: AccountAppId.pomodoist,
            deviceId: await _ensureDeviceId(),
          )
          .timeout(_requestTimeout);
    } on Object {
      // Realtime hints only accelerate the next pull; persisted sync succeeded.
    }
  }
}

class _OwnerTransitionQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

class _TaskLabelIds {
  const _TaskLabelIds(this.taskId, this.labelId);

  final String taskId;
  final String labelId;
}
