import 'package:pomodoist/utils/result.dart';
import 'package:pomodoist/data/repositories/projects/project_repository.dart';
import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/project_local_service.dart';
import 'package:pomodoist/data/services/local/shared_access.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/domain/models/tasks/project_colors.dart';
import 'package:pomodoist/domain/models/tasks/project_hierarchy.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/data/services/local/task_repository_support.dart';

class DriftProjectRepository implements ProjectRepository {
  DriftProjectRepository(AppDatabase db, this._syncQueue, {Uuid? uuid})
    : _db = db,
      _uuid = uuid ?? const Uuid(),
      _projects = ProjectLocalService(db);

  final AppDatabase _db;
  SharedAccess get _access => SharedAccess(_db);
  final OutboxService _syncQueue;
  final Uuid _uuid;
  final ProjectLocalService _projects;

  @override
  Stream<List<ProjectItem>> watchProjects() {
    return _projects.watchActiveProjects().asyncMap((rows) async {
      final actor = await _access.actorId();
      return List<ProjectItem>.unmodifiable(
        rows.map(
          (row) => _mapProject(
            row.project,
            scope: sharedScopeFromRow(row.scope),
            actor: actor,
          ),
        ),
      );
    });
  }

  @override
  Future<Result<ProjectItem?>> findByName(String name) =>
      Result.capture<ProjectItem?>(() async {
        final normalizedName = name.trim().toLowerCase();
        final row = (await _projects.activeProjects()).firstWhereOrNull(
          (project) => project.name.trim().toLowerCase() == normalizedName,
        );
        return row == null ? null : _mapProject(row);
      });

  Future<List<ProjectItem>> _activeProjects() async =>
      (await _projects.activeProjects()).map(_mapProject).toList()
        ..sort(compareProjects);

  void _validateParent(
    List<ProjectItem> projects,
    String? id,
    String? parentId,
  ) {
    if (!canParentProject(projects, projectId: id, parentId: parentId)) {
      throw ArgumentError('Invalid parent project');
    }
  }

  // ponytail: renumber siblings in O(n); use fractional keys if large groups need it.
  Future<void> _writeProjectOrder(
    List<ProjectItem> items,
    String? parentId,
    DateTime now,
  ) async {
    for (var index = 0; index < items.length; index++) {
      final project = items[index];
      final key = ((index + 1) * 1024).toString().padLeft(20, '0');
      if (project.parentId == parentId && project.orderKey == key) continue;
      await _projects.updateProject(
        project.id,
        ProjectsCompanion(
          parentId: Value(parentId),
          orderKey: Value(key),
          updatedAt: Value(now),
        ),
      );
      final scope = await _access.scope(project.scopeId);
      if (scope?.rootProjectId == project.id) {
        await _syncQueue.enqueue(
          type: 'private.preferences',
          clientId: scope!.id,
          payload: {
            'scopeId': scope.id,
            'entityType': 'scope',
            'entityId': scope.id,
            'data': {
              'rootParentId': parentId,
              'viewPreferences': {'orderKey': key},
            },
          },
        );
        continue;
      }
      await _syncQueue.enqueue(
        type: 'project.update',
        clientId: project.id,
        payload: {'id': project.id, 'parentId': parentId, 'orderKey': key},
      );
    }
  }

