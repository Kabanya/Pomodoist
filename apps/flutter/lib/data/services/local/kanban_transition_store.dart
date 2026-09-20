import 'package:drift/drift.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';

/// Raw reads and writes used inside the repository's shared transaction.
class KanbanTransitionStore {
  KanbanTransitionStore(this._db);
  final AppDatabase _db;
  Future<TaskRow?> task(String id, {bool activeOnly = false}) =>
      (_db.select(_db.tasks)..where(
            (r) =>
                r.id.equals(id) &
                (activeOnly ? r.isDeleted.equals(false) : const Constant(true)),
          ))
          .getSingleOrNull();
  Future<LabelRow?> label(String id) =>
      (_db.select(_db.labels)..where((r) => r.id.equals(id))).getSingleOrNull();
  Future<LabelRow?> activeStatus(String id) =>
      (_db.select(_db.labels)..where(
            (r) =>
                r.id.equals(id) &
                r.kind.equals(labelKindKanbanStatus) &
                r.isDeleted.equals(false),
          ))
          .getSingleOrNull();
  Future<List<LabelRow>> activeStatuses() =>
      (_db.select(_db.labels)..where(
            (r) =>
                r.kind.equals(labelKindKanbanStatus) &
                r.isDeleted.equals(false),
          ))
          .get();
  Future<List<TaskRow>> activeTasks() =>
      (_db.select(_db.tasks)..where((r) => r.isDeleted.equals(false))).get();
  Future<TaskLabelRow?> assignment(String id) =>
      (_db.select(_db.taskLabels)..where(
            (r) => r.taskId.equals(id) & r.kind.equals(labelKindKanbanStatus),
          ))
          .getSingleOrNull();
  Future<List<TaskLabelRow>> assignments() => (_db.select(
    _db.taskLabels,
  )..where((r) => r.kind.equals(labelKindKanbanStatus))).get();
  Future<List<TaskCompletionRow>> completions(String id) =>
      (_db.select(_db.taskCompletions)
            ..where((r) => r.taskId.equals(id))
            ..orderBy([
              (r) => OrderingTerm.desc(r.completedAt),
              (r) => OrderingTerm.desc(r.createdAt),
              (r) => OrderingTerm.desc(r.id),
            ]))
          .get();
  Future<KanbanSettingsRow?> settings() => (_db.select(
    _db.kanbanSettings,
  )..where((r) => r.id.equals(kanbanSettingsPrimaryId))).getSingleOrNull();
  Future<void> repairSettings(DateTime timestamp) =>
      _db.repairKanbanSettings(now: timestamp);
  Future<void> writeTask(String id, TasksCompanion values) async {
    await (_db.update(_db.tasks)..where((r) => r.id.equals(id))).write(values);
  }

  Future<void> insertCompletion(TaskCompletionsCompanion values) async {
    await _db.into(_db.taskCompletions).insert(values);
  }

  Future<void> replaceAssignment(
    String taskId,
    String statusId,
    DateTime timestamp,
  ) async {
    await (_db.delete(_db.taskLabels)..where(
          (r) => r.taskId.equals(taskId) & r.kind.equals(labelKindKanbanStatus),
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
  }

  Future<void> repairProtectedAnchor({
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
}
