import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:pomodoist/data/services/local/kanban_transition_store.dart';

import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/shared_access.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';

const _backlogOrderKey = '00000000000000000000';
const _doneOrderKey = '00004503599627370496';

class KanbanTransitionCoordinator {
  KanbanTransitionCoordinator(this._db, this._syncQueue, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid(),
      _store = KanbanTransitionStore(_db);

  final AppDatabase _db;
  final KanbanTransitionStore _store;
  final OutboxService _syncQueue;
  final Uuid _uuid;

  Future<String> assignInitialStatusInTransaction({
    required String taskId,
    required String? requestedStatusId,
    required DateTime timestamp,
    List<SyncQueueCommand> precedingCommands = const [],
  }) async {
    final statusId = await _validInitialStatusId(taskId, requestedStatusId);
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
    await SharedAccess(_db).task(rootId);
    final rows = await _activeTaskRows();
    final commands = <SyncQueueCommand>[];
    for (final row in _subtreeRows(rootId, rows)) {
      if (row.status == 'completed') {
        continue;
      }
      final previousStatusId = await resolveWorkflowStatusInTransaction(row.id);
      final completionId = _uuid.v4();
      await _store.writeTask(
        row.id,
        TasksCompanion(
          status: const Value('completed'),
          completedAt: Value(timestamp),
          completedBy: Value(await SharedAccess(_db).actorId()),
          updatedAt: Value(timestamp),
        ),
      );
      await _store.insertCompletion(
        TaskCompletionsCompanion.insert(
          id: completionId,
          taskId: row.id,
          userId: localUserId,
          completedAt: timestamp,
          snapshotJson: Value(_completionSnapshot(previousStatusId)),
          createdAt: timestamp,
        ),
      );
      final doneId = await _anchor(row.id, kanbanStatusDoneId);
      await _replaceStatusAssignment(row.id, doneId, timestamp);
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
        _statusCommand(row.id, doneId, timestamp),
      ]);
    }
    await _syncQueue.enqueueBatch(commands, occurredAt: timestamp);
  }

  Future<void> restoreSubtreeInTransaction(
    String rootId, {
    required DateTime timestamp,
    String? explicitRootStatusId,
  }) async {
    await SharedAccess(_db).task(rootId);
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
      await _store.writeTask(
        row.id,
        TasksCompanion(
          status: const Value('open'),
          completedAt: const Value(null),
          completedBy: const Value(null),
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
    await SharedAccess(_db).task(taskId);
    final status = await _activeStatus(statusId);
    if (status == null) {
      throw ArgumentError.value(statusId, 'statusId', 'Unknown Kanban status');
    }
    final task = await _store.task(taskId, activeOnly: true);
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
    final assignment = await _store.assignment(taskId);
    final statusId = assignment?.labelId;
    return statusId != null && await _isActiveNonDoneStatus(statusId)
        ? statusId
        : await _anchor(taskId, kanbanStatusBacklogId);
  }

  Future<String> latestValidSnapshotStatusInTransaction(String taskId) async {
    final completions = await _store.completions(taskId);
    for (final completion in completions) {
      final statusId = _snapshotStatusId(completion.snapshotJson);
      if (statusId != null && await _isActiveNonDoneStatus(statusId)) {
        return statusId;
      }
    }
    return _anchor(taskId, kanbanStatusBacklogId);
  }

  Future<String> copyRecurringStatusInTransaction({
    required String sourceTaskId,
    required String newTaskId,
    required DateTime timestamp,
    List<SyncQueueCommand> precedingCommands = const [],
  }) async {
    final source = (await _store.task(sourceTaskId))!;
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
    await SharedAccess(_db).task(taskId);
    final task = await _store.task(taskId, activeOnly: true);
    if (task == null) {
      throw ArgumentError.value(taskId, 'taskId', 'Unknown task');
    }
    if (task.status == 'completed') {
      throw StateError('Completed tasks must be restored before Focus starts');
    }
    final settings = await _store.settings();
    final configuredStatusId = settings?.focusStatusLabelId;
    final statusId =
        configuredStatusId != null &&
            await _isActiveNonDoneStatus(configuredStatusId) &&
            await _sameScope(taskId, configuredStatusId)
        ? configuredStatusId
        : await _fallbackFocusStatusId(taskId);
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
    await _store.repairProtectedAnchor(
      id: kanbanStatusBacklogId,
      systemKey: kanbanSystemKeyBacklog,
      orderKey: _backlogOrderKey,
      timestamp: timestamp,
    );
    await _store.repairProtectedAnchor(
      id: kanbanStatusDoneId,
      systemKey: kanbanSystemKeyDone,
      orderKey: _doneOrderKey,
      timestamp: timestamp,
    );

    final activeStatuses = await _store.activeStatuses();
    final activeStatusById = {
      for (final status in activeStatuses) status.id: status,
    };
    final assignments = await _store.assignments();
    final assignmentByTask = {
      for (final assignment in assignments) assignment.taskId: assignment,
    };
    final commands = <SyncQueueCommand>[];
    for (final task in await _activeTaskRows()) {
      // Shared scopes are repaired on the server, including for read-only clients.
      if (task.scopeId != null) continue;
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

    final settingsBefore = await _store.settings();
    await _store.repairSettings(timestamp);
    final settingsAfter = (await _store.settings())!;
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
    final task = await _store.task(taskId);
    final status = await _store.label(statusId);
    if (task == null || status == null) {
      // ponytail: missing kanban seed label degrades to "no status" instead of
      // failing the whole task mutation; ensureSeedData normally guarantees it.
      return false;
    }
    if (task.scopeId != status.scopeId) {
      throw ArgumentError.value(
        statusId,
        'statusId',
        'Kanban status belongs to another project scope',
      );
    }
    final current = await _store.assignment(taskId);
    if (current?.labelId == statusId) {
      return false;
    }
    await _store.replaceAssignment(taskId, statusId, timestamp);
    return true;
  }

  Future<String> _validInitialStatusId(
    String taskId,
    String? requestedStatusId,
  ) async {
    if (requestedStatusId != null &&
        await _isActiveNonDoneStatus(requestedStatusId)) {
      final resolved = await resolveStatusInTaskScope(
        taskId,
        requestedStatusId,
      );
      if (resolved != null) {
        return resolved;
      }
    }
    return _anchor(taskId, kanbanStatusBacklogId);
  }

  Future<bool> _isActiveNonDoneStatus(String id) async {
    final status = await _activeStatus(id);
    return status != null && status.systemKey != kanbanSystemKeyDone;
  }

  /// The status of the same project scope as [taskId] that [statusId] stands
  /// for. Scopes mirror the shared status set, so a board column points at the
  /// matching status of the card's own scope. Returns `null` when that scope
  /// defines no such status.
  Future<String?> resolveStatusInTaskScope(
    String taskId,
    String statusId,
  ) async {
    final status = await _activeStatus(statusId);
    final task = await _store.task(taskId);
    if (status == null || task == null) {
      return null;
    }
    if (status.scopeId == task.scopeId) {
      return status.id;
    }
    final candidates = (await _store.activeStatuses()).where(
      (row) => row.scopeId == task.scopeId,
    );
    if (status.systemKey != null) {
      for (final candidate in candidates) {
        if (candidate.systemKey == status.systemKey) {
          return candidate.id;
        }
      }
      return null;
    }
    final name = status.name.trim().toLowerCase();
    for (final candidate in candidates) {
      if (candidate.systemKey == null &&
          candidate.name.trim().toLowerCase() == name) {
        return candidate.id;
      }
    }
    return null;
  }

  Future<String> _fallbackFocusStatusId(String taskId) async {
    final statuses = await _store.activeStatuses();
    statuses.sort((a, b) {
      final order = a.orderKey.compareTo(b.orderKey);
      return order != 0 ? order : a.id.compareTo(b.id);
    });
    for (final status in statuses) {
      if (await _sameScope(taskId, status.id) &&
          status.systemKey != kanbanSystemKeyBacklog &&
          status.systemKey != kanbanSystemKeyDone) {
        return status.id;
      }
    }
    return _anchor(taskId, kanbanStatusBacklogId);
  }

  Future<String> _anchor(String taskId, String personalId) async {
    final task = (await _store.task(taskId))!;
    return task.scopeId == null ? personalId : '${task.scopeId}:$personalId';
  }

  Future<bool> _sameScope(String taskId, String labelId) async {
    final task = await _store.task(taskId);
    final label = await _store.label(labelId);
    return task != null && label != null && task.scopeId == label.scopeId;
  }

  Future<LabelRow?> _activeStatus(String id) => _store.activeStatus(id);
  Future<List<TaskRow>> _activeTaskRows() => _store.activeTasks();

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