  @override
  Future<Result<String>> createProject(
    String name, {
    String? color,
    String? parentId,
  }) => Result.capture<String>(
    () async => _db.transaction(() async {
      final scopeId = await _access.projectScope(parentId);
      await _access.requireEdit(scopeId);
      final trimmed = name.trim();
      if (trimmed.isEmpty) throw ArgumentError('Project name is empty');
      final items = await _activeProjects();
      _validateParent(items, null, parentId);
      final existing = items.firstWhereOrNull(
        (p) => p.name.trim().toLowerCase() == trimmed.toLowerCase(),
      );
      if (existing != null) {
        if (existing.parentId != parentId) {
          throw ArgumentError('Project name already exists');
        }
        return existing.id;
      }
      final normalizedColor = color == null
          ? nextProjectColor(items)
          : normalizeProjectColor(color);
      if (normalizedColor == null || !isPaletteProjectColor(normalizedColor)) {
        throw ArgumentError.value(color, 'color', 'Unsupported project color');
      }
      final now = DateTime.now().toUtc();
      final id = _uuid.v4();
      final parents = projectParents(items);
      final siblings = items
          .where((p) => p.id != inboxProjectId && parents[p.id] == parentId)
          .toList();
      await _writeProjectOrder(siblings, parentId, now);
      final orderKey = ((siblings.length + 1) * 1024).toString().padLeft(
        20,
        '0',
      );
      await _projects.insertProject(
        ProjectsCompanion.insert(
          id: id,
          userId: localUserId,
          scopeId: Value(scopeId),
          name: trimmed,
          color: Value(normalizedColor),
          parentId: Value(parentId),
          orderKey: orderKey,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await _syncQueue.enqueue(
        type: 'project.create',
        clientId: id,
        payload: {
          'id': id,
          'name': trimmed,
          'color': normalizedColor,
          'parentId': parentId,
          'orderKey': orderKey,
        },
      );
      return id;
    }),
  );

  @override
  Future<Result<void>> moveProject(
    String id, {
    required String? parentId,
    String? beforeProjectId,
  }) => Result.capture<void>(
    () async => _db.transaction(() async {
      await _access.project(id, destinationId: parentId, moving: true);
      final items = await _activeProjects();
      final project = items.firstWhereOrNull((p) => p.id == id);
      if (project == null || project.isArchived || id == inboxProjectId) {
        throw ArgumentError('Project cannot be moved');
      }
      _validateParent(items, id, parentId);
      final parents = projectParents(items);
      final siblings = items
          .where(
            (p) =>
                p.id != inboxProjectId &&
                p.id != id &&
                parents[p.id] == parentId,
          )
          .toList();
      if (beforeProjectId == id && parents[id] == parentId) return;
      final index = beforeProjectId == null
          ? siblings.length
          : siblings.indexWhere((p) => p.id == beforeProjectId);
      if (index < 0) throw ArgumentError('Invalid project position');
      siblings.insert(index, project);
      final now = DateTime.now().toUtc();
      await _writeProjectOrder(siblings, parentId, now);
      if (parents[id] != parentId) {
        await _writeProjectOrder(
          items
              .where(
                (p) =>
                    p.id != inboxProjectId &&
                    p.id != id &&
                    parents[p.id] == parents[id],
              )
              .toList(),
          parents[id],
          now,
        );
      }
    }),
  );

  @override
  Future<Result<void>> updateProject(
    String id,
    UpdateProjectPatch patch,
  ) => Result.capture<void>(() async {
    if (patch.name != null || patch.color != null || patch.icon != null) {
      await _access.project(id);
    }
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
      final existing = await findByName(
        normalizedName,
      ).then((result) => result.getOrThrow());
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
    if (patch.icon != null &&
        !ProjectIcon.values.any((icon) => icon.name == patch.icon)) {
      throw ArgumentError.value(
        patch.icon,
        'patch.icon',
        'Unsupported project icon',
      );
    }
    if (normalizedName == null &&
        patch.icon == null &&
        normalizedColor == null &&
        patch.isFavorite == null) {
      return;
    }
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await _projects.updateProject(
        id,
        ProjectsCompanion(
          icon: patch.icon == null ? const Value.absent() : Value(patch.icon),
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
          'icon': ?patch.icon,
        },
      );
    });
  });

  @override
  Future<Result<void>> deleteProject(String id) => Result.capture<void>(
    () async {
      await _access.project(id, deleting: true);
      if (id == inboxProjectId) {
        return;
      }
      final now = DateTime.now().toUtc();
      await _db.transaction(() async {
        final project = await _projects.findActiveProject(id);
        if (project == null) {
          return;
        }

        final items = await _activeProjects();
        final parents = projectParents(items);
        final parentId = parents[id];
        final children = items
            .where((p) => p.id != inboxProjectId && parents[p.id] == id)
            .toList();
        final siblings = <ProjectItem>[
          for (final item in items.where(
            (p) => p.id != inboxProjectId && parents[p.id] == parentId,
          ))
            if (item.id == id) ...children else item,
        ];
        await _writeProjectOrder(siblings, parentId, now);

        final tasks = await _projects.activeTasksForProject(id);
        for (final task in tasks) {
          final targetProjectId = project.scopeId == null
              ? inboxProjectId
              : parentId!;
          await _projects.moveTaskToProject(task.id, targetProjectId, now);
          await _syncQueue.enqueue(
            type: 'task.move',
            clientId: task.id,
            payload: {
              'id': task.id,
              'projectId': targetProjectId,
              'sectionId': null,
              'parentId': task.parentId,
              'orderKey': task.orderKey,
            },
          );
        }

        final settingsBefore = await _projects.loadKanbanSettings();
        await _projects.setProjectDeleted(id, now);
        await _projects.repairKanbanSettings(now: now);
        final settingsAfter = await _projects.loadKanbanSettings();
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
    },
  );

  ProjectItem _mapProject(
    ProjectRow row, {
    SharedScope? scope,
    String? actor,
  }) => ProjectItem(
    scopeId: row.scopeId,
    canEdit: row.scopeId == null || (scope?.canEdit ?? false),
    canManage: row.scopeId == null || (scope?.canManage ?? false),
    isOwner: row.scopeId == null || (scope?.canDeleteRoot(actor) ?? false),
    id: row.id,
    userId: row.userId,
    name: row.name,
    color: row.color,
    icon: row.icon,
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
