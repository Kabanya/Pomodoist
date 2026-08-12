import '../../../core/db/app_database.dart';
import '../domain/task_models.dart';

class TimelineProjectRow {
  const TimelineProjectRow({
    required this.project,
    required this.depth,
    required this.hasVisibleChildren,
  });

  final ProjectItem project;
  final int depth;
  final bool hasVisibleChildren;
}

List<TimelineProjectRow> buildTimelineProjectRows({
  required List<ProjectItem> projects,
  required Iterable<TaskItem> tasks,
  required Set<String> collapsedProjectIds,
  required Set<String> temporarilyVisibleProjectIds,
}) {
  final active = {
    for (final project in projects)
      if (!project.isArchived && !project.isDeleted) project.id: project,
  };
  final visibleIds = <String>{
    if (active.containsKey(inboxProjectId)) inboxProjectId,
    ...temporarilyVisibleProjectIds.where(active.containsKey),
    ...tasks.map((task) => task.projectId).where(active.containsKey),
    ...active.values
        .where((project) => project.isFavorite)
        .map((project) => project.id),
  };

  for (final id in [...visibleIds]) {
    var parentId = active[id]?.parentId;
    final seen = <String>{id};
    while (parentId != null &&
        active.containsKey(parentId) &&
        seen.add(parentId)) {
      visibleIds.add(parentId);
      parentId = active[parentId]?.parentId;
    }
  }

  final children = <String?, List<ProjectItem>>{};
  for (final id in visibleIds) {
    final project = active[id];
    if (project == null) {
      continue;
    }
    final parentId = visibleIds.contains(project.parentId)
        ? project.parentId
        : null;
    children.putIfAbsent(parentId, () => []).add(project);
  }
  for (final items in children.values) {
    items.sort((a, b) => a.orderKey.compareTo(b.orderKey));
  }

  final favoriteBranchCache = <String, bool>{};
  bool branchHasFavorite(ProjectItem project) =>
      favoriteBranchCache[project.id] ??=
          project.isFavorite ||
          (children[project.id] ?? const <ProjectItem>[]).any(
            branchHasFavorite,
          );

  int compareFavoriteBranches(ProjectItem a, ProjectItem b) {
    final aFavorite = branchHasFavorite(a);
    final bFavorite = branchHasFavorite(b);
    if (aFavorite != bFavorite) {
      return aFavorite ? -1 : 1;
    }
    return a.orderKey.compareTo(b.orderKey);
  }

  for (final entry in children.entries) {
    if (entry.key != null) {
      entry.value.sort(compareFavoriteBranches);
    }
  }

  int rootGroup(ProjectItem project) {
    if (project.id == inboxProjectId) {
      return 0;
    }
    return branchHasFavorite(project) ? 1 : 2;
  }

  final roots = children[null] ?? <ProjectItem>[];
  roots.sort((a, b) {
    final group = rootGroup(a).compareTo(rootGroup(b));
    return group != 0 ? group : a.orderKey.compareTo(b.orderKey);
  });

  final rows = <TimelineProjectRow>[];
  void visit(ProjectItem project, int depth) {
    final visibleChildren = children[project.id] ?? const <ProjectItem>[];
    rows.add(
      TimelineProjectRow(
        project: project,
        depth: depth,
        hasVisibleChildren: visibleChildren.isNotEmpty,
      ),
    );
    if (collapsedProjectIds.contains(project.id)) {
      return;
    }
    for (final child in visibleChildren) {
      visit(child, depth + 1);
    }
  }

  for (final root in roots) {
    visit(root, 0);
  }
  return rows;
}
