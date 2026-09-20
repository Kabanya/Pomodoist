import 'package:drift/drift.dart';

import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

typedef TaskWithScope = ({TaskRow task, SharedScopeRow? scope});

class TaskLocalService {
  TaskLocalService(this._db);

  final AppDatabase _db;

  Stream<List<TaskWithScope>> watchTasks(TaskQuery query) {
    final statement = _db.select(_db.tasks)
      ..where((task) => task.isDeleted.equals(false));
    statement.where(
      (task) => query.kind == TaskQueryKind.completed
          ? task.status.equals('completed')
          : task.status.equals('completed').not(),
    );
    if (query.kind == TaskQueryKind.inbox) {
      statement.where((task) => task.projectId.equals(inboxProjectId));
    } else if (query.kind == TaskQueryKind.project) {
      statement.where(
        (task) => query.projectId == null
            ? task.projectId.isNull()
            : task.projectId.equals(query.projectId!),
      );
    }
    if (query.kind == TaskQueryKind.label) {
      final links = _db.selectOnly(_db.taskLabels)
        ..addColumns([_db.taskLabels.taskId])
        ..join([
          innerJoin(
            _db.labels,
            _db.labels.id.equalsExp(_db.taskLabels.labelId),
          ),
        ])
        ..where(
          _db.taskLabels.labelId.equals(query.labelId ?? '') &
              _db.taskLabels.kind.equals(labelKindUser) &
              _db.labels.kind.equals(labelKindUser) &
              _db.labels.isDeleted.equals(false),
        );
      statement.where((task) => task.id.isInQuery(links));
    }
    return statement
        .join([
          leftOuterJoin(
            _db.sharedScopes,
            _db.sharedScopes.id.equalsExp(_db.tasks.scopeId),
          ),
        ])
        .watch()
        .map(
          (rows) => [
            for (final result in rows)
              (
                task: result.readTable(_db.tasks),
                scope: result.readTableOrNull(_db.sharedScopes),
              ),
          ],
        );
  }

  Stream<TaskWithScope?> watchTask(String id) {
    final statement = _db.select(_db.tasks)
      ..where((task) => task.id.equals(id));
    return statement
        .join([
          leftOuterJoin(
            _db.sharedScopes,
            _db.sharedScopes.id.equalsExp(_db.tasks.scopeId),
          ),
        ])
        .watchSingleOrNull()
        .map(
          (result) => result == null
              ? null
              : (
                  task: result.readTable(_db.tasks),
                  scope: result.readTableOrNull(_db.sharedScopes),
                ),
        );
  }

  Future<List<TaskRow>> activeTasks() {
    return (_db.select(
      _db.tasks,
    )..where((task) => task.isDeleted.equals(false))).get();
  }

  Future<TaskRow?> findTask(String id) {
    return (_db.select(
      _db.tasks,
    )..where((task) => task.id.equals(id))).getSingleOrNull();
  }

  Future<TaskRow> loadTask(String id) {
    return (_db.select(
      _db.tasks,
    )..where((task) => task.id.equals(id))).getSingle();
  }

  Future<void> insertTask(TasksCompanion task) {
    return _db.into(_db.tasks).insert(task);
  }

  Future<void> updateTask(String id, TasksCompanion patch) {
    return (_db.update(
      _db.tasks,
    )..where((task) => task.id.equals(id))).write(patch);
  }

  Future<void> setTaskDeleted(String id, DateTime updatedAt) {
    return updateTask(
      id,
      TasksCompanion(isDeleted: const Value(true), updatedAt: Value(updatedAt)),
    );
  }

  Future<List<TaskRow>> deletedTasks(Set<String> ids) {
    return (_db.select(
      _db.tasks,
    )..where((row) => row.id.isIn(ids) & row.isDeleted.equals(true))).get();
  }

