import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/sync/sync_queue_repository.dart';

const _backlogOrderKey = '00000000000000000000';
const _doneOrderKey = '00004503599627370496';

class KanbanTransitionCoordinator {
  KanbanTransitionCoordinator(this._db, this._syncQueue, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final SyncQueueRepository _syncQueue;
  final Uuid _uuid;

  Future<String> assignInitialStatusInTransaction({
    required String taskId,
    required String? requestedStatusId,
    required DateTime timestamp,
    List<SyncQueueCommand> precedingCommands = const [],
  }) async {
    final statusId = await _validInitialStatusId(requestedStatusId);
    await _replaceStatusAssignment(taskId, statusId, timestamp);
    await _syncQueue.enqueueBatch([
      ...precedingCommands,
      _statusCommand(taskId, statusId, timestamp),
    ], occurredAt: timestamp);
    return statusId;
  }

  Future<void> completeSubtreeInTransaction(
    String rootId, {
    required DateTime timestamp,
  }) async {
    final rows = await _activeTaskRows();
    final commands = <SyncQueueCommand>[];
    for (final row in _subtreeRows(rootId, rows)) {
      if (row.status == 'completed') {
        continue;
      }
      final previousStatusId = await resolveWorkflowStatusInTransaction(row.id);
      final completionId = _uuid.v4();
      await (_db.update(
        _db.tasks,
      )..where((task) => task.id.equals(row.id))).write(
        TasksCompanion(
          status: const Value('completed'),
          completedAt: Value(timestamp),
          updatedAt: Value(timestamp),
        ),
      );
      await _db
          .into(_db.taskCompletions)
          .insert(
            TaskCompletionsCompanion.insert(
              id: completionId,
              taskId: row.id,
              userId: localUserId,
              completedAt: timestamp,
              snapshotJson: Value(_completionSnapshot(previousStatusId)),
              createdAt: timestamp,
            ),
          );
      await _replaceStatusAssignment(row.id, kanbanStatusDoneId, timestamp);
      commands.addAll([
        SyncQueueCommand(
          type: 'task.complete',
          clientId: row.id,
          payload: {
            'id': row.id,
            'completionId': completionId,
            'completedAt': timestamp.toIso8601String(),
          },
        ),
        _statusCommand(row.id, kanbanStatusDoneId, timestamp),
      ]);
    }
    await _syncQueue.enqueueBatch(commands, occurredAt: timestamp);
  }

  Future<void> restoreSubtreeInTransaction(
    String rootId, {
    required DateTime timestamp,
    String? explicitRootStatusId,
  }) async {
    if (explicitRootStatusId != null &&
        !await _isActiveNonDoneStatus(explicitRootStatusId)) {
      throw ArgumentError.value(
        explicitRootStatusId,
        'explicitRootStatusId',
        'Restore target must be an active non-Done status',
      );
    }
    final rows = await _activeTaskRows();
    final commands = <SyncQueueCommand>[];
    for (final row in _subtreeRows(rootId, rows)) {
      if (row.status != 'completed') {
        continue;
      }
      final statusId = row.id == rootId && explicitRootStatusId != null
          ? explicitRootStatusId
          : await latestValidSnapshotStatusInTransaction(row.id);
      await (_db.update(
        _db.tasks,
      )..where((task) => task.id.equals(row.id))).write(
        TasksCompanion(
          status: const Value('open'),
          completedAt: const Value(null),
          updatedAt: Value(timestamp),
        ),
      );
      await _replaceStatusAssignment(row.id, statusId, timestamp);
      commands.addAll([
        SyncQueueCommand(
          type: 'task.uncomplete',
          clientId: row.id,
          payload: {'id': row.id, 'restoredAt': timestamp.toIso8601String()},
        ),
        _statusCommand(row.id, statusId, timestamp),
      ]);
    }
    await _syncQueue.enqueueBatch(commands, occurredAt: timestamp);
  }

  Future<void> moveTaskInTransaction(
    String taskId, {
    required String statusId,
    required DateTime timestamp,
  }) async {
    final status = await _activeStatus(statusId);
    if (status == null) {
      throw ArgumentError.value(statusId, 'statusId', 'Unknown Kanban status');
    }
    final task =
        await (_db.select(_db.tasks)..where(
              (row) => row.id.equals(taskId) & row.isDeleted.equals(false),
            ))
            .getSingleOrNull();
    if (task == null) {
      throw ArgumentError.value(taskId, 'taskId', 'Unknown task');
    }
    if (status.systemKey == kanbanSystemKeyDone) {
      if (task.status != 'completed') {
        await completeSubtreeInTransaction(taskId, timestamp: timestamp);
      } else {
        await _assignStatusWithCommand(taskId, statusId, timestamp);
      }
      return;
    }
    if (task.status == 'completed') {
      await restoreSubtreeInTransaction(
        taskId,
        timestamp: timestamp,
        explicitRootStatusId: statusId,
      );
      return;
    }
    await _assignStatusWithCommand(taskId, statusId, timestamp);
  }

  Future<String> resolveWorkflowStatusInTransaction(String taskId) async {
    final assignment =
        await (_db.select(_db.taskLabels)..where(
              (row) =>
                  row.taskId.equals(taskId) &
                  row.kind.equals(labelKindKanbanStatus),
            ))
            .getSingleOrNull();
    final statusId = assignment?.labelId;
    return statusId != null && await _isActiveNonDoneStatus(statusId)
        ? statusId
        : kanbanStatusBacklogId;
  }

  Future<String> latestValidSnapshotStatusInTransaction(String taskId) async {
    final completions =
        await (_db.select(_db.taskCompletions)
              ..where((row) => row.taskId.equals(taskId))
              ..orderBy([
                (row) => OrderingTerm.desc(row.completedAt),
                (row) => OrderingTerm.desc(row.createdAt),
                (row) => OrderingTerm.desc(row.id),
              ]))
            .get();
    for (final completion in completions) {
      final statusId = _snapshotStatusId(completion.snapshotJson);
      if (statusId != null && await _isActiveNonDoneStatus(statusId)) {
        return statusId;
      }
    }
    return kanbanStatusBacklogId;
  }

  Future<String> copyRecurringStatusInTransaction({
    required String sourceTaskId,
    required String newTaskId,
    required DateTime timestamp,
    List<SyncQueueCommand> precedingCommands = const [],
  }) async {
    final source = await (_db.select(
      _db.tasks,
    )..where((row) => row.id.equals(sourceTaskId))).getSingle();
    final statusId = source.status == 'completed'
        ? await latestValidSnapshotStatusInTransaction(sourceTaskId)
        : await resolveWorkflowStatusInTransaction(sourceTaskId);
    await _replaceStatusAssignment(newTaskId, statusId, timestamp);
    await _syncQueue.enqueueBatch([
      ...precedingCommands,
      _statusCommand(newTaskId, statusId, timestamp),
    ], occurredAt: timestamp);
    return statusId;
  }

  Future<String> prepareTaskForFocusInTransaction(
    String taskId, {
    required DateTime timestamp,
  }) async {
    final task =
        await (_db.select(_db.tasks)..where(
              (row) => row.id.equals(taskId) & row.isDeleted.equals(false),
            ))
            .getSingleOrNull();
    if (task == null) {
      throw ArgumentError.value(taskId, 'taskId', 'Unknown task');
    }
    if (task.status == 'completed') {
      throw StateError('Completed tasks must be restored before Focus starts');
    }
    final settings =
        await (_db.select(_db.kanbanSettings)
              ..where((row) => row.id.equals(kanbanSettingsPrimaryId)))
            .getSingleOrNull();
    final configuredStatusId = settings?.focusStatusLabelId;
    final statusId =
        configuredStatusId != null &&
            await _isActiveNonDoneStatus(configuredStatusId)
        ? configuredStatusId
        : await _fallbackFocusStatusId();
    await _assignStatusWithCommand(taskId, statusId, timestamp);
    return statusId;
  }

  Future<void> assignStatusInTransaction(
    String taskId, {
    required String statusId,
    required DateTime timestamp,
  }) async {
    if (await _activeStatus(statusId) == null) {
      throw ArgumentError.value(statusId, 'statusId', 'Unknown Kanban status');
    }
    await _assignStatusWithCommand(taskId, statusId, timestamp);
  }

  Future<void> repairAfterRemotePullInTransaction({
    required DateTime timestamp,
  }) async {
    await _repairProtectedAnchor(
      id: kanbanStatusBacklogId,
      systemKey: kanbanSystemKeyBacklog,
      orderKey: _backlogOrderKey,
      timestamp: timestamp,
    );
    await _repairProtectedAnchor(
      id: kanbanStatusDoneId,
      systemKey: kanbanSystemKeyDone,
      orderKey: _doneOrderKey,
      timestamp: timestamp,
    );

    final activeStatuses =
        await (_db.select(_db.labels)..where(
              (row) =>
                  row.kind.equals(labelKindKanbanStatus) &
                  row.isDeleted.equals(false),
            ))
            .get();
    final activeStatusById = {
      for (final status in activeStatuses) status.id: status,
    };
    final assignments = await (_db.select(
      _db.taskLabels,
    )..where((row) => row.kind.equals(labelKindKanbanStatus))).get();
    final assignmentByTask = {
      for (final assignment in assignments) assignment.taskId: assignment,
    };
    final commands = <SyncQueueCommand>[];
    for (final task in await _activeTaskRows()) {
      final currentStatusId = assignmentByTask[task.id]?.labelId;
      final currentStatus = activeStatusById[currentStatusId];
      final expectedStatusId = task.status == 'completed'
          ? kanbanStatusDoneId
          : currentStatus != null &&
                currentStatus.systemKey != kanbanSystemKeyDone
          ? currentStatus.id
          : await latestValidSnapshotStatusInTransaction(task.id);
      if (await _replaceStatusAssignment(
        task.id,
        expectedStatusId,
        timestamp,
      )) {
        commands.add(_statusCommand(task.id, expectedStatusId, timestamp));
      }
    }

    final settingsBefore =
        await (_db.select(_db.kanbanSettings)
              ..where((row) => row.id.equals(kanbanSettingsPrimaryId)))
            .getSingleOrNull();
    await _db.repairKanbanSettings(now: timestamp);
    final settingsAfter = await (_db.select(
      _db.kanbanSettings,
    )..where((row) => row.id.equals(kanbanSettingsPrimaryId))).getSingle();
    if (settingsBefore?.selectedProjectIdsJson !=
        settingsAfter.selectedProjectIdsJson) {
      commands.add(
        SyncQueueCommand(
          type: 'kanban.settings.projects.set',
          clientId: kanbanSettingsPrimaryId,
          payload: {
            'id': kanbanSettingsPrimaryId,
            'selectedProjectIdsJson': settingsAfter.selectedProjectIdsJson,
            'changedAt': timestamp.toIso8601String(),
          },
        ),
      );
    }
    if (settingsBefore?.focusStatusLabelId !=
        settingsAfter.focusStatusLabelId) {
      commands.add(
        SyncQueueCommand(
          type: 'kanban.settings.focus.set',
          clientId: kanbanSettingsPrimaryId,
          payload: {
            'id': kanbanSettingsPrimaryId,
            'focusStatusLabelId': settingsAfter.focusStatusLabelId,
            'changedAt': timestamp.toIso8601String(),
          },
        ),
      );
    }
    await _syncQueue.enqueueBatch(commands, occurredAt: timestamp);
  }

  Future<void> _repairProtectedAnchor({
    required String id,
    required String systemKey,
    required String orderKey,
    required DateTime timestamp,
  }) async {
    final existing = await (_db.select(
      _db.labels,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (existing == null) {
      await _db
          .into(_db.labels)
          .insert(
            LabelsCompanion.insert(
              id: id,
              userId: localUserId,
              name: systemKey == kanbanSystemKeyDone ? 'Done' : 'Backlog',
              kind: const Value(labelKindKanbanStatus),
              systemKey: Value(systemKey),
              orderKey: orderKey,
              createdAt: timestamp,
              updatedAt: timestamp,
            ),
          );
      return;
    }
    if (existing.kind == labelKindKanbanStatus &&
        existing.systemKey == systemKey &&
        existing.orderKey == orderKey &&
        !existing.isDeleted) {
      return;
    }
    await (_db.update(_db.labels)..where((row) => row.id.equals(id))).write(
      LabelsCompanion(
        kind: const Value(labelKindKanbanStatus),
        systemKey: Value(systemKey),
        orderKey: Value(orderKey),
        isDeleted: const Value(false),
        updatedAt: Value(timestamp),
      ),
    );
  }

  Future<void> _assignStatusWithCommand(
    String taskId,
    String statusId,
    DateTime timestamp,
  ) async {
    final changed = await _replaceStatusAssignment(taskId, statusId, timestamp);
    if (changed) {
      await _syncQueue.enqueueBatch([
        _statusCommand(taskId, statusId, timestamp),
      ], occurredAt: timestamp);
    }
  }

  Future<bool> _replaceStatusAssignment(
    String taskId,
    String statusId,
    DateTime timestamp,
  ) async {
    final current =
        await (_db.select(_db.taskLabels)..where(
              (row) =>
                  row.taskId.equals(taskId) &
                  row.kind.equals(labelKindKanbanStatus),
            ))
            .getSingleOrNull();
    if (current?.labelId == statusId) {
      return false;
    }
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
            labelId: statusId,
            kind: const Value(labelKindKanbanStatus),
            createdAt: timestamp,
          ),
        );
    return true;
  }

  Future<String> _validInitialStatusId(String? requestedStatusId) async {
    if (requestedStatusId != null &&
        await _isActiveNonDoneStatus(requestedStatusId)) {
      return requestedStatusId;
    }
    return kanbanStatusBacklogId;
  }

  Future<bool> _isActiveNonDoneStatus(String id) async {
    final status = await _activeStatus(id);
    return status != null && status.systemKey != kanbanSystemKeyDone;
  }

  Future<String> _fallbackFocusStatusId() async {
    final statuses =
        await (_db.select(_db.labels)..where(
              (row) =>
                  row.kind.equals(labelKindKanbanStatus) &
                  row.isDeleted.equals(false),
            ))
            .get();
    statuses.sort((a, b) {
      final order = a.orderKey.compareTo(b.orderKey);
      return order != 0 ? order : a.id.compareTo(b.id);
    });
    for (final status in statuses) {
      if (status.systemKey != kanbanSystemKeyBacklog &&
          status.systemKey != kanbanSystemKeyDone) {
        return status.id;
      }
    }
    return kanbanStatusBacklogId;
  }

  Future<LabelRow?> _activeStatus(String id) {
    return (_db.select(_db.labels)..where(
          (row) =>
              row.id.equals(id) &
              row.kind.equals(labelKindKanbanStatus) &
              row.isDeleted.equals(false),
        ))
        .getSingleOrNull();
  }

  Future<List<TaskRow>> _activeTaskRows() {
    return (_db.select(
      _db.tasks,
    )..where((row) => row.isDeleted.equals(false))).get();
  }

  List<TaskRow> _subtreeRows(String rootId, List<TaskRow> rows) {
    final rowById = {for (final row in rows) row.id: row};
    final root = rowById[rootId];
    if (root == null) {
      return const [];
    }
    final childrenByParent = <String, List<TaskRow>>{};
    for (final row in rows) {
      final parentId = row.parentId;
      if (parentId != null) {
        childrenByParent.putIfAbsent(parentId, () => []).add(row);
      }
    }
    for (final children in childrenByParent.values) {
      children.sort((a, b) {
        final order = a.orderKey.compareTo(b.orderKey);
        return order != 0 ? order : a.id.compareTo(b.id);
      });
    }
    final result = <TaskRow>[];
    final stack = <TaskRow>[root];
    final seen = <String>{};
    while (stack.isNotEmpty) {
      final row = stack.removeLast();
      if (!seen.add(row.id)) {
        continue;
      }
      result.add(row);
      stack.addAll((childrenByParent[row.id] ?? const []).reversed);
    }
    return result;
  }

  SyncQueueCommand _statusCommand(
    String taskId,
    String statusId,
    DateTime timestamp,
  ) {
    return SyncQueueCommand(
      type: 'task.kanbanStatus.set',
      clientId: taskId,
      payload: {
        'taskId': taskId,
        'labelId': statusId,
        'changedAt': timestamp.toIso8601String(),
      },
    );
  }

  String _completionSnapshot(String statusId) {
    return jsonEncode({
      'version': 1,
      'kanban': {'previousStatusLabelId': statusId},
    });
  }

  String? _snapshotStatusId(String? snapshotJson) {
    if (snapshotJson == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(snapshotJson);
      if (decoded is! Map || decoded['version'] != 1) {
        return null;
      }
      final kanban = decoded['kanban'];
      if (kanban is! Map) {
        return null;
      }
      final value = kanban['previousStatusLabelId'];
      return value is String && value.trim().isNotEmpty ? value : null;
    } on FormatException {
      return null;
    }
  }
}
