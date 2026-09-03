import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/sync/sync_queue_repository.dart';
import '../domain/project_colors.dart';
import '../domain/task_models.dart';
import 'kanban_transition_coordinator.dart';

class DriftTaskRepository implements TaskRepository {
  static const _deleteUndoWindow = Duration(seconds: 7);

  DriftTaskRepository(
    this._db,
    this._syncQueue, {
    Uuid? uuid,
    KanbanTransitionCoordinator? kanbanTransitions,
    void Function()? onUserTaskCreated,
  }) : _uuid = uuid ?? const Uuid(),
       _kanbanTransitions =
           kanbanTransitions ??
           KanbanTransitionCoordinator(_db, _syncQueue, uuid: uuid),
       _onUserTaskCreated = onUserTaskCreated;

  final AppDatabase _db;
  final SyncQueueRepository _syncQueue;
  final Uuid _uuid;
  final KanbanTransitionCoordinator _kanbanTransitions;
  final void Function()? _onUserTaskCreated;

  @override
  Stream<List<TaskItem>> watchTasks(TaskQuery query) {
    final statement = _db.select(_db.tasks)
      ..where((task) => task.isDeleted.equals(false));
    return statement.watch().map((rows) {
      final tasks = rows
          .map(_mapTask)
          .where((task) => _matchesQuery(task, query))
          .toList();
      tasks.sort((a, b) {
        final dayOrderCompare = (a.dayOrder ?? 999999).compareTo(
          b.dayOrder ?? 999999,
        );
        if (dayOrderCompare != 0) {
          return dayOrderCompare;
        }
        return a.orderKey.compareTo(b.orderKey);
      });
      return tasks;
    });
  }

  @override
  Stream<TaskItem?> watchTask(String id) {
    final statement = _db.select(_db.tasks)
      ..where((task) => task.id.equals(id));
    return statement.watchSingleOrNull().map(
      (row) => row == null ? null : _mapTask(row),
    );
  }