  Future<void> restoreTasks(Set<String> ids, DateTime updatedAt) {
    return (_db.update(
      _db.tasks,
    )..where((row) => row.id.isIn(ids) & row.isDeleted.equals(true))).write(
      TasksCompanion(
        isDeleted: const Value(false),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  Future<void> deleteTaskRows(Iterable<String> ids) {
    return (_db.delete(_db.tasks)..where((task) => task.id.isIn(ids))).go();
  }

  Map<String, TaskRow> rowById(List<TaskRow> rows) {
    return {for (final row in rows) row.id: row};
  }

  Map<String, List<TaskRow>> childrenByParent(List<TaskRow> rows) {
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

  List<TaskRow> subtreeRowsFrom(
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

  List<TaskRow> subtreeRows(String rootId, List<TaskRow> rows) {
    final root = rowById(rows)[rootId];
    if (root == null) {
      return const [];
    }
    return subtreeRowsFrom(root, childrenByParent(rows));
  }

  Future<LabelRow?> findUserLabel(String id) {
    return (_db.select(_db.labels)..where(
          (row) =>
              row.id.equals(id) &
              row.kind.equals(labelKindUser) &
              row.isDeleted.equals(false),
        ))
        .getSingleOrNull();
  }

  Future<LabelRow> loadLabel(String id) {
    return (_db.select(
      _db.labels,
    )..where((row) => row.id.equals(id))).getSingle();
  }

  Future<LabelRow?> findUserLabelByName(String name, String? scopeId) {
    return (_db.select(_db.labels)
          ..where(
            (label) =>
                label.name.equals(name) &
                label.kind.equals(labelKindUser) &
                (scopeId == null
                    ? label.scopeId.isNull()
                    : label.scopeId.equals(scopeId)) &
                label.isDeleted.equals(false),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  Future<List<LabelRow>> activeUserLabelsInScope(String? scopeId) {
    return (_db.select(_db.labels)..where(
          (label) =>
              label.kind.equals(labelKindUser) &
              (scopeId == null
                  ? label.scopeId.isNull()
                  : label.scopeId.equals(scopeId)) &
              label.isDeleted.equals(false),
        ))
        .get();
  }

  Future<void> insertLabel(LabelsCompanion label) {
    return _db.into(_db.labels).insert(label);
  }

  Future<List<TaskLabelRow>> userTaskLabels(Iterable<String> taskIds) {
    return (_db.select(_db.taskLabels)..where(
          (label) =>
              label.taskId.isIn(taskIds) & label.kind.equals(labelKindUser),
        ))
        .get();
  }

  Future<void> upsertTaskLabel(TaskLabelsCompanion link) {
    return _db.into(_db.taskLabels).insertOnConflictUpdate(link);
  }

  Future<void> deleteTaskLabels(Iterable<String> taskIds) {
    return (_db.delete(
      _db.taskLabels,
    )..where((label) => label.taskId.isIn(taskIds))).go();
  }

  Future<List<SyncCommandRow>> pendingDeleteCommands(
    Set<String> taskIds,
    DateTime availableAt,
  ) {
    return (_db.select(_db.syncCommands)..where(
          (row) =>
              row.type.equals('task.delete') &
              row.status.equals('pending') &
              row.attempts.equals(0) &
              row.clientId.isIn(taskIds) &
              row.availableAt.equals(availableAt),
        ))
        .get();
  }

  Future<void> deleteCommands(Iterable<String> ids) {
    return (_db.delete(
      _db.syncCommands,
    )..where((row) => row.id.isIn(ids))).go();
  }

  Future<SyncCommandRow?> pendingCreateCommand(
    String clientId,
    DateTime windowStart,
  ) {
    return (_db.select(_db.syncCommands)..where(
          (command) =>
              command.type.equals('task.create') &
              command.clientId.equals(clientId) &
              command.status.equals('pending') &
              command.attempts.equals(0) &
              command.updatedAt.isBiggerOrEqualValue(windowStart),
        ))
        .getSingleOrNull();
  }

  Future<void> deleteCommandsByClientIds(Iterable<String> clientIds) {
    return (_db.delete(
      _db.syncCommands,
    )..where((command) => command.clientId.isIn(clientIds))).go();
  }

  Future<List<FocusIntervalRow>> completedWorkIntervals(String taskId) async {
    return await (_db.select(_db.focusIntervals)..where(
          (interval) =>
              interval.taskId.equals(taskId) &
              interval.type.equals('work') &
              interval.status.equals('completed') &
              interval.isDeleted.equals(false),
        ))
        .get();
  }
}
