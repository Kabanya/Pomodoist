import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../core/db/app_database.dart';
import '../domain/collaboration_models.dart';

class SharedAccess {
  const SharedAccess(this.db);
  final AppDatabase db;

  Future<String> actorId() async {
    final row =
        await (db.select(db.syncState)
              ..where((row) => row.id.equals('pomodoist-account-owner-v1')))
            .getSingleOrNull();
    return row?.cursor == null || row!.cursor == 'guest'
        ? localUserId
        : row.cursor!;
  }

  Future<SharedScope?> scope(String? id) async {
    if (id == null) return null;
    final row = await (db.select(
      db.sharedScopes,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    return row == null ? null : SharedScope.fromJson(jsonDecode(row.dataJson));
  }

  Future<String?> projectScope(String? id) async {
    if (id == null) return null;
    return (await (db.select(
      db.projects,
    )..where((row) => row.id.equals(id))).getSingleOrNull())?.scopeId;
  }

  Future<void> requireEdit(String? id) async {
    if (id != null && !((await scope(id))?.canEdit ?? false)) {
      throw const CollaborationException('forbidden');
    }
  }

  Future<String?> commandScope(
    String type,
    String? id,
    Map<String, Object?> payload,
  ) async {
    final explicit = payload['scopeId'] as String?;
    if (explicit != null) return explicit;
    if (id == null) return null;
    if (type.startsWith('task.')) {
      final task = await (db.select(
        db.tasks,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      return task?.scopeId ?? await projectScope(task?.projectId);
    }
    if (type.startsWith('project.')) return projectScope(id);
    if (type.startsWith('section.')) {
      final section = await (db.select(
        db.sections,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      return projectScope(section?.projectId);
    }
    if (type.startsWith('label.') || type.startsWith('kanban.status.')) {
      return (await (db.select(
        db.labels,
      )..where((row) => row.id.equals(id))).getSingleOrNull())?.scopeId;
    }
    return null;
  }

  Future<void> task(String id, {String? destinationProjectId}) async {
    final row = await (db.select(
      db.tasks,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    await requireEdit(row.scopeId);
    if (destinationProjectId != null &&
        row.scopeId != await projectScope(destinationProjectId)) {
      throw const CollaborationException('cross_scope_move');
    }
  }

  Future<void> taskLocation(
    String projectId, {
    String? parentId,
    String? sectionId,
  }) async {
    final scopeId = await projectScope(projectId);
    if (parentId != null) {
      final parent = await (db.select(
        db.tasks,
      )..where((row) => row.id.equals(parentId))).getSingleOrNull();
      if (parent?.scopeId != scopeId ||
          scopeId != null &&
              (parent == null ||
                  parent.isDeleted ||
                  parent.projectId != projectId)) {
        throw const CollaborationException('cross_scope_move');
      }
    }
    if (scopeId != null && sectionId != null) {
      final section = await (db.select(
        db.sections,
      )..where((row) => row.id.equals(sectionId))).getSingleOrNull();
      if (section == null ||
          section.projectId != projectId ||
          section.isDeleted) {
        throw const CollaborationException('invalid_section');
      }
    }
  }

  Future<void> project(
    String id, {
    String? destinationId,
    bool moving = false,
    bool deleting = false,
  }) async {
    final scopeId = await projectScope(id);
    final access = await scope(scopeId);
    if (moving && access?.rootProjectId == id) {
      if (await projectScope(destinationId) != null)
        throw const CollaborationException('cross_scope_move');
      return;
    }
    await requireEdit(scopeId);
    if (moving && scopeId != await projectScope(destinationId)) {
      throw const CollaborationException('cross_scope_move');
    }
    if (deleting && access?.rootProjectId == id) {
      throw const CollaborationException('shared_root_requires_server_delete');
    }
  }
}
