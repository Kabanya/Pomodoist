import '../../../core/db/app_database.dart';
import '../domain/task_models.dart';
import '../domain/project_hierarchy.dart';

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
  final parents = projectParents(active.values);
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
    final parentId = visibleIds.contains(parents[project.id])
        ? parents[project.id]
        : null;
    children.putIfAbsent(parentId, () => []).add(project);
  }
  for (final items in children.values) {
    items.sort((a, b) => a.orderKey.compareTo(b.orderKey));
  }

  final favoriteBranches = <String>{};
  for (final project in active.values.where((p) => p.isFavorite)) {
    String? id = project.id;
    while (id != null && favoriteBranches.add(id)) {
      id = parents[id];
    }
  }
  bool branchHasFavorite(ProjectItem project) =>
      favoriteBranches.contains(project.id);

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
  final stack = <(ProjectItem, int)>[
    for (final root in roots.reversed) (root, 0),
  ];
  while (stack.isNotEmpty) {
    final (project, depth) = stack.removeLast();
    final nested = children[project.id] ?? const <ProjectItem>[];
    rows.add(
      TimelineProjectRow(
        project: project,
        depth: depth,
        hasVisibleChildren: nested.isNotEmpty,
      ),
    );
    if (!collapsedProjectIds.contains(project.id)) {
      for (final child in nested.reversed) {
        stack.add((child, depth + 1));
      }
    }
  }
  return rows;
}
