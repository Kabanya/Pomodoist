import 'package:pomodoist/domain/models/tasks/task_models.dart';

int compareProjects(ProjectItem a, ProjectItem b) {
  final order = a.orderKey.compareTo(b.orderKey);
  return order == 0 ? a.id.compareTo(b.id) : order;
}

/// A display-only forest: incomplete or cyclic sync data must stay reachable.
Map<String, String?> projectParents(Iterable<ProjectItem> projects) {
  final sorted = projects.toList()..sort(compareProjects);
  final ids = sorted.map((p) => p.id).toSet();
  final parents = {
    for (final p in sorted)
      p.id: p.parentId != inboxProjectId && ids.contains(p.parentId)
          ? p.parentId
          : null,
  };
  final visited = <String>{};
  for (final project in sorted) {
    final path = <String>{};
    String? id = project.id;
    while (id != null && !visited.contains(id)) {
      if (!path.add(id)) {
        parents[id] = null;
        break;
      }
      id = parents[id];
    }
    visited.addAll(path);
  }
  return parents;
}

bool canParentProject(
  Iterable<ProjectItem> projects, {
  String? projectId,
  required String? parentId,
}) {
  if (projectId == inboxProjectId) return false;
  if (parentId == null) return true;
  final byId = {for (final p in projects) p.id: p};
  final seen = <String>{?projectId};
  String? current = parentId;
  while (current != null) {
    final parent = byId[current];
    if (current == inboxProjectId ||
        !seen.add(current) ||
        parent == null ||
        parent.isDeleted ||
        parent.isArchived) {
      return false;
    }
    current = parent.parentId;
  }
  return true;
}

enum ProjectDropPosition { before, inside, after }

class ProjectMoveTarget {
  const ProjectMoveTarget(this.parentId, this.beforeProjectId);
  final String? parentId;
  final String? beforeProjectId;
}

ProjectMoveTarget? projectDropTarget(
  List<ProjectItem> projects,
  String id,
  String targetId,
  ProjectDropPosition position,
) {
  if (id == targetId || id == inboxProjectId || targetId == inboxProjectId) {
    return null;
  }
  final byId = {for (final p in projects) p.id: p};
  final source = byId[id];
  final target = byId[targetId];
  if (source == null ||
      target == null ||
      source.isArchived ||
      source.isDeleted ||
      target.isArchived ||
      target.isDeleted) {
    return null;
  }
  final parents = projectParents(projects);
  final parentId = position == ProjectDropPosition.inside
      ? targetId
      : parents[targetId];
  if (!canParentProject(projects, projectId: id, parentId: parentId)) {
    return null;
  }
  if (position == ProjectDropPosition.inside) {
    return ProjectMoveTarget(parentId, null);
  }
  final siblings =
      projects
          .where(
            (p) =>
                p.id != id &&
                p.id != inboxProjectId &&
                !p.isDeleted &&
                parents[p.id] == parentId,
          )
          .toList()
        ..sort(compareProjects);
  final index = siblings.indexWhere((p) => p.id == targetId);
  if (index < 0) return null;
  return ProjectMoveTarget(
    parentId,
    position == ProjectDropPosition.before
        ? targetId
        : (index + 1 < siblings.length ? siblings[index + 1].id : null),
  );
}
