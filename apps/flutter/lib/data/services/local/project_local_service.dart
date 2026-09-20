import 'package:drift/drift.dart';

import 'package:pomodoist/data/services/local/database/app_database.dart';

typedef ProjectWithScope = ({ProjectRow project, SharedScopeRow? scope});

class ProjectLocalService {
  ProjectLocalService(this._db);

  final AppDatabase _db;

  Stream<List<ProjectWithScope>> watchActiveProjects() {
    final statement = _db.select(_db.projects)
      ..where((project) => project.isDeleted.equals(false))
      ..orderBy([
        (project) => OrderingTerm.asc(project.orderKey),
        (project) => OrderingTerm.asc(project.id),
      ]);
    return statement
        .join([
          leftOuterJoin(
            _db.sharedScopes,
            _db.sharedScopes.id.equalsExp(_db.projects.scopeId),
          ),
        ])
        .watch()
        .map(
          (rows) => [
            for (final result in rows)
              (
                project: result.readTable(_db.projects),
                scope: result.readTableOrNull(_db.sharedScopes),
              ),
          ],
        );
  }

  Future<List<ProjectRow>> activeProjects() {
    return (_db.select(
      _db.projects,
    )..where((project) => project.isDeleted.equals(false))).get();
  }

  Future<void> insertProject(ProjectsCompanion project) {
    return _db.into(_db.projects).insert(project);
  }

  Future<void> updateProject(String id, ProjectsCompanion patch) {
    return (_db.update(
      _db.projects,
    )..where((project) => project.id.equals(id))).write(patch);
  }

  Future<ProjectRow?> findActiveProject(String id) {
    return (_db.select(_db.projects)
          ..where(
            (project) =>
                project.id.equals(id) & project.isDeleted.equals(false),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  Future<void> setProjectDeleted(String id, DateTime updatedAt) {
    return updateProject(
      id,
      ProjectsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  Future<List<TaskRow>> activeTasksForProject(String projectId) {
    return (_db.select(_db.tasks)..where(
          (task) =>
              task.projectId.equals(projectId) & task.isDeleted.equals(false),
        ))
        .get();
  }

  Future<void> moveTaskToProject(
    String taskId,
    String projectId,
    DateTime updatedAt,
  ) {
    return (_db.update(
      _db.tasks,
    )..where((task) => task.id.equals(taskId))).write(
      TasksCompanion(
        projectId: Value(projectId),
        sectionId: const Value(null),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  Future<KanbanSettingsRow> loadKanbanSettings() {
    return (_db.select(
      _db.kanbanSettings,
    )..where((row) => row.id.equals(kanbanSettingsPrimaryId))).getSingle();
  }

  Future<void> repairKanbanSettings({required DateTime now}) {
    return _db.repairKanbanSettings(now: now);
  }
}