  @override
  Future<String> createTask(CreateTaskInput input) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();
    final projectId = input.projectId ?? inboxProjectId;
    final schedule =
        input.schedule ??
        (input.dueDate == null ? null : TaskSchedule.allDay(input.dueDate!));
    final durationSeconds =
        input.durationSeconds ?? schedule?.duration?.inSeconds;
    await _db.transaction(() async {
      await _db
          .into(_db.tasks)
          .insert(
            TasksCompanion.insert(
              id: id,
              userId: localUserId,
              content: input.content,
              description: Value(input.description),
              projectId: projectId,
              sectionId: Value(input.sectionId),
              parentId: Value(input.parentId),
              priority: Value(input.priority ?? 4),
              dueJson: Value(_scheduleJson(schedule)),
              deadlineJson: Value(_dateJson(input.deadline)),
              durationSeconds: Value(durationSeconds),
              estimatedFocusIntervals: Value(input.estimatedFocusIntervals),
              orderKey: _orderKey(now),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _kanbanTransitions.assignInitialStatusInTransaction(
        taskId: id,
        requestedStatusId: input.kanbanStatusId,
        timestamp: now,
        precedingCommands: [
          SyncQueueCommand(
            type: 'task.create',
            clientId: id,
            payload: {
              'id': id,
              'content': input.content,
              if (input.description != null) 'description': input.description,
              'projectId': projectId,
              'priority': input.priority ?? 4,
              'due': schedule?.toJsonString(),
              'estimatedFocusIntervals': input.estimatedFocusIntervals,
            },
          ),
        ],
      );
      await _attachLabels(id, input.labelNames, now);
    });
    _onUserTaskCreated?.call();
    return id;
  }

  @override
  Future<List<String>> duplicateTasks(
    Set<String> taskIds, {
    required bool includeSubtasks,
  }) async {
    if (taskIds.isEmpty) {
      return const [];
    }
    final duplicateIds = <String>[];
    await _db.transaction(() async {
      final rows = await (_db.select(
        _db.tasks,
      )..where((task) => task.isDeleted.equals(false))).get();
      final rowById = _rowById(rows);
      final selectedIds = taskIds.where(rowById.containsKey).toSet();
      if (includeSubtasks) {
        final childrenByParent = _childrenByParent(rows);
        for (final id in taskIds) {
          final root = rowById[id];
          if (root != null) {
            selectedIds.addAll(
              _subtreeRowsFrom(root, childrenByParent).map((row) => row.id),
            );
          }
        }
      }
      final sources =
          [
            for (final row in rows)
              if (selectedIds.contains(row.id)) row,
          ]..sort((left, right) {
            final order = left.orderKey.compareTo(right.orderKey);
            return order == 0 ? left.id.compareTo(right.id) : order;
          });
      final idBySource = {for (final row in sources) row.id: _uuid.v4()};
      final seriesIdBySource = <String, String>{};
      final now = DateTime.now().toUtc();

      for (var index = 0; index < sources.length; index++) {
        final source = sources[index];
        final duplicateId = idBySource[source.id]!;
        final schedule = _duplicateSchedule(
          TaskSchedule.fromJsonString(source.dueJson),
          seriesIdBySource,
        );
        final parentId = idBySource[source.parentId] ?? source.parentId;
        final orderKey = (now.microsecondsSinceEpoch + index)
            .toString()
            .padLeft(20, '0');
        await _db
            .into(_db.tasks)
            .insert(
              TasksCompanion.insert(
                id: duplicateId,
                userId: source.userId,
                content: source.content,
                description: Value(source.description),
                projectId: source.projectId,
                sectionId: Value(source.sectionId),
                parentId: Value(parentId),
                priority: Value(source.priority),
                dueJson: Value(_scheduleJson(schedule)),
                deadlineJson: Value(source.deadlineJson),
                durationSeconds: Value(source.durationSeconds),
                estimatedFocusIntervals: Value(source.estimatedFocusIntervals),
                orderKey: orderKey,
                dayOrder: Value(source.dayOrder),
                isCollapsed: Value(source.isCollapsed),
                createdAt: now,
                updatedAt: now,
              ),
            );
        await _kanbanTransitions.copyRecurringStatusInTransaction(
          sourceTaskId: source.id,
          newTaskId: duplicateId,
          timestamp: now,
          precedingCommands: [
            SyncQueueCommand(
              type: 'task.create',
              clientId: duplicateId,
              payload: {
                'id': duplicateId,
                'content': source.content,
                if (source.description != null)
                  'description': source.description,
                'projectId': source.projectId,
                'priority': source.priority,
                'due': schedule?.toJsonString(),
                'estimatedFocusIntervals': source.estimatedFocusIntervals,
              },
            ),
          ],
        );
        await _syncQueue.enqueue(
          type: 'task.move',
          clientId: duplicateId,
          payload: {
            'id': duplicateId,
            'projectId': source.projectId,
            'sectionId': source.sectionId,
            'parentId': parentId,
            'orderKey': orderKey,
          },
        );
        duplicateIds.add(duplicateId);
      }
      await _copyLabels(
        sourceTaskIds: idBySource.keys,
        idBySource: idBySource,
        now: now,
      );
    });
    return duplicateIds;
  }

  @override
  Future<void> updateTask(String id, UpdateTaskPatch patch) async {
    final now = DateTime.now().toUtc();
    final schedule =
        patch.schedule ??
        (patch.dueDate == null ? null : TaskSchedule.allDay(patch.dueDate!));
    await _db.transaction(() async {
      await (_db.update(_db.tasks)..where((task) => task.id.equals(id))).write(
        TasksCompanion(
          content: patch.content == null
              ? const Value.absent()
              : Value(patch.content!),
          description: patch.updateDescription
              ? Value(patch.description)
              : const Value.absent(),
          priority: patch.priority == null
              ? const Value.absent()
              : Value(patch.priority!),
          dueJson: patch.clearSchedule
              ? const Value(null)
              : schedule == null
              ? const Value.absent()
              : Value(_scheduleJson(schedule)),
          durationSeconds: patch.clearSchedule || schedule != null
              ? Value(schedule?.duration?.inSeconds)
              : const Value.absent(),
          estimatedFocusIntervals: patch.estimatedFocusIntervals == null
              ? const Value.absent()
              : Value(patch.estimatedFocusIntervals),
          isCollapsed: patch.isCollapsed == null
              ? const Value.absent()
              : Value(patch.isCollapsed!),
          updatedAt: Value(now),
        ),
      );
      if (patch.labelNames != null) {
        await _attachLabels(id, patch.labelNames!, now);
      }
      await _syncQueue.enqueue(
        type: 'task.update',
        clientId: id,
        payload: {
          'id': id,
          if (patch.content != null) 'content': patch.content,
          if (patch.updateDescription) 'description': patch.description,
          if (patch.priority != null) 'priority': patch.priority,
          if (patch.clearSchedule)
            'due': null
          else if (schedule != null)
            'due': schedule.toJsonString(),
          if (patch.clearSchedule || schedule != null)
            'durationSeconds': schedule?.duration?.inSeconds,
          if (patch.estimatedFocusIntervals != null)
            'estimatedFocusIntervals': patch.estimatedFocusIntervals,
          if (patch.isCollapsed != null) 'isCollapsed': patch.isCollapsed,
        },
      );
    });
  }

  @override
  Future<void> materializeDueRecurringTasks({DateTime? now}) async {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final localNow = timestamp.toLocal();
    await _db.transaction(() async {
      final rows = await (_db.select(
        _db.tasks,
      )..where((task) => task.isDeleted.equals(false))).get();
      final rowById = {for (final row in rows) row.id: row};
      final childrenByParent = _childrenByParent(rows);

      for (final row in rows) {
        final schedule = TaskSchedule.fromJsonString(row.dueJson);
        final recurrence = schedule?.recurrence;
        if (schedule == null || recurrence == null) {
          continue;
        }
        if (!_shouldMaterialize(row, schedule, localNow)) {
          continue;
        }

        final advanceFirst =
            row.status == 'completed' &&
            schedule.occurrenceStartLocal.isAfter(localNow);
        await _stripRecurrence(row, schedule, timestamp);
        await _createNextRecurringOccurrence(
          row: row,
          schedule: schedule,
          recurrence: recurrence,
          localNow: localNow,
          timestamp: timestamp,
          rowById: rowById,
          childrenByParent: childrenByParent,
          advanceFirst: advanceFirst,
        );
      }
    });
  }

  @override
  Future<void> moveTask(
    String id, {
    String? projectId,
    String? sectionId,
    bool clearSectionId = false,
    String? parentId,
    bool clearParentId = false,
    String? orderKey,
  }) async {
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      final rows = await (_db.select(
        _db.tasks,
      )..where((task) => task.isDeleted.equals(false))).get();
      final rowById = {for (final row in rows) row.id: row};
      final task = rowById[id];
      if (task == null) {
        return;
      }
      if (parentId == id ||
          (parentId != null && _hasAncestor(parentId, id, rowById))) {
        throw ArgumentError.value(
          parentId,
          'parentId',
          'Cannot move a task into itself',
        );
      }

      final subtree = _subtreeRows(id, rows);
      final updateSection = clearSectionId || sectionId != null;
      final updateParent = clearParentId || parentId != null;
      for (final row in subtree) {
        final isRoot = row.id == id;
        final nextProjectId = projectId ?? row.projectId;
        final nextSectionId = updateSection
            ? (clearSectionId ? null : sectionId)
            : row.sectionId;
        final nextParentId = isRoot
            ? (updateParent ? (clearParentId ? null : parentId) : row.parentId)
            : row.parentId;
        final nextOrderKey = isRoot && orderKey != null
            ? orderKey
            : row.orderKey;
        if (nextProjectId == row.projectId &&
            nextSectionId == row.sectionId &&
            nextParentId == row.parentId &&
            nextOrderKey == row.orderKey) {
          continue;
        }
        await (_db.update(
          _db.tasks,
        )..where((task) => task.id.equals(row.id))).write(
          TasksCompanion(
            projectId: Value(nextProjectId),
            sectionId: Value(nextSectionId),
            parentId: Value(nextParentId),
            orderKey: Value(nextOrderKey),
            updatedAt: Value(now),
          ),
        );
        await _syncQueue.enqueue(
          type: 'task.move',
          clientId: row.id,
          payload: {
            'id': row.id,
            if (nextProjectId != row.projectId) 'projectId': nextProjectId,
            if (nextSectionId != row.sectionId) 'sectionId': nextSectionId,
            if (nextParentId != row.parentId) 'parentId': nextParentId,
            if (nextOrderKey != row.orderKey) 'orderKey': nextOrderKey,
          },
        );
      }
    });
  }

  @override
  Future<void> placeTaskOnTimeline(
    String id, {
    required TaskSchedule schedule,
    required String projectId,
  }) async {
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      final rows = await (_db.select(
        _db.tasks,
      )..where((task) => task.isDeleted.equals(false))).get();
      final rowById = {for (final row in rows) row.id: row};
      final root = rowById[id];
      if (root == null) {
        return;
      }
      final projectChanged = root.projectId != projectId;
      final rootParent = root.parentId == null ? null : rowById[root.parentId];
      final detachRootFromParent =
          projectChanged &&
          root.parentId != null &&
          rootParent?.projectId != projectId;
      for (final row in _subtreeRows(id, rows)) {
        final isRoot = row.id == id;
        final nextSectionId = projectChanged ? null : row.sectionId;
        final nextParentId = detachRootFromParent && isRoot
            ? null
            : row.parentId;
        await (_db.update(
          _db.tasks,
        )..where((task) => task.id.equals(row.id))).write(
          TasksCompanion(
            projectId: Value(projectId),
            sectionId: Value(nextSectionId),
            parentId: Value(nextParentId),
            dueJson: isRoot
                ? Value(_scheduleJson(schedule))
                : const Value.absent(),
            durationSeconds: isRoot
                ? Value(schedule.duration?.inSeconds)
                : const Value.absent(),
            updatedAt: Value(now),
          ),
        );
        if (projectChanged) {
          await _syncQueue.enqueue(
            type: 'task.move',
            clientId: row.id,
            payload: {
              'id': row.id,
              'projectId': projectId,
              'sectionId': nextSectionId,
              'parentId': nextParentId,
              'orderKey': row.orderKey,
            },
          );
        }
      }
      await _syncQueue.enqueue(
        type: 'task.update',
        clientId: id,
        payload: {
          'id': id,
          'due': schedule.toJsonString(),
          'durationSeconds': schedule.duration?.inSeconds,
        },
      );
    });
  }

  @override
  Future<void> completeTask(String id) async {
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await _kanbanTransitions.completeSubtreeInTransaction(id, timestamp: now);
    });
  }

  @override
  Future<void> uncompleteTask(String id) async {
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await _kanbanTransitions.restoreSubtreeInTransaction(id, timestamp: now);
    });
  }

  @override
  Future<DeletedTaskBatch> deleteTask(String id) => deleteTasks({id});

  @override
  Future<DeletedTaskBatch> deleteTasks(Set<String> ids) async {
    final now = DateTime.now().toUtc();
    final undoUntil = DateTime.fromMillisecondsSinceEpoch(
      (now.add(_deleteUndoWindow).millisecondsSinceEpoch ~/ 1000) * 1000,
      isUtc: true,
    );
    final deletedIds = <String>{};
    await _db.transaction(() async {
      final rows = await (_db.select(
        _db.tasks,
      )..where((task) => task.isDeleted.equals(false))).get();
      final childrenByParent = _childrenByParent(rows);
      final rowById = _rowById(rows);
      final targets = <TaskRow>[];
      for (final id in ids) {
        final row = rowById[id];
        if (row != null) {
          targets.addAll(_subtreeRowsFrom(row, childrenByParent));
        }
      }
      deletedIds.addAll(
        await _deleteRows(targets, now, availableAt: undoUntil),
      );
    });
    return DeletedTaskBatch(taskIds: deletedIds, undoUntil: undoUntil);
  }

  @override
  Future<DeletedTaskBatch> deleteRecurringOccurrence(
    String id, {
    required bool includeFollowing,
  }) async {
    final now = DateTime.now().toUtc();
    final localNow = now.toLocal();
    final undoUntil = DateTime.fromMillisecondsSinceEpoch(
      (now.add(_deleteUndoWindow).millisecondsSinceEpoch ~/ 1000) * 1000,
      isUtc: true,
    );
    final deletedIds = <String>{};
    await _db.transaction(() async {
      final rows = await (_db.select(
        _db.tasks,
      )..where((task) => task.isDeleted.equals(false))).get();
      final rowById = _rowById(rows);
      final selected = rowById[id];
      if (selected == null) {
        return;
      }
      final childrenByParent = _childrenByParent(rows);
      final selectedSchedule = TaskSchedule.fromJsonString(selected.dueJson);
      final seriesId = selectedSchedule?.recurrenceSeriesKey;
      if (selectedSchedule == null || seriesId == null) {
        deletedIds.addAll(
          await _deleteRows(
            _subtreeRowsFrom(selected, childrenByParent),
            now,
            availableAt: undoUntil,
          ),
        );
        return;
      }

      if (!includeFollowing) {
        final recurrence = selectedSchedule.recurrence;
        if (recurrence != null) {
          await _createNextRecurringOccurrence(
            row: selected,
            schedule: selectedSchedule,
            recurrence: recurrence,
            localNow: localNow,
            timestamp: now,
            rowById: rowById,
            childrenByParent: childrenByParent,
            advanceFirst: true,
          );
        }
        deletedIds.addAll(
          await _deleteRows(
            _subtreeRowsFrom(selected, childrenByParent),
            now,
            availableAt: undoUntil,
          ),
        );
        return;
      }

      final selectedStart = selectedSchedule.occurrenceStartLocal;
      final targets =
          rows.where((row) {
            final schedule = TaskSchedule.fromJsonString(row.dueJson);
            if (schedule == null || schedule.recurrenceSeriesKey != seriesId) {
              return false;
            }
            return !schedule.occurrenceStartLocal.isBefore(selectedStart);
          }).toList()..sort(
            (a, b) => TaskSchedule.fromJsonString(a.dueJson)!
                .occurrenceStartLocal
                .compareTo(
                  TaskSchedule.fromJsonString(b.dueJson)!.occurrenceStartLocal,
                ),
          );
      for (final row in targets) {
        deletedIds.addAll(
          await _deleteRows(
            _subtreeRowsFrom(row, childrenByParent),
            now,
            availableAt: undoUntil,
          ),
        );
      }
    });
    return DeletedTaskBatch(taskIds: deletedIds, undoUntil: undoUntil);
  }

  @override
  Future<bool> restoreDeletedTasks(DeletedTaskBatch batch) async {
    if (batch.taskIds.isEmpty ||
        DateTime.now().toUtc().isAfter(batch.undoUntil)) {
      return false;
    }
    return _db.transaction(() async {
      final deletedRows =
          await (_db.select(_db.tasks)..where(
                (row) =>
                    row.id.isIn(batch.taskIds) & row.isDeleted.equals(true),
              ))
              .get();
      final commands =
          await (_db.select(_db.syncCommands)..where(
                (row) =>
                    row.type.equals('task.delete') &
                    row.status.equals('pending') &
                    row.attempts.equals(0) &
                    row.clientId.isIn(batch.taskIds) &
                    row.availableAt.equals(batch.undoUntil),
              ))
              .get();
      final commandTaskIds = commands
          .map((command) => command.clientId)
          .whereType<String>()
          .toSet();
      if (commandTaskIds.length != batch.taskIds.length) {
        return false;
      }
      await _removeRecurringCopiesCreatedForDelete(deletedRows, batch);
      await (_db.delete(
            _db.syncCommands,
          )..where((row) => row.id.isIn(commands.map((command) => command.id))))
          .go();
      await (_db.update(_db.tasks)..where(
            (row) => row.id.isIn(batch.taskIds) & row.isDeleted.equals(true),
          ))
          .write(
            TasksCompanion(
              isDeleted: const Value(false),
              updatedAt: Value(DateTime.now().toUtc()),
            ),
          );
      return true;
    });
  }

  Future<void> _removeRecurringCopiesCreatedForDelete(
    List<TaskRow> deletedRows,
    DeletedTaskBatch batch,
  ) async {
    final windowStart = batch.undoUntil.subtract(_deleteUndoWindow);
    for (final row in deletedRows) {
      final schedule = TaskSchedule.fromJsonString(row.dueJson);
      final recurrence = schedule?.recurrence;
      if (schedule == null || recurrence == null) {
        continue;
      }
      final nextSchedule = schedule.nextOccurrenceAfter(
        DateTime.now(),
        advanceFirst: true,
      );
      final nextRootId = _recurringTaskId(
        recurrence,
        _occurrenceKey(nextSchedule),
        row.id,
      );
      final createdHere =
          await (_db.select(_db.syncCommands)..where(
                (command) =>
                    command.type.equals('task.create') &
                    command.clientId.equals(nextRootId) &
                    command.status.equals('pending') &
                    command.attempts.equals(0) &
                    command.updatedAt.isBiggerOrEqualValue(windowStart),
              ))
              .getSingleOrNull();
      if (createdHere == null) {
        continue;
      }
      final activeRows = await (_db.select(
        _db.tasks,
      )..where((task) => task.isDeleted.equals(false))).get();
      final nextRoot = _rowById(activeRows)[nextRootId];
      if (nextRoot == null) {
        continue;
      }
      final copyIds = _subtreeRowsFrom(
        nextRoot,
        _childrenByParent(activeRows),
      ).map((task) => task.id).toSet();
      await (_db.delete(
        _db.syncCommands,
      )..where((command) => command.clientId.isIn(copyIds))).go();
      await (_db.delete(
        _db.taskLabels,
      )..where((label) => label.taskId.isIn(copyIds))).go();
      await (_db.delete(
        _db.tasks,
      )..where((task) => task.id.isIn(copyIds))).go();
    }
  }

  @override
  Future<void> updateFocusAggregates(String id) async {
    final intervals =
        await (_db.select(_db.focusIntervals)..where(
              (interval) =>
                  interval.taskId.equals(id) &
                  interval.type.equals('work') &
                  interval.status.equals('completed') &
                  interval.isDeleted.equals(false),
            ))
            .get();
    var totalSeconds = 0;
    for (final interval in intervals) {
      final end = interval.completedAt ?? interval.startedAt;
      totalSeconds +=
          end.difference(interval.startedAt).inSeconds -
          interval.pausedTotalSeconds;
    }
    await (_db.update(_db.tasks)..where((task) => task.id.equals(id))).write(
      TasksCompanion(
        completedFocusIntervals: Value(intervals.length),
        totalFocusSeconds: Value(totalSeconds < 0 ? 0 : totalSeconds),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  @override
  Future<String> createTaskFromCalendar(RemoteCalendarTaskInput input) async {
    final id = _uuid.v4();
    final now = input.updatedAt.toUtc();
    await _db.transaction(() async {
      await _db
          .into(_db.tasks)
          .insert(
            TasksCompanion.insert(
              id: id,
              userId: localUserId,
              content: input.content,
              description: Value(input.description),
              projectId: inboxProjectId,
              priority: const Value(4),
              dueJson: Value(_scheduleJson(input.schedule)),
              durationSeconds: Value(input.schedule.duration?.inSeconds),
              status: const Value('open'),
              orderKey: _orderKey(now),
              createdAt: now,
              updatedAt: now,
              completedAt: const Value(null),
            ),
          );
      await _kanbanTransitions.assignInitialStatusInTransaction(
        taskId: id,
        requestedStatusId: null,
        timestamp: now,
        precedingCommands: [
          SyncQueueCommand(
            type: 'task.create',
            clientId: id,
            payload: {'id': id},
          ),
        ],
      );
      if (input.isCompleted) {
        await _kanbanTransitions.completeSubtreeInTransaction(
          id,
          timestamp: now,
        );
      }
    });
    return id;
  }

  @override
  Future<void> applyRemoteCalendarPatch(
    String id,
    RemoteCalendarTaskPatch patch,
  ) async {
    final updatedAt = patch.updatedAt.toUtc();
    await _db.transaction(() async {
      final existing = await (_db.select(
        _db.tasks,
      )..where((task) => task.id.equals(id))).getSingleOrNull();
      final existingSchedule = TaskSchedule.fromJsonString(existing?.dueJson);
      final existingRecurrence = existingSchedule?.recurrence;
      final existingSeriesId = existingSchedule?.recurrenceSeriesKey;
      final schedule = patch.schedule == null
          ? null
          : existingRecurrence != null
          ? patch.schedule!.withRecurrence(existingRecurrence)
          : patch.schedule!.withRecurrenceSeriesId(existingSeriesId);
      final companion = TasksCompanion(
        content: patch.content == null
            ? const Value.absent()
            : Value(patch.content!),
        description: patch.updateDescription
            ? Value(patch.description)
            : const Value.absent(),
        dueJson: schedule == null
            ? const Value.absent()
            : Value(_scheduleJson(schedule)),
        durationSeconds: schedule == null
            ? const Value.absent()
            : Value(schedule.duration?.inSeconds),
        isDeleted: patch.isDeleted == null
            ? const Value.absent()
            : Value(patch.isDeleted!),
        updatedAt: Value(updatedAt),
      );
      await (_db.update(
        _db.tasks,
      )..where((task) => task.id.equals(id))).write(companion);
      if (existing == null) {
        return;
      }
      if (patch.isDeleted == true) {
        await _syncQueue.enqueue(
          type: 'task.delete',
          clientId: id,
          payload: {'id': id},
        );
        return;
      }
      final completes =
          patch.isCompleted == true && existing.status != 'completed';
      final restores =
          patch.isCompleted == false && existing.status == 'completed';
      if (completes) {
        await _kanbanTransitions.completeSubtreeInTransaction(
          id,
          timestamp: updatedAt,
        );
      } else if (restores) {
        await _kanbanTransitions.restoreSubtreeInTransaction(
          id,
          timestamp: updatedAt,
        );
      } else {
        await _syncQueue.enqueue(
          type: 'task.update',
          clientId: id,
          payload: {
            'id': id,
            if (patch.content != null) 'content': patch.content,
            if (patch.updateDescription) 'description': patch.description,
            if (schedule != null) 'due': schedule.toJsonString(),
            if (schedule != null)
              'durationSeconds': schedule.duration?.inSeconds,
          },
        );
      }
    });
  }

  List<TaskRow> _subtreeRows(String rootId, List<TaskRow> rows) {
    final root = _rowById(rows)[rootId];
    if (root == null) {
      return const [];
    }
    return _subtreeRowsFrom(root, _childrenByParent(rows));
  }

  Map<String, TaskRow> _rowById(List<TaskRow> rows) {
    return {for (final row in rows) row.id: row};
  }

  Map<String, List<TaskRow>> _childrenByParent(List<TaskRow> rows) {
    final childrenByParent = <String, List<TaskRow>>{};
    for (final row in rows) {
      final parentId = row.parentId;
      if (parentId == null) {
        continue;
      }
      childrenByParent.putIfAbsent(parentId, () => []).add(row);
    }
    return childrenByParent;
  }

  List<TaskRow> _subtreeRowsFrom(
    TaskRow root,
    Map<String, List<TaskRow>> childrenByParent,
  ) {
    final result = <TaskRow>[];
    final stack = <TaskRow>[root];
    final seen = <String>{};
    while (stack.isNotEmpty) {
      final row = stack.removeLast();
      if (!seen.add(row.id)) {
        continue;
      }
      result.add(row);
      stack.addAll(childrenByParent[row.id] ?? const []);
    }
    return result;
  }

  bool _shouldMaterialize(
    TaskRow row,
    TaskSchedule schedule,
    DateTime localNow,
  ) {
    return row.status == 'completed' ||
        !schedule.occurrenceStartLocal.isAfter(localNow);
  }

  Future<void> _stripRecurrence(
    TaskRow row,
    TaskSchedule schedule,
    DateTime now,
  ) async {
    final nextDue = schedule
        .withoutRecurrence(keepSeriesId: true)
        .toJsonString();
    if (row.dueJson == nextDue) {
      return;
    }
    await (_db.update(_db.tasks)..where((task) => task.id.equals(row.id)))
        .write(TasksCompanion(dueJson: Value(nextDue), updatedAt: Value(now)));
    await _syncQueue.enqueue(
      type: 'task.update',
      clientId: row.id,
      payload: {
        'id': row.id,
        'due': nextDue,
        'durationSeconds': row.durationSeconds,
      },
    );
  }

  Future<void> _createNextRecurringOccurrence({
    required TaskRow row,
    required TaskSchedule schedule,
    required TaskRecurrence recurrence,
    required DateTime localNow,
    required DateTime timestamp,
    required Map<String, TaskRow> rowById,
    required Map<String, List<TaskRow>> childrenByParent,
    required bool advanceFirst,
  }) async {
    final nextSchedule = schedule.nextOccurrenceAfter(
      localNow,
      advanceFirst: advanceFirst,
    );
    final occurrenceKey = _occurrenceKey(nextSchedule);
    final nextRootId = _recurringTaskId(recurrence, occurrenceKey, row.id);
    if (rowById.containsKey(nextRootId) || await _taskExists(nextRootId)) {
      return;
    }

    final subtree = _subtreeRowsFrom(row, childrenByParent);
    final idBySource = {
      for (final source in subtree)
        source.id: _recurringTaskId(recurrence, occurrenceKey, source.id),
    };
    final delta = nextSchedule.occurrenceStartLocal.difference(
      schedule.occurrenceStartLocal,
    );

    for (final source in subtree) {
      final isRoot = source.id == row.id;
      final sourceSchedule = TaskSchedule.fromJsonString(source.dueJson);
      final copiedSchedule = isRoot
          ? nextSchedule
          : _shiftSchedule(sourceSchedule, delta)?.withoutRecurrence();
      await _db
          .into(_db.tasks)
          .insert(
            TasksCompanion.insert(
              id: idBySource[source.id]!,
              userId: source.userId,
              content: source.content,
              description: Value(source.description),
              projectId: source.projectId,
              sectionId: Value(source.sectionId),
              parentId: Value(
                isRoot
                    ? source.parentId
                    : idBySource[source.parentId] ?? source.parentId,
              ),
              priority: Value(source.priority),
              dueJson: Value(_scheduleJson(copiedSchedule)),
              deadlineJson: Value(source.deadlineJson),
              durationSeconds: Value(source.durationSeconds),
              estimatedFocusIntervals: Value(source.estimatedFocusIntervals),
              orderKey: source.orderKey,
              dayOrder: Value(source.dayOrder),
              isCollapsed: Value(source.isCollapsed),
              createdAt: timestamp,
              updatedAt: timestamp,
            ),
          );
      await _kanbanTransitions.copyRecurringStatusInTransaction(
        sourceTaskId: source.id,
        newTaskId: idBySource[source.id]!,
        timestamp: timestamp,
        precedingCommands: [
          SyncQueueCommand(
            type: 'task.create',
            clientId: idBySource[source.id],
            payload: {'id': idBySource[source.id]},
          ),
        ],
      );
    }

    await _copyLabels(
      sourceTaskIds: idBySource.keys,
      idBySource: idBySource,
      now: timestamp,
    );
  }

  Future<Set<String>> _deleteRows(
    Iterable<TaskRow> rows,
    DateTime now, {
    DateTime? availableAt,
  }) async {
    final uniqueRows = {for (final row in rows) row.id: row}.values;
    for (final row in uniqueRows) {
      await (_db.update(
        _db.tasks,
      )..where((task) => task.id.equals(row.id))).write(
        TasksCompanion(isDeleted: const Value(true), updatedAt: Value(now)),
      );
      await _syncQueue.enqueue(
        type: 'task.delete',
        clientId: row.id,
        payload: {'id': row.id},
        availableAt: availableAt,
      );
    }
    return uniqueRows.map((row) => row.id).toSet();
  }

  Future<bool> _taskExists(String id) async {
    return await (_db.select(
          _db.tasks,
        )..where((task) => task.id.equals(id))).getSingleOrNull() !=
        null;
  }

  Future<void> _copyLabels({
    required Iterable<String> sourceTaskIds,
    required Map<String, String> idBySource,
    required DateTime now,
  }) async {
    final rows =
        await (_db.select(_db.taskLabels)..where(
              (label) =>
                  label.taskId.isIn(sourceTaskIds) &
                  label.kind.equals(labelKindUser),
            ))
            .get();
    for (final row in rows) {
      final nextTaskId = idBySource[row.taskId];
      if (nextTaskId == null) {
        continue;
      }
      await _db
          .into(_db.taskLabels)
          .insertOnConflictUpdate(
            TaskLabelsCompanion.insert(
              taskId: nextTaskId,
              labelId: row.labelId,
              kind: const Value(labelKindUser),
              createdAt: now,
            ),
          );
      await _syncQueue.enqueue(
        type: 'task.label.add',
        clientId: nextTaskId,
        payload: {'taskId': nextTaskId, 'labelId': row.labelId},
      );
    }
  }

  TaskSchedule? _duplicateSchedule(
    TaskSchedule? schedule,
    Map<String, String> seriesIdBySource,
  ) {
    if (schedule == null) {
      return null;
    }
    final sourceSeriesId = schedule.recurrenceSeriesKey;
    if (sourceSeriesId == null) {
      return schedule;
    }
    final seriesId = seriesIdBySource.putIfAbsent(sourceSeriesId, _uuid.v4);
    final recurrence = schedule.recurrence;
    if (recurrence == null) {
      return schedule.withRecurrenceSeriesId(seriesId);
    }
    return schedule.withRecurrence(
      TaskRecurrence(
        interval: recurrence.interval,
        unit: recurrence.unit,
        seriesId: seriesId,
      ),
    );
  }

  TaskSchedule? _shiftSchedule(TaskSchedule? schedule, Duration delta) {
    if (schedule == null) {
      return null;
    }
    if (schedule.isAllDay) {
      return TaskSchedule.allDay(schedule.date!.add(delta));
    }
    return TaskSchedule.timed(
      start: schedule.start!.toLocal().add(delta),
      end: schedule.end!.toLocal().add(delta),
      timeZone: schedule.timeZone,
    );
  }

  String _occurrenceKey(TaskSchedule schedule) {
    if (schedule.isAllDay) {
      return _formatDate(schedule.date!);
    }
    return schedule.start!.toUtc().toIso8601String();
  }

  String _recurringTaskId(
    TaskRecurrence recurrence,
    String occurrenceKey,
    String sourceTaskId,
  ) {
    final input = '${recurrence.seriesId}|$occurrenceKey|$sourceTaskId';
    return 'rec-${sha1.convert(utf8.encode(input))}';
  }

  String _formatDate(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  bool _hasAncestor(
    String id,
    String ancestorId,
    Map<String, TaskRow> rowById,
  ) {
    var current = rowById[id]?.parentId;
    final seen = <String>{};
    while (current != null && seen.add(current)) {
      if (current == ancestorId) {
        return true;
      }
      current = rowById[current]?.parentId;
    }
    return false;
  }

  Future<void> _attachLabels(
    String taskId,
    List<String> labelNames,
    DateTime now,
  ) async {
    for (final rawName in labelNames) {
      final name = rawName.trim();
      if (name.isEmpty) {
        continue;
      }
      var existing =
          await (_db.select(_db.labels)
                ..where(
                  (label) =>
                      label.name.equals(name) &
                      label.kind.equals(labelKindUser) &
                      label.isDeleted.equals(false),
                )
                ..limit(1))
              .getSingleOrNull();
      existing ??=
          (await (_db.select(_db.labels)..where(
                    (label) =>
                        label.kind.equals(labelKindUser) &
                        label.isDeleted.equals(false),
                  ))
                  .get())
              .firstWhereOrNull(
                (label) =>
                    label.name.trim().toLowerCase() == name.toLowerCase(),
              );
      final labelId = existing?.id ?? _uuid.v4();
      if (existing == null) {
        await _db
            .into(_db.labels)
            .insert(
              LabelsCompanion.insert(
                id: labelId,
                userId: localUserId,
                name: name,
                kind: const Value(labelKindUser),
                orderKey: _orderKey(now),
                createdAt: now,
                updatedAt: now,
              ),
            );
        await _syncQueue.enqueue(
          type: 'label.create',
          clientId: labelId,
          payload: {'id': labelId, 'name': name},
        );
      }
      await _db
          .into(_db.taskLabels)
          .insertOnConflictUpdate(
            TaskLabelsCompanion.insert(
              taskId: taskId,
              labelId: labelId,
              kind: const Value(labelKindUser),
              createdAt: now,
            ),
          );
      await _syncQueue.enqueue(
        type: 'task.label.add',
        clientId: taskId,
        payload: {'taskId': taskId, 'labelId': labelId},
      );
    }
  }

  bool _matchesQuery(TaskItem task, TaskQuery query) {
    final now = query.now ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = task.dueDate;
    switch (query.kind) {
      case TaskQueryKind.inbox:
        return !task.isCompleted &&
            task.projectId == inboxProjectId &&
            due == null;
      case TaskQueryKind.today:
        return !task.isCompleted && due != null && !due.isAfter(today);
      case TaskQueryKind.upcoming:
        return !task.isCompleted && due != null && due.isAfter(today);
      case TaskQueryKind.day:
        final date = query.date ?? query.now ?? DateTime.now();
        final day = DateTime(date.year, date.month, date.day);
        return !task.isCompleted && due != null && due == day;
      case TaskQueryKind.project:
        return !task.isCompleted && task.projectId == query.projectId;
      case TaskQueryKind.search:
        final search = (query.search ?? '').trim().toLowerCase();
        if (search.isEmpty) {
          return !task.isCompleted;
        }
        return !task.isCompleted &&
            (task.content.toLowerCase().contains(search) ||
                (task.description ?? '').toLowerCase().contains(search));
      case TaskQueryKind.all:
        return !task.isCompleted;
      case TaskQueryKind.completed:
        return task.isCompleted;
    }
  }

  TaskItem _mapTask(TaskRow row) => TaskItem(
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

  String _orderKey(DateTime now) =>
      now.microsecondsSinceEpoch.toString().padLeft(20, '0');

  String? _dateJson(DateTime? value) {
    if (value == null) {
      return null;
    }
    final date = DateTime(value.year, value.month, value.day);
    return jsonEncode({'type': 'date', 'date': date.toIso8601String()});
  }

  String? _scheduleJson(TaskSchedule? value) {
    return value?.toJsonString();
  }
}

class DriftProjectRepository implements ProjectRepository {
  DriftProjectRepository(this._db, this._syncQueue, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final SyncQueueRepository _syncQueue;
  final Uuid _uuid;

  @override
  Stream<List<ProjectItem>> watchProjects() {
    final statement = _db.select(_db.projects)
      ..where((project) => project.isDeleted.equals(false))
      ..orderBy([(project) => OrderingTerm.asc(project.orderKey)]);
    return statement.watch().map((rows) => rows.map(_mapProject).toList());
  }

  @override
  Future<ProjectItem?> findByName(String name) async {
    final normalizedName = name.trim().toLowerCase();
    final row =
        (await (_db.select(
              _db.projects,
            )..where((project) => project.isDeleted.equals(false))).get())
            .firstWhereOrNull(
              (project) => project.name.trim().toLowerCase() == normalizedName,
            );
    return row == null ? null : _mapProject(row);
  }

  @override
  Future<String> createProject(String name, {String? color}) async {
    final existing = await findByName(name);
    if (existing != null) {
      return existing.id;
    }
    final projectRows = color == null
        ? await (_db.select(
            _db.projects,
          )..where((project) => project.isDeleted.equals(false))).get()
        : const <ProjectRow>[];
    final normalizedColor = color == null
        ? nextProjectColor(projectRows.map(_mapProject))
        : normalizeProjectColor(color);
    if (normalizedColor == null || !isPaletteProjectColor(normalizedColor)) {
      throw ArgumentError.value(color, 'color', 'Unsupported project color');
    }
    final now = DateTime.now().toUtc();
    final id = _uuid.v4();
    await _db.transaction(() async {
      await _db
          .into(_db.projects)
          .insert(
            ProjectsCompanion.insert(
              id: id,
              userId: localUserId,
              name: name.trim(),
              color: Value(normalizedColor),
              orderKey: now.microsecondsSinceEpoch.toString().padLeft(20, '0'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _syncQueue.enqueue(
        type: 'project.create',
        clientId: id,
        payload: {'id': id, 'name': name.trim(), 'color': normalizedColor},
      );
    });
    return id;
  }

  @override
  Future<void> updateProject(String id, UpdateProjectPatch patch) async {
    if (id == inboxProjectId) {
      throw ArgumentError.value(id, 'id', 'Inbox project cannot be changed');
    }
    final normalizedName = patch.name?.trim();
    if (patch.name != null && normalizedName!.isEmpty) {
      throw ArgumentError.value(
        patch.name,
        'patch.name',
        'Project name is empty',
      );
    }
    if (normalizedName != null) {
      final existing = await findByName(normalizedName);
      if (existing != null && existing.id != id) {
        throw ArgumentError.value(
          patch.name,
          'patch.name',
          'Project name already exists',
        );
      }
    }
    final normalizedColor = patch.color == null
        ? null
        : normalizeProjectColor(patch.color);
    if (patch.color != null &&
        (normalizedColor == null || !isPaletteProjectColor(normalizedColor))) {
      throw ArgumentError.value(
        patch.color,
        'patch.color',
        'Unsupported project color',
      );
    }
    if (normalizedName == null &&
        normalizedColor == null &&
        patch.isFavorite == null) {
      return;
    }
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await (_db.update(
        _db.projects,
      )..where((project) => project.id.equals(id))).write(
        ProjectsCompanion(
          name: normalizedName == null
              ? const Value.absent()
              : Value(normalizedName),
          color: normalizedColor == null
              ? const Value.absent()
              : Value(normalizedColor),
          isFavorite: patch.isFavorite == null
              ? const Value.absent()
              : Value(patch.isFavorite!),
          updatedAt: Value(now),
        ),
      );
      await _syncQueue.enqueue(
        type: 'project.update',
        clientId: id,
        payload: {
          'id': id,
          'name': ?normalizedName,
          'color': ?normalizedColor,
          'isFavorite': ?patch.isFavorite,
        },
      );
    });
  }

  @override
  Future<void> deleteProject(String id) async {
    if (id == inboxProjectId) {
      return;
    }
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      final project =
          await (_db.select(_db.projects)
                ..where(
                  (project) =>
                      project.id.equals(id) & project.isDeleted.equals(false),
                )
                ..limit(1))
              .getSingleOrNull();
      if (project == null) {
        return;
      }

      final tasks =
          await (_db.select(_db.tasks)..where(
                (task) =>
                    task.projectId.equals(id) & task.isDeleted.equals(false),
              ))
              .get();
      for (final task in tasks) {
        await (_db.update(
          _db.tasks,
        )..where((row) => row.id.equals(task.id))).write(
          TasksCompanion(
            projectId: const Value(inboxProjectId),
            sectionId: const Value(null),
            updatedAt: Value(now),
          ),
        );
        await _syncQueue.enqueue(
          type: 'task.move',
          clientId: task.id,
          payload: {
            'id': task.id,
            'projectId': inboxProjectId,
            'sectionId': null,
            'parentId': task.parentId,
            'orderKey': task.orderKey,
          },
        );
      }

      final settingsBefore = await (_db.select(
        _db.kanbanSettings,
      )..where((row) => row.id.equals(kanbanSettingsPrimaryId))).getSingle();
      await (_db.update(
        _db.projects,
      )..where((project) => project.id.equals(id))).write(
        ProjectsCompanion(isDeleted: const Value(true), updatedAt: Value(now)),
      );
      await _db.repairKanbanSettings(now: now);
      final settingsAfter = await (_db.select(
        _db.kanbanSettings,
      )..where((row) => row.id.equals(kanbanSettingsPrimaryId))).getSingle();
      await _syncQueue.enqueueBatch([
        SyncQueueCommand(
          type: 'project.delete',
          clientId: id,
          payload: {'id': id},
        ),
        if (settingsBefore.selectedProjectIdsJson !=
            settingsAfter.selectedProjectIdsJson)
          SyncQueueCommand(
            type: 'kanban.settings.projects.set',
            clientId: kanbanSettingsPrimaryId,
            payload: {
              'id': kanbanSettingsPrimaryId,
              'selectedProjectIdsJson': settingsAfter.selectedProjectIdsJson,
              'changedAt': now.toIso8601String(),
            },
          ),
        if (settingsBefore.focusStatusLabelId !=
            settingsAfter.focusStatusLabelId)
          SyncQueueCommand(
            type: 'kanban.settings.focus.set',
            clientId: kanbanSettingsPrimaryId,
            payload: {
              'id': kanbanSettingsPrimaryId,
              'focusStatusLabelId': settingsAfter.focusStatusLabelId,
              'changedAt': now.toIso8601String(),
            },
          ),
      ], occurredAt: now);
    });
  }

  ProjectItem _mapProject(ProjectRow row) => ProjectItem(
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
}

class DriftLabelRepository implements LabelRepository {
  DriftLabelRepository(this._db, this._syncQueue, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final SyncQueueRepository _syncQueue;
  final Uuid _uuid;

  @override
  Stream<List<LabelItem>> watchLabels() {
    final statement = _db.select(_db.labels)
      ..where(
        (label) =>
            label.kind.equals(labelKindUser) & label.isDeleted.equals(false),
      )
      ..orderBy([(label) => OrderingTerm.asc(label.orderKey)]);
    return statement.watch().map((rows) => rows.map(_mapLabel).toList());
  }

  @override
  Future<LabelItem?> findByName(String name) async {
    final normalizedName = name.trim().toLowerCase();
    final row =
        (await (_db.select(_db.labels)..where(
                  (label) =>
                      label.kind.equals(labelKindUser) &
                      label.isDeleted.equals(false),
                ))
                .get())
            .firstWhereOrNull(
              (label) => label.name.trim().toLowerCase() == normalizedName,
            );
    return row == null ? null : _mapLabel(row);
  }

  @override
  Future<String> createLabel(String name) async {
    final existing = await findByName(name);
    if (existing != null) {
      return existing.id;
    }
    final now = DateTime.now().toUtc();
    final id = _uuid.v4();
    await _db.transaction(() async {
      await _db
          .into(_db.labels)
          .insert(
            LabelsCompanion.insert(
              id: id,
              userId: localUserId,
              name: name.trim(),
              kind: const Value(labelKindUser),
              orderKey: now.microsecondsSinceEpoch.toString().padLeft(20, '0'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _syncQueue.enqueue(
        type: 'label.create',
        clientId: id,
        payload: {'id': id, 'name': name.trim()},
      );
    });
    return id;
  }

  @override
  Future<void> deleteLabel(String id) async {
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      final label =
          await (_db.select(_db.labels)
                ..where(
                  (label) =>
                      label.id.equals(id) &
                      label.kind.equals(labelKindUser) &
                      label.isDeleted.equals(false),
                )
                ..limit(1))
              .getSingleOrNull();
      if (label == null) {
        return;
      }
      await (_db.update(
        _db.labels,
      )..where((label) => label.id.equals(id))).write(
        LabelsCompanion(isDeleted: const Value(true), updatedAt: Value(now)),
      );
      await _syncQueue.enqueue(
        type: 'label.delete',
        clientId: id,
        payload: {'id': id},
      );
    });
  }

  LabelItem _mapLabel(LabelRow row) => LabelItem(
    id: row.id,
    userId: row.userId,
    name: row.name,
    color: row.color,
    orderKey: row.orderKey,
    isFavorite: row.isFavorite,
    isDeleted: row.isDeleted,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}
