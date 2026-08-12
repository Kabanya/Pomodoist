import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart' as db_schema;
import '../../../core/sync/sync_queue_repository.dart';
import '../domain/task_models.dart';
import 'kanban_transition_coordinator.dart';

const _minimumOrderValue = 0;
const _maximumOrderValue = 4503599627370496;
const _orderKeyWidth = 20;

class DriftKanbanRepository implements KanbanRepository {
  DriftKanbanRepository(
    db_schema.AppDatabase db, {
    SyncQueueRepository? syncQueue,
    KanbanTransitionCoordinator? kanbanTransitions,
    Uuid? uuid,
  }) : _db = db,
       _syncQueue = syncQueue ?? DriftSyncQueueRepository(db, uuid: uuid),
       _kanbanTransitions =
           kanbanTransitions ??
           KanbanTransitionCoordinator(
             db,
             syncQueue ?? DriftSyncQueueRepository(db, uuid: uuid),
             uuid: uuid,
           ),
       _uuid = uuid ?? const Uuid();

  final db_schema.AppDatabase _db;
  final SyncQueueRepository _syncQueue;
  final KanbanTransitionCoordinator _kanbanTransitions;
  final Uuid _uuid;

  @override
  Stream<KanbanBoardSnapshot> watchBoard() async* {
    final changes = _db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            _db.labels,
            _db.taskLabels,
            _db.kanbanSettings,
            _db.projects,
            _db.tasks,
          },
        )
        .watch();
    await for (final _ in changes) {
      yield await _loadSnapshot();
    }
  }

  @override
  Future<String> createStatus(String name, {String? color}) async {
    final normalizedName = _normalizedName(name);
    await _db.ensureKanbanData();
    await _ensureUniqueStatusName(normalizedName);
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await _db
          .into(_db.labels)
          .insert(
            db_schema.LabelsCompanion.insert(
              id: id,
              userId: db_schema.localUserId,
              name: normalizedName,
              color: Value(color),
              kind: const Value(db_schema.labelKindKanbanStatus),
              orderKey: _formatOrderValue(_maximumOrderValue ~/ 2),
              createdAt: now,
              updatedAt: now,
            ),
          );
      final statuses = await _activeStatusRows();
      final created = statuses.singleWhere((status) => status.id == id);
      statuses.remove(created);
      final doneIndex = statuses.indexWhere(_isDoneRow);
      statuses.insert(doneIndex < 0 ? statuses.length : doneIndex, created);
      final orderChanges = await _writeStatusOrder(statuses, now);
      final finalStatus = await _activeStatusRow(id);
      await _syncQueue.enqueueBatch([
        SyncQueueCommand(
          type: 'kanban.status.create',
          clientId: id,
          payload: {
            'id': id,
            'name': normalizedName,
            'color': color,
            'kind': db_schema.labelKindKanbanStatus,
            'systemKey': null,
            'orderKey': finalStatus!.orderKey,
            'changedAt': now.toIso8601String(),
          },
        ),
        for (final change in orderChanges.where((change) => change.id != id))
          _statusOrderCommand(change.id, change.orderKey, now),
      ], occurredAt: now);
    });
    return id;
  }

  @override
  Future<void> renameStatus(String id, String name) async {
    final normalizedName = _normalizedName(name);
    await _db.ensureKanbanData();
    final status = await _activeStatusRow(id);
    if (status == null) {
      throw ArgumentError.value(id, 'id', 'Unknown Kanban status');
    }
    await _ensureUniqueStatusName(normalizedName, exceptId: id);
    if (status.name == normalizedName) {
      return;
    }
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await (_db.update(_db.labels)..where((row) => row.id.equals(id))).write(
        db_schema.LabelsCompanion(
          name: Value(normalizedName),
          updatedAt: Value(now),
        ),
      );
      await _syncQueue.enqueueBatch([
        SyncQueueCommand(
          type: 'kanban.status.rename',
          clientId: id,
          payload: {
            'id': id,
            'name': normalizedName,
            'changedAt': now.toIso8601String(),
          },
        ),
      ], occurredAt: now);
    });
  }

  @override
  Future<void> reorderStatus(String id, int targetIndex) async {
    await _db.ensureKanbanData();
    final statuses = await _activeStatusRows();
    final currentIndex = statuses.indexWhere((status) => status.id == id);
    if (currentIndex < 0) {
      throw ArgumentError.value(id, 'id', 'Unknown Kanban status');
    }
    final status = statuses[currentIndex];
    if (_isProtectedRow(status)) {
      throw StateError('Protected Kanban anchors cannot be reordered');
    }
    statuses.removeAt(currentIndex);
    final maximumMiddleIndex = statuses.length - 1;
    final nextIndex = targetIndex.clamp(1, maximumMiddleIndex);
    statuses.insert(nextIndex, status);
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      final changes = await _writeStatusOrder(statuses, now);
      await _syncQueue.enqueueBatch([
        for (final change in changes)
          _statusOrderCommand(change.id, change.orderKey, now),
      ], occurredAt: now);
    });
  }

  @override
  Future<void> deleteStatus(String id) async {
    await _db.ensureKanbanData();
    final status = await _activeStatusRow(id);
    if (status == null) {
      return;
    }
    if (_isProtectedRow(status)) {
      throw StateError('Protected Kanban anchors cannot be deleted');
    }
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      final settingsBefore = await _settingsRow();
      final links =
          await (_db.select(_db.taskLabels)..where(
                (row) =>
                    row.kind.equals(db_schema.labelKindKanbanStatus) &
                    row.labelId.equals(id),
              ))
              .get();
      for (final link in links) {
        await _kanbanTransitions.assignStatusInTransaction(
          link.taskId,
          statusId: db_schema.kanbanStatusBacklogId,
          timestamp: now,
        );
      }
      await (_db.update(_db.labels)..where((row) => row.id.equals(id))).write(
        db_schema.LabelsCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(now),
        ),
      );
      await _db.repairKanbanSettings(now: now);
      final settingsAfter = await _settingsRow();
      await _syncQueue.enqueueBatch([
        SyncQueueCommand(
          type: 'kanban.status.delete',
          clientId: id,
          payload: {
            'id': id,
            'isDeleted': true,
            'changedAt': now.toIso8601String(),
          },
        ),
        ..._settingsCommands(settingsBefore, settingsAfter, now),
      ], occurredAt: now);
    });
  }

  @override
  Future<void> setSelectedProjectIds(Set<String> projectIds) async {
    await _db.ensureKanbanData();
    if (projectIds.isEmpty) {
      return;
    }
    final activeIds =
        (await (_db.select(_db.projects)..where(
                  (row) =>
                      row.isDeleted.equals(false) &
                      row.isArchived.equals(false),
                ))
                .get())
            .map((project) => project.id)
            .toSet();
    final selected = projectIds.where(activeIds.contains).toSet().toList()
      ..sort();
    if (selected.isEmpty) {
      return;
    }
    final settings = await _settingsRow();
    final encoded = jsonEncode(selected);
    if (settings.selectedProjectIdsJson == encoded) {
      return;
    }
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await (_db.update(_db.kanbanSettings)
            ..where((row) => row.id.equals(db_schema.kanbanSettingsPrimaryId)))
          .write(
            db_schema.KanbanSettingsCompanion(
              selectedProjectIdsJson: Value(encoded),
              updatedAt: Value(now),
            ),
          );
      await _syncQueue.enqueueBatch([
        SyncQueueCommand(
          type: 'kanban.settings.projects.set',
          clientId: db_schema.kanbanSettingsPrimaryId,
          payload: {
            'id': db_schema.kanbanSettingsPrimaryId,
            'selectedProjectIdsJson': encoded,
            'changedAt': now.toIso8601String(),
          },
        ),
      ], occurredAt: now);
    });
  }

  @override
  Future<void> setFocusStatus(String statusId) async {
    await _db.ensureKanbanData();
    final status = await _activeStatusRow(statusId);
    if (status == null || _isDoneRow(status)) {
      throw ArgumentError.value(
        statusId,
        'statusId',
        'Focus status must be an active non-Done status',
      );
    }
    final settings = await _settingsRow();
    if (settings.focusStatusLabelId == statusId) {
      return;
    }
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await (_db.update(_db.kanbanSettings)
            ..where((row) => row.id.equals(db_schema.kanbanSettingsPrimaryId)))
          .write(
            db_schema.KanbanSettingsCompanion(
              focusStatusLabelId: Value(statusId),
              updatedAt: Value(now),
            ),
          );
      await _syncQueue.enqueueBatch([
        SyncQueueCommand(
          type: 'kanban.settings.focus.set',
          clientId: db_schema.kanbanSettingsPrimaryId,
          payload: {
            'id': db_schema.kanbanSettingsPrimaryId,
            'focusStatusLabelId': statusId,
            'changedAt': now.toIso8601String(),
          },
        ),
      ], occurredAt: now);
    });
  }

  @override
  Future<void> moveTask(
    String taskId, {
    required String statusId,
    int? targetIndex,
  }) async {
    await _db.ensureKanbanData();
    final status = await _activeStatusRow(statusId);
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
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await _kanbanTransitions.moveTaskInTransaction(
        taskId,
        statusId: statusId,
        timestamp: now,
      );
      if (!_isDoneRow(status)) {
        await _reorderTask(
          task,
          statusId: statusId,
          targetIndex: targetIndex,
          now: now,
        );
      }
    });
  }

  Future<KanbanBoardSnapshot> _loadSnapshot() async {
    final statusRows = await _activeStatusRows();
    final projectRows =
        await (_db.select(_db.projects)
              ..where(
                (row) =>
                    row.isDeleted.equals(false) & row.isArchived.equals(false),
              )
              ..orderBy([
                (row) => OrderingTerm.asc(row.orderKey),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    final settingsRow = await _settingsRow();
    final settings = _mapSettings(settingsRow);
    final selectedProjectIds = settings.selectedProjectIds;
    final projectById = {for (final row in projectRows) row.id: row};
    final statusById = {for (final row in statusRows) row.id: row};

    final openRoots = selectedProjectIds.isEmpty
        ? <db_schema.TaskRow>[]
        : await (_db.select(_db.tasks)
                ..where(
                  (row) =>
                      row.projectId.isIn(selectedProjectIds) &
                      row.parentId.isNull() &
                      row.isDeleted.equals(false) &
                      row.status.equals('open'),
                )
                ..orderBy([
                  (row) => OrderingTerm.asc(row.orderKey),
                  (row) => OrderingTerm.asc(row.id),
                ]))
              .get();
    final doneRecency = coalesce<DateTime>([
      _db.tasks.completedAt,
      _db.tasks.updatedAt,
    ]);
    final doneRoots = selectedProjectIds.isEmpty
        ? <db_schema.TaskRow>[]
        : await (_db.select(_db.tasks)
                ..where(
                  (row) =>
                      row.projectId.isIn(selectedProjectIds) &
                      row.parentId.isNull() &
                      row.isDeleted.equals(false) &
                      row.status.equals('completed'),
                )
                ..orderBy([
                  (_) => OrderingTerm.desc(doneRecency),
                  (row) => OrderingTerm.desc(row.id),
                ])
                ..limit(20))
              .get();
    final candidateRoots = [...openRoots, ...doneRoots];
    final statusIdByTask = <String, String>{};
    for (final taskIds in candidateRoots.map((row) => row.id).slices(400)) {
      final links =
          await (_db.select(_db.taskLabels)..where(
                (row) =>
                    row.kind.equals(db_schema.labelKindKanbanStatus) &
                    row.taskId.isIn(taskIds),
              ))
              .get();
      for (final link in links) {
        statusIdByTask[link.taskId] = link.labelId;
      }
    }

    final renderedRoots = <({db_schema.TaskRow task, String statusId})>[];
    for (final task in candidateRoots) {
      final statusId = statusIdByTask[task.id];
      final status = statusById[statusId];
      if (status == null ||
          (task.status == 'completed') != _isDoneRow(status)) {
        continue;
      }
      renderedRoots.add((task: task, statusId: status.id));
    }

    final subtaskProgressByParent = <String, ({int total, int completed})>{};
    final totalSubtasks = _db.tasks.id.count();
    final completedSubtasks = _db.tasks.id.count(
      filter: _db.tasks.status.equals('completed'),
    );
    for (final parentIds
        in renderedRoots.map((root) => root.task.id).slices(400)) {
      final progressRows =
          await (_db.selectOnly(_db.tasks)
                ..addColumns([
                  _db.tasks.parentId,
                  totalSubtasks,
                  completedSubtasks,
                ])
                ..where(
                  _db.tasks.parentId.isIn(parentIds) &
                      _db.tasks.parentId.isNotNull() &
                      _db.tasks.isDeleted.equals(false),
                )
                ..groupBy([_db.tasks.parentId]))
              .get();
      for (final progress in progressRows) {
        final parentId = progress.read(_db.tasks.parentId);
        if (parentId != null) {
          subtaskProgressByParent[parentId] = (
            total: progress.read(totalSubtasks) ?? 0,
            completed: progress.read(completedSubtasks) ?? 0,
          );
        }
      }
    }

    final cardsByStatusId = {
      for (final row in statusRows) row.id: <KanbanCard>[],
    };
    for (final root in renderedRoots) {
      final task = root.task;
      final project = projectById[task.projectId];
      if (project == null) {
        continue;
      }
      final progress = subtaskProgressByParent[task.id];
      cardsByStatusId[root.statusId]!.add(
        KanbanCard(
          task: _mapTask(task),
          project: _mapProject(project),
          statusId: root.statusId,
          totalSubtasks: progress?.total ?? 0,
          completedSubtasks: progress?.completed ?? 0,
        ),
      );
    }

    for (final status in statusRows) {
      final cards = cardsByStatusId[status.id]!;
      if (_isDoneRow(status)) {
        cards.sort((a, b) {
          final aRecency = a.task.completedAt ?? a.task.updatedAt;
          final bRecency = b.task.completedAt ?? b.task.updatedAt;
          final dateCompare = bRecency.compareTo(aRecency);
          if (dateCompare != 0) {
            return dateCompare;
          }
          return b.task.id.compareTo(a.task.id);
        });
        if (cards.length > 20) {
          cards.removeRange(20, cards.length);
        }
      } else {
        cards.sort(_compareCardsByOrder);
      }
    }

    return KanbanBoardSnapshot(
      statuses: statusRows.map(_mapStatus),
      settings: settings,
      availableProjects: projectRows.map(_mapProject),
      cardsByStatusId: cardsByStatusId,
    );
  }

  Future<void> _reorderTask(
    db_schema.TaskRow task, {
    required String statusId,
    required int? targetIndex,
    required DateTime now,
  }) async {
    final settings = await _settingsRow();
    final selectedProjectIds = _decodeProjectIds(
      settings.selectedProjectIdsJson,
    ).toSet();
    final links =
        await (_db.select(_db.taskLabels)..where(
              (row) =>
                  row.kind.equals(db_schema.labelKindKanbanStatus) &
                  row.labelId.equals(statusId),
            ))
            .get();
    final taskIds = links.map((link) => link.taskId).toSet();
    final rows =
        await (_db.select(_db.tasks)..where(
              (row) =>
                  row.id.isIn(taskIds) &
                  row.isDeleted.equals(false) &
                  row.status.equals('open') &
                  row.parentId.isNull() &
                  row.projectId.isIn(selectedProjectIds),
            ))
            .get();
    rows.sort((a, b) {
      final orderCompare = a.orderKey.compareTo(b.orderKey);
      return orderCompare != 0 ? orderCompare : a.id.compareTo(b.id);
    });
    rows.removeWhere((row) => row.id == task.id);
    final insertionIndex = (targetIndex ?? rows.length).clamp(0, rows.length);
    rows.insert(insertionIndex, task);

    final left = insertionIndex == 0 ? null : rows[insertionIndex - 1].orderKey;
    final right = insertionIndex == rows.length - 1
        ? null
        : rows[insertionIndex + 1].orderKey;
    final midpoint = _midpointOrderKey(left, right);
    if (midpoint != null) {
      await _writeTaskOrder(task.id, midpoint, now);
      return;
    }
    await _rebalanceTaskRows(rows, now);
  }

  Future<void> _rebalanceTaskRows(
    List<db_schema.TaskRow> rows,
    DateTime now,
  ) async {
    final step = _maximumOrderValue ~/ (rows.length + 1);
    for (var index = 0; index < rows.length; index++) {
      await _writeTaskOrder(
        rows[index].id,
        _formatOrderValue(step * (index + 1)),
        now,
      );
    }
  }

  Future<void> _writeTaskOrder(String id, String orderKey, DateTime now) async {
    await (_db.update(_db.tasks)..where((row) => row.id.equals(id))).write(
      db_schema.TasksCompanion(
        orderKey: Value(orderKey),
        updatedAt: Value(now),
      ),
    );
    await _syncQueue.enqueueBatch([
      SyncQueueCommand(
        type: 'task.reorder',
        clientId: id,
        payload: {
          'id': id,
          'orderKey': orderKey,
          'changedAt': now.toIso8601String(),
        },
      ),
    ], occurredAt: now);
  }

  String? _midpointOrderKey(String? left, String? right) {
    final leftValue = left == null ? _minimumOrderValue : _parseOrderKey(left);
    final rightValue = right == null
        ? _maximumOrderValue
        : _parseOrderKey(right);
    if (leftValue == null ||
        rightValue == null ||
        rightValue - leftValue <= 1) {
      return null;
    }
    return _formatOrderValue(leftValue + ((rightValue - leftValue) ~/ 2));
  }

  int? _parseOrderKey(String value) {
    if (value.length != _orderKeyWidth) {
      return null;
    }
    return int.tryParse(value);
  }

  Future<List<db_schema.LabelRow>> _activeStatusRows() async {
    final rows =
        await (_db.select(_db.labels)..where(
              (row) =>
                  row.kind.equals(db_schema.labelKindKanbanStatus) &
                  row.isDeleted.equals(false),
            ))
            .get();
    rows.sort(_compareStatusRows);
    return rows;
  }

  Future<db_schema.LabelRow?> _activeStatusRow(String id) {
    return (_db.select(_db.labels)..where(
          (row) =>
              row.id.equals(id) &
              row.kind.equals(db_schema.labelKindKanbanStatus) &
              row.isDeleted.equals(false),
        ))
        .getSingleOrNull();
  }

  Future<List<({String id, String orderKey})>> _writeStatusOrder(
    List<db_schema.LabelRow> statuses,
    DateTime now,
  ) async {
    final changes = <({String id, String orderKey})>[];
    final step = _maximumOrderValue ~/ (statuses.length - 1);
    for (var index = 0; index < statuses.length; index++) {
      final value = index == statuses.length - 1
          ? _maximumOrderValue
          : step * index;
      final orderKey = _formatOrderValue(value);
      if (statuses[index].orderKey == orderKey) {
        continue;
      }
      await (_db.update(
        _db.labels,
      )..where((row) => row.id.equals(statuses[index].id))).write(
        db_schema.LabelsCompanion(
          orderKey: Value(orderKey),
          updatedAt: Value(now),
        ),
      );
      changes.add((id: statuses[index].id, orderKey: orderKey));
    }
    return changes;
  }

  SyncQueueCommand _statusOrderCommand(
    String id,
    String orderKey,
    DateTime now,
  ) {
    return SyncQueueCommand(
      type: 'kanban.status.reorder',
      clientId: id,
      payload: {
        'id': id,
        'orderKey': orderKey,
        'changedAt': now.toIso8601String(),
      },
    );
  }

  List<SyncQueueCommand> _settingsCommands(
    db_schema.KanbanSettingsRow before,
    db_schema.KanbanSettingsRow after,
    DateTime now,
  ) {
    return [
      if (before.selectedProjectIdsJson != after.selectedProjectIdsJson)
        SyncQueueCommand(
          type: 'kanban.settings.projects.set',
          clientId: db_schema.kanbanSettingsPrimaryId,
          payload: {
            'id': db_schema.kanbanSettingsPrimaryId,
            'selectedProjectIdsJson': after.selectedProjectIdsJson,
            'changedAt': now.toIso8601String(),
          },
        ),
      if (before.focusStatusLabelId != after.focusStatusLabelId)
        SyncQueueCommand(
          type: 'kanban.settings.focus.set',
          clientId: db_schema.kanbanSettingsPrimaryId,
          payload: {
            'id': db_schema.kanbanSettingsPrimaryId,
            'focusStatusLabelId': after.focusStatusLabelId,
            'changedAt': now.toIso8601String(),
          },
        ),
    ];
  }

  Future<void> _ensureUniqueStatusName(String name, {String? exceptId}) async {
    final duplicate =
        await (_db.select(_db.labels)..where(
              (row) =>
                  row.kind.equals(db_schema.labelKindKanbanStatus) &
                  row.isDeleted.equals(false) &
                  row.name.lower().equals(name.toLowerCase()) &
                  (exceptId == null
                      ? const Constant(true)
                      : row.id.equals(exceptId).not()),
            ))
            .getSingleOrNull();
    if (duplicate != null) {
      throw ArgumentError.value(name, 'name', 'Status name already exists');
    }
  }

  Future<db_schema.KanbanSettingsRow> _settingsRow() {
    return (_db.select(_db.kanbanSettings)
          ..where((row) => row.id.equals(db_schema.kanbanSettingsPrimaryId)))
        .getSingle();
  }

  String _normalizedName(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Status name cannot be empty');
    }
    return normalized;
  }

  int _compareStatusRows(db_schema.LabelRow a, db_schema.LabelRow b) {
    final rankCompare = _statusRank(a).compareTo(_statusRank(b));
    if (rankCompare != 0) {
      return rankCompare;
    }
    final orderCompare = a.orderKey.compareTo(b.orderKey);
    return orderCompare != 0 ? orderCompare : a.id.compareTo(b.id);
  }

  int _statusRank(db_schema.LabelRow row) {
    if (row.systemKey == db_schema.kanbanSystemKeyBacklog) {
      return 0;
    }
    if (row.systemKey == db_schema.kanbanSystemKeyDone) {
      return 2;
    }
    return 1;
  }

  bool _isProtectedRow(db_schema.LabelRow row) {
    return row.systemKey == db_schema.kanbanSystemKeyBacklog ||
        row.systemKey == db_schema.kanbanSystemKeyDone;
  }

  bool _isDoneRow(db_schema.LabelRow row) {
    return row.systemKey == db_schema.kanbanSystemKeyDone;
  }

  KanbanStatus _mapStatus(db_schema.LabelRow row) => KanbanStatus(
    id: row.id,
    userId: row.userId,
    name: row.name,
    color: row.color,
    orderKey: row.orderKey,
    systemKey: _parseSystemKey(row.systemKey),
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  KanbanSettings _mapSettings(db_schema.KanbanSettingsRow row) {
    return KanbanSettings(
      id: row.id,
      userId: row.userId,
      selectedProjectIds: _decodeProjectIds(row.selectedProjectIdsJson),
      focusStatusLabelId: row.focusStatusLabelId,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  ProjectItem _mapProject(db_schema.ProjectRow row) => ProjectItem(
    id: row.id,
    userId: row.userId,
    name: row.name,
    color: row.color,
    parentId: row.parentId,
    viewStyle: row.viewStyle,
    isFavorite: row.isFavorite,
    isArchived: row.isArchived,
    isDeleted: row.isDeleted,
    orderKey: row.orderKey,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  TaskItem _mapTask(db_schema.TaskRow row) => TaskItem(
    id: row.id,
    userId: row.userId,
    content: row.content,
    description: row.description,
    projectId: row.projectId,
    sectionId: row.sectionId,
    parentId: row.parentId,
    priority: row.priority,
    dueJson: row.dueJson,
    deadlineJson: row.deadlineJson,
    durationSeconds: row.durationSeconds,
    status: row.status,
    estimatedFocusIntervals: row.estimatedFocusIntervals,
    completedFocusIntervals: row.completedFocusIntervals,
    totalFocusSeconds: row.totalFocusSeconds,
    orderKey: row.orderKey,
    dayOrder: row.dayOrder,
    isCollapsed: row.isCollapsed,
    isDeleted: row.isDeleted,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    completedAt: row.completedAt,
  );

  KanbanSystemKey? _parseSystemKey(String? value) {
    for (final key in KanbanSystemKey.values) {
      if (key.name == value) {
        return key;
      }
    }
    return null;
  }

  List<String> _decodeProjectIds(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is List) {
        return decoded.whereType<String>().toSet().toList()..sort();
      }
    } on FormatException {
      // The database repair path replaces malformed settings before mapping.
    }
    return const [];
  }

  int _compareCardsByOrder(KanbanCard a, KanbanCard b) {
    final orderCompare = a.task.orderKey.compareTo(b.task.orderKey);
    return orderCompare != 0 ? orderCompare : a.task.id.compareTo(b.task.id);
  }
}

String _formatOrderValue(int value) {
  return value.toString().padLeft(_orderKeyWidth, '0');
}
