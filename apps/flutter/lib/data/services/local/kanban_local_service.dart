import 'package:drift/drift.dart';

import 'package:pomodoist/data/services/local/database/app_database.dart';

class KanbanLocalService {
  KanbanLocalService(this._db);

  final AppDatabase _db;

  Stream<void> watchBoardChanges() {
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            _db.labels,
            _db.taskLabels,
            _db.kanbanSettings,
            _db.projects,
            _db.tasks,
            _db.sharedScopes,
          },
        )
        .watch()
        .map((_) {});
  }

  Future<List<SharedScopeRow>> loadSharedScopes() {
    return _db.select(_db.sharedScopes).get();
  }

  Future<KanbanSettingsRow> loadKanbanSettings() {
    return (_db.select(
      _db.kanbanSettings,
    )..where((row) => row.id.equals(kanbanSettingsPrimaryId))).getSingle();
  }

  Future<List<ProjectRow>> activeProjects() {
    return (_db.select(_db.projects)
          ..where(
            (row) => row.isDeleted.equals(false) & row.isArchived.equals(false),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.orderKey),
            (row) => OrderingTerm.asc(row.id),
          ]))
        .get();
  }

  Future<Set<String>> activeProjectIds() async {
    final rows =
        await (_db.select(_db.projects)..where(
              (row) =>
                  row.isDeleted.equals(false) & row.isArchived.equals(false),
            ))
            .get();
    return rows.map((project) => project.id).toSet();
  }

  Future<List<ProjectRow>> projectsByIds(Iterable<String> ids) {
    return (_db.select(_db.projects)..where((row) => row.id.isIn(ids))).get();
  }

  Future<List<LabelRow>> activeStatusRows({String? scopeId, bool all = false}) {
    return (_db.select(_db.labels)..where(
          (row) =>
              row.kind.equals(labelKindKanbanStatus) &
              (all
                  ? const Constant(true)
                  : scopeId == null
                  ? row.scopeId.isNull()
                  : row.scopeId.equals(scopeId)) &
              row.isDeleted.equals(false),
        ))
        .get();
  }

  Future<LabelRow?> findActiveStatus(String id) {
    return (_db.select(_db.labels)..where(
          (row) =>
              row.id.equals(id) &
              row.kind.equals(labelKindKanbanStatus) &
              row.isDeleted.equals(false),
        ))
        .getSingleOrNull();
  }

  Future<LabelRow?> findStatusByName(
    String name, {
    String? exceptId,
    String? scopeId,
  }) {
    return (_db.select(_db.labels)..where(
          (row) =>
              row.kind.equals(labelKindKanbanStatus) &
              (scopeId == null
                  ? row.scopeId.isNull()
                  : row.scopeId.equals(scopeId)) &
              row.isDeleted.equals(false) &
              row.name.lower().equals(name.toLowerCase()) &
              (exceptId == null
                  ? const Constant(true)
                  : row.id.equals(exceptId).not()),
        ))
        .getSingleOrNull();
  }

  Future<void> insertLabel(LabelsCompanion label) {
    return _db.into(_db.labels).insert(label);
  }

  Future<void> updateLabelName(String id, String name, DateTime updatedAt) {
    return (_db.update(_db.labels)..where((row) => row.id.equals(id))).write(
      LabelsCompanion(name: Value(name), updatedAt: Value(updatedAt)),
    );
  }

  Future<void> updateLabelOrderKey(
    String id,
    String orderKey,
    DateTime updatedAt,
  ) {
    return (_db.update(_db.labels)..where((row) => row.id.equals(id))).write(
      LabelsCompanion(orderKey: Value(orderKey), updatedAt: Value(updatedAt)),
    );
  }

  Future<void> markLabelDeleted(String id, DateTime updatedAt) {
    return (_db.update(_db.labels)..where((row) => row.id.equals(id))).write(
      LabelsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  Future<List<TaskLabelRow>> statusLinksForLabel(String labelId) {
    return (_db.select(_db.taskLabels)..where(
          (row) =>
              row.kind.equals(labelKindKanbanStatus) &
              row.labelId.equals(labelId),
        ))
        .get();
  }

  Future<List<TaskLabelRow>> statusLinksForTasks(Iterable<String> taskIds) {
    return (_db.select(_db.taskLabels)..where(
          (row) =>
              row.kind.equals(labelKindKanbanStatus) & row.taskId.isIn(taskIds),
        ))
        .get();
  }

  Future<List<TaskLabelRow>> statusLinksForStatuses(
    Iterable<String> statusIds,
  ) {
    return (_db.select(_db.taskLabels)..where(
          (row) =>
              row.kind.equals(labelKindKanbanStatus) &
              row.labelId.isIn(statusIds),
        ))
        .get();
  }

  Future<TaskRow?> findActiveTask(String id) {
    return (_db.select(_db.tasks)
          ..where((row) => row.id.equals(id) & row.isDeleted.equals(false)))
        .getSingleOrNull();
  }

  Future<List<TaskRow>> openRootTasks(Iterable<String> projectIds) {
    return (_db.select(_db.tasks)
          ..where(
            (row) =>
                row.projectId.isIn(projectIds) &
                row.parentId.isNull() &
                row.isDeleted.equals(false) &
                row.status.equals('open'),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.orderKey),
            (row) => OrderingTerm.asc(row.id),
          ]))
        .get();
  }

  Future<List<TaskRow>> recentDoneRootTasks(Iterable<String> projectIds) {
    final recency = coalesce<DateTime>([
      _db.tasks.completedAt,
      _db.tasks.updatedAt,
    ]);
    return (_db.select(_db.tasks)
          ..where(
            (row) =>
                row.projectId.isIn(projectIds) &
                row.parentId.isNull() &
                row.isDeleted.equals(false) &
                row.status.equals('completed'),
          )
          ..orderBy([
            (_) => OrderingTerm.desc(recency),
            (row) => OrderingTerm.desc(row.id),
          ])
          ..limit(20))
        .get();
  }

  Future<List<({String parentId, int total, int completed})>>
  subtaskProgressForParents(Iterable<String> parentIds) async {
    final totalSubtasks = _db.tasks.id.count();
    final completedSubtasks = _db.tasks.id.count(
      filter: _db.tasks.status.equals('completed'),
    );
    final rows =
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
    final progress = <({String parentId, int total, int completed})>[];
    for (final row in rows) {
      final parentId = row.read(_db.tasks.parentId);
      if (parentId != null) {
        progress.add((
          parentId: parentId,
          total: row.read(totalSubtasks) ?? 0,
          completed: row.read(completedSubtasks) ?? 0,
        ));
      }
    }
    return progress;
  }

  Future<List<TaskRow>> openTasksForReorder({
    required Iterable<String> taskIds,
    required Iterable<String> projectIds,
  }) {
    return (_db.select(_db.tasks)..where(
          (row) =>
              row.id.isIn(taskIds) &
              row.isDeleted.equals(false) &
              row.status.equals('open') &
              row.parentId.isNull() &
              row.projectId.isIn(projectIds),
        ))
        .get();
  }

  Future<void> updateSelectedProjectIds(String json, DateTime updatedAt) {
    return (_db.update(
      _db.kanbanSettings,
    )..where((row) => row.id.equals(kanbanSettingsPrimaryId))).write(
      KanbanSettingsCompanion(
        selectedProjectIdsJson: Value(json),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  Future<void> updateFocusStatusLabelId(String statusId, DateTime updatedAt) {
    return (_db.update(
      _db.kanbanSettings,
    )..where((row) => row.id.equals(kanbanSettingsPrimaryId))).write(
      KanbanSettingsCompanion(
        focusStatusLabelId: Value(statusId),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  Future<void> updateTaskOrder(String id, String orderKey, DateTime updatedAt) {
    return (_db.update(_db.tasks)..where((row) => row.id.equals(id))).write(
      TasksCompanion(orderKey: Value(orderKey), updatedAt: Value(updatedAt)),
    );
  }
}
