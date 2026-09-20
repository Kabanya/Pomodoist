import 'package:pomodoist/utils/result.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository.dart';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/shared_access.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/data/repositories/local/kanban_transition_coordinator.dart';
import 'package:pomodoist/data/services/local/task_local_service.dart';
import 'package:pomodoist/data/services/local/task_repository_support.dart';

class DriftTaskRepository implements TaskRepository {
  static const _deleteUndoWindow = Duration(seconds: 7);

  DriftTaskRepository(
    AppDatabase db,
    this._syncQueue, {
    Uuid? uuid,
    KanbanTransitionCoordinator? kanbanTransitions,
  }) : _db = db,
       _uuid = uuid ?? const Uuid(),
       _tasks = TaskLocalService(db),
       _kanbanTransitions =
           kanbanTransitions ??
           KanbanTransitionCoordinator(db, _syncQueue, uuid: uuid);

  final AppDatabase _db;
  SharedAccess get _access => SharedAccess(_db);
  final OutboxService _syncQueue;
  final Uuid _uuid;
  final TaskLocalService _tasks;
  final KanbanTransitionCoordinator _kanbanTransitions;
  @override
  Stream<List<TaskItem>> watchTasks(TaskQuery query) {
    return _tasks.watchTasks(query).asyncMap((rows) async {
      final actorId = await _access.actorId();
      final tasks = rows
          .map(
            (row) => _mapTask(row.task, scope: sharedScopeFromRow(row.scope)),
          )
          .where(
            (task) =>
                !{
                  TaskQueryKind.today,
                  TaskQueryKind.upcoming,
                  TaskQueryKind.day,
                }.contains(query.kind) ||
                task.scopeId == null ||
                task.assigneeIds.contains(actorId),
          )
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
      return List<TaskItem>.unmodifiable(tasks);
    });
  }

  @override
  Stream<TaskItem?> watchTask(String id) {
    return _tasks
        .watchTask(id)
        .map(
          (row) => row == null
              ? null
              : _mapTask(row.task, scope: sharedScopeFromRow(row.scope)),
        );
  }

  @override
  Future<Result<String>> createTask(
    CreateTaskInput input,
  ) => Result.capture<String>(() async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();
    final projectId = input.projectId ?? inboxProjectId;
    final scopeId = await _access.projectScope(projectId);
    await _access.requireEdit(scopeId);
    await _access.taskLocation(
      projectId,
      parentId: input.parentId,
      sectionId: input.sectionId,
    );
    final creator = await _access.actorId();
    final schedule =
        input.schedule ??
        (input.dueDate == null ? null : TaskSchedule.allDay(input.dueDate!));
    final durationSeconds =
        input.durationSeconds ?? schedule?.duration?.inSeconds;
    await _db.transaction(() async {
      await _tasks.insertTask(
        TasksCompanion.insert(
          id: id,
          userId: localUserId,
          scopeId: Value(scopeId),
          createdBy: Value(creator),
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
      final contextLabelId = input.labelId;
      LabelRow? contextLabel;
      if (contextLabelId != null) {
        contextLabel = await _tasks.findUserLabel(contextLabelId);
        if (contextLabel == null) throw StateError('Label no longer exists');
      }
      if (contextLabel != null) await _attachLabel(id, contextLabel.id, now);
      await _attachLabels(
        id,
        input.labelNames
            .where(
              (name) =>
                  contextLabel == null ||
                  name.trim().toLowerCase() !=
                      contextLabel.name.trim().toLowerCase(),
            )
            .toList(),
        now,
      );
    });
    return id;
  });

  @override
  Future<Result<List<String>>> duplicateTasks(
    Set<String> taskIds, {
    required bool includeSubtasks,
  }) => Result.capture<List<String>>(() async {
    if (taskIds.isEmpty) {
      return const [];
    }
    for (final id in taskIds) {
      await _access.task(id);
    }
    final duplicateIds = <String>[];
    await _db.transaction(() async {
      final rows = await _tasks.activeTasks();
      final rowById = _tasks.rowById(rows);
      final selectedIds = taskIds.where(rowById.containsKey).toSet();
      if (includeSubtasks) {
        final childrenByParent = _tasks.childrenByParent(rows);
        for (final id in taskIds) {
          final root = rowById[id];
          if (root != null) {
            selectedIds.addAll(
              _tasks
                  .subtreeRowsFrom(root, childrenByParent)
                  .map((row) => row.id),
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
        await _tasks.insertTask(
          TasksCompanion.insert(
            id: duplicateId,
            userId: source.userId,
            scopeId: Value(source.scopeId),
            createdBy: Value(await _access.actorId()),
            assigneeIdsJson: Value(source.assigneeIdsJson),
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
  });

  @override
  Future<Result<void>> updateTask(String id, UpdateTaskPatch patch) =>
      Result.capture<void>(() async {
        if (patch.content != null ||
            patch.updateDescription ||
            patch.priority != null ||
            patch.dueDate != null ||
            patch.schedule != null ||
            patch.clearSchedule ||
            patch.estimatedFocusIntervals != null ||
            patch.labelNames != null) {
          await _access.task(id);
        }
        final now = DateTime.now().toUtc();
        final schedule =
            patch.schedule ??
            (patch.dueDate == null
                ? null
                : TaskSchedule.allDay(patch.dueDate!));
        await _db.transaction(() async {
          await _tasks.updateTask(
            id,
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
      });

  @override
  Future<Result<void>> materializeDueRecurringTasks({DateTime? now}) =>
      Result.capture<void>(() async {
        final timestamp = (now ?? DateTime.now()).toUtc();
        final localNow = timestamp.toLocal();
        await _db.transaction(() async {
          final rows = await _tasks.activeTasks();
          final rowById = _tasks.rowById(rows);
          final childrenByParent = _tasks.childrenByParent(rows);

          for (final row in rows) {
            if (row.scopeId != null &&
                !((await _access.scope(row.scopeId))?.canEdit ?? false)) {
              continue;
            }
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
      });

  @override
  Future<Result<void>> moveTask(
    String id, {
    String? projectId,
    String? sectionId,
    bool clearSectionId = false,
    String? parentId,
    bool clearParentId = false,
    String? orderKey,
  }) => Result.capture<void>(() async {
    await _access.task(id, destinationProjectId: projectId);
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      final rows = await _tasks.activeTasks();
      final rowById = _tasks.rowById(rows);
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

      await _access.taskLocation(
        projectId ?? task.projectId,
        parentId: clearParentId ? null : parentId ?? task.parentId,
        sectionId:
            clearSectionId || projectId != null && projectId != task.projectId
            ? sectionId
            : sectionId ?? task.sectionId,
      );
      final subtree = _tasks.subtreeRows(id, rows);
      final updateSection = clearSectionId || sectionId != null;
      final updateParent = clearParentId || parentId != null;
      for (final row in subtree) {
        final isRoot = row.id == id;
        final nextProjectId = projectId ?? row.projectId;
        final nextSectionId = updateSection
            ? (clearSectionId ? null : sectionId)
            : nextProjectId != row.projectId
            ? null
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
        await _tasks.updateTask(
          row.id,
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
  });

  @override
  Future<Result<void>> placeTaskOnTimeline(
    String id, {
    required TaskSchedule schedule,
    required String projectId,
  }) => Result.capture<void>(() async {
    await _access.task(id, destinationProjectId: projectId);
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      final rows = await _tasks.activeTasks();
      final rowById = _tasks.rowById(rows);
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
      for (final row in _tasks.subtreeRows(id, rows)) {
        final isRoot = row.id == id;
        final nextSectionId = projectChanged ? null : row.sectionId;
        final nextParentId = detachRootFromParent && isRoot
            ? null
            : row.parentId;
        await _tasks.updateTask(
          row.id,
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
  });

  @override
  Future<Result<void>> completeTask(String id) =>
      Result.capture<void>(() async {
        await _access.task(id);
        final now = DateTime.now().toUtc();
        await _db.transaction(() async {
          await _kanbanTransitions.completeSubtreeInTransaction(
            id,
            timestamp: now,
          );
        });
      });

  @override
  Future<Result<void>> uncompleteTask(String id) =>
      Result.capture<void>(() async {
        await _access.task(id);
        final now = DateTime.now().toUtc();
        await _db.transaction(() async {
          await _kanbanTransitions.restoreSubtreeInTransaction(
            id,
            timestamp: now,
          );
        });
      });

  @override
  Future<Result<DeletedTaskBatch>> deleteTask(String id) =>
      Result.capture<DeletedTaskBatch>(
        () async => deleteTasks({id}).then((result) => result.getOrThrow()),
      );

  @override
  Future<Result<DeletedTaskBatch>> deleteTasks(Set<String> ids) =>
      Result.capture<DeletedTaskBatch>(() async {
        for (final id in ids) {
          await _access.task(id);
        }
        final now = DateTime.now().toUtc();
        final undoUntil = DateTime.fromMillisecondsSinceEpoch(
          (now.add(_deleteUndoWindow).millisecondsSinceEpoch ~/ 1000) * 1000,
          isUtc: true,
        );
        final deletedIds = <String>{};
        await _db.transaction(() async {
          final rows = await _tasks.activeTasks();
          final childrenByParent = _tasks.childrenByParent(rows);
          final rowById = _tasks.rowById(rows);
          final targets = <TaskRow>[];
          for (final id in ids) {
            final row = rowById[id];
            if (row != null) {
              targets.addAll(_tasks.subtreeRowsFrom(row, childrenByParent));
            }
          }
          deletedIds.addAll(
            await _deleteRows(targets, now, availableAt: undoUntil),
          );
        });
        return DeletedTaskBatch(taskIds: deletedIds, undoUntil: undoUntil);
      });

  @override
  Future<Result<DeletedTaskBatch>> deleteRecurringOccurrence(
    String id, {
    required bool includeFollowing,
  }) => Result.capture<DeletedTaskBatch>(() async {
    await _access.task(id);
    final now = DateTime.now().toUtc();
    final localNow = now.toLocal();
    final undoUntil = DateTime.fromMillisecondsSinceEpoch(
      (now.add(_deleteUndoWindow).millisecondsSinceEpoch ~/ 1000) * 1000,
      isUtc: true,
    );
    final deletedIds = <String>{};
    await _db.transaction(() async {
      final rows = await _tasks.activeTasks();
      final rowById = _tasks.rowById(rows);
      final selected = rowById[id];
      if (selected == null) {
        return;
      }
      final childrenByParent = _tasks.childrenByParent(rows);
      final selectedSchedule = TaskSchedule.fromJsonString(selected.dueJson);
      final seriesId = selectedSchedule?.recurrenceSeriesKey;
      if (selectedSchedule == null || seriesId == null) {
        deletedIds.addAll(
          await _deleteRows(
            _tasks.subtreeRowsFrom(selected, childrenByParent),
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
            _tasks.subtreeRowsFrom(selected, childrenByParent),
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
            _tasks.subtreeRowsFrom(row, childrenByParent),
            now,
            availableAt: undoUntil,
          ),
        );
      }
    });
    return DeletedTaskBatch(taskIds: deletedIds, undoUntil: undoUntil);
  });

  @override
  Future<Result<bool>> restoreDeletedTasks(DeletedTaskBatch batch) =>
      Result.capture<bool>(() async {
        for (final id in batch.taskIds) {
          await _access.task(id);
        }
        if (batch.taskIds.isEmpty ||
            DateTime.now().toUtc().isAfter(batch.undoUntil)) {
          return false;
        }
        return _db.transaction(() async {
          final deletedRows = await _tasks.deletedTasks(batch.taskIds);
          final commands = await _tasks.pendingDeleteCommands(
            batch.taskIds,
            batch.undoUntil,
          );
          final commandTaskIds = commands
              .map((command) => command.clientId)
              .whereType<String>()
              .toSet();
          if (commandTaskIds.length != batch.taskIds.length) {
            return false;
          }
          await _removeRecurringCopiesCreatedForDelete(deletedRows, batch);
          await _tasks.deleteCommands(commands.map((command) => command.id));
          await _tasks.restoreTasks(batch.taskIds, DateTime.now().toUtc());
          return true;
        });
      });

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
      final createdHere = await _tasks.pendingCreateCommand(
        nextRootId,
        windowStart,
      );
      if (createdHere == null) {
        continue;
      }
      final activeRows = await _tasks.activeTasks();
      final nextRoot = _tasks.rowById(activeRows)[nextRootId];
      if (nextRoot == null) {
        continue;
      }
      final copyIds = _tasks
          .subtreeRowsFrom(nextRoot, _tasks.childrenByParent(activeRows))
          .map((task) => task.id)
          .toSet();
      await _tasks.deleteCommandsByClientIds(copyIds);
      await _tasks.deleteTaskLabels(copyIds);
      await _tasks.deleteTaskRows(copyIds);
    }
  }

  @override
  Future<Result<void>> updateFocusAggregates(String id) =>
      Result.capture<void>(() async {
        final intervals = await _tasks.completedWorkIntervals(id);
        final totalSeconds = intervals.fold<int>(
          0,
          (total, interval) =>
              total +
              (interval.completedAt ?? interval.startedAt)
                  .difference(interval.startedAt)
                  .inSeconds -
              interval.pausedTotalSeconds,
        );
        await _tasks.updateTask(
          id,
          TasksCompanion(
            completedFocusIntervals: Value(intervals.length),
            totalFocusSeconds: Value(totalSeconds < 0 ? 0 : totalSeconds),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
      });

  @override
  Future<Result<String>> createTaskFromCalendar(
    RemoteCalendarTaskInput input,
  ) => Result.capture<String>(() async {
    final id = _uuid.v4();
    final now = input.updatedAt.toUtc();
    await _db.transaction(() async {
      await _tasks.insertTask(
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
  });

  @override
  Future<Result<void>> applyRemoteCalendarPatch(
    String id,
    RemoteCalendarTaskPatch patch,
  ) => Result.capture<void>(() async {
    final updatedAt = patch.updatedAt.toUtc();
    await _db.transaction(() async {
      final existing = await _tasks.findTask(id);
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
      await _tasks.updateTask(id, companion);
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
  });

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
    await _tasks.updateTask(
      row.id,
      TasksCompanion(dueJson: Value(nextDue), updatedAt: Value(now)),
    );
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
    if (rowById.containsKey(nextRootId) ||
        await _tasks.findTask(nextRootId) != null) {
      return;
    }

    final subtree = _tasks.subtreeRowsFrom(row, childrenByParent);
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
      await _tasks.insertTask(
        TasksCompanion.insert(
          id: idBySource[source.id]!,
          userId: source.userId,
          scopeId: Value(source.scopeId),
          createdBy: Value(source.createdBy),
          assigneeIdsJson: Value(source.assigneeIdsJson),
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
            payload: {
              'id': idBySource[source.id],
              if (source.scopeId != null) 'recurrenceSourceId': source.id,
              if (source.scopeId != null) 'occurrenceKey': occurrenceKey,
            },
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
      await _tasks.setTaskDeleted(row.id, now);
      await _syncQueue.enqueue(
        type: 'task.delete',
        clientId: row.id,
        payload: {'id': row.id},
        availableAt: availableAt,
      );
    }
    return uniqueRows.map((row) => row.id).toSet();
  }

  Future<void> _copyLabels({
    required Iterable<String> sourceTaskIds,
    required Map<String, String> idBySource,
    required DateTime now,
  }) async {
    final rows = await _tasks.userTaskLabels(sourceTaskIds);
    for (final row in rows) {
      final nextTaskId = idBySource[row.taskId];
      if (nextTaskId == null) {
        continue;
      }
      await _tasks.upsertTaskLabel(
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
    final task = await _tasks.loadTask(taskId);
    final scopeId = task.scopeId;
    final seen = <String>{};
    for (final rawName in labelNames) {
      final name = rawName.trim();
      if (name.isEmpty || !seen.add(name.toLowerCase())) {
        continue;
      }
      var existing = await _tasks.findUserLabelByName(name, scopeId);
      existing ??= (await _tasks.activeUserLabelsInScope(scopeId))
          .firstWhereOrNull(
            (label) => label.name.trim().toLowerCase() == name.toLowerCase(),
          );
      final labelId = existing?.id ?? _uuid.v4();
      if (existing == null) {
        await _tasks.insertLabel(
          LabelsCompanion.insert(
            id: labelId,
            scopeId: Value(scopeId),
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
      await _attachLabel(taskId, labelId, now);
    }
  }

  Future<void> _attachLabel(String taskId, String labelId, DateTime now) async {
    await _access.task(taskId);
    final task = await _tasks.loadTask(taskId);
    final label = await _tasks.loadLabel(labelId);
    if (task.scopeId != label.scopeId) {
      throw const CollaborationException('cross_scope_label');
    }
    await _tasks.upsertTaskLabel(
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

  bool _matchesQuery(TaskItem task, TaskQuery query) {
    if (query.creatorId != null && task.createdBy != query.creatorId) {
      return false;
    }
    if (query.assigneeId != null &&
        !task.assigneeIds.contains(query.assigneeId)) {
      return false;
    }
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
      case TaskQueryKind.label:
        return !task.isCompleted;
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

  TaskItem _mapTask(TaskRow row, {SharedScope? scope}) => TaskItem(
    scopeId: row.scopeId,
    createdBy: row.createdBy,
    completedBy: row.completedBy,
    assigneeIds: collaborationIds(row.assigneeIdsJson),
    canEdit: row.scopeId == null || (scope?.canEdit ?? false),
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
