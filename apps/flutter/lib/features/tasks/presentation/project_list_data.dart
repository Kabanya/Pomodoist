import '../domain/task_models.dart';
import '../domain/project_hierarchy.dart';

class ProjectListRow {
  const ProjectListRow({
    required this.project,
    required this.depth,
    this.hasChildren = false,
  });
  final ProjectItem project;
  final int depth;
  final bool hasChildren;
}

List<ProjectListRow> projectRows(
  List<ProjectItem> projects, {
  Set<String> collapsedIds = const {},
}) {
  final parents = projectParents(projects);
  final children = <String?, List<ProjectItem>>{};
  for (final project in projects) {
    children.putIfAbsent(parents[project.id], () => []).add(project);
  }
  final stack = <(ProjectItem, int)>[
    for (final root in (children[null] ?? <ProjectItem>[]).reversed) (root, 0),
  ];
  final rows = <ProjectListRow>[];
  while (stack.isNotEmpty) {
    final (project, depth) = stack.removeLast();
    final nested = children[project.id] ?? const <ProjectItem>[];
    rows.add(
      ProjectListRow(
        project: project,
        depth: depth,
        hasChildren: nested.isNotEmpty,
      ),
    );
    if (!collapsedIds.contains(project.id)) {
      for (final child in nested.reversed) {
        stack.add((child, depth + 1));
      }
    }
  }
  return rows;
}

Map<String, int> countOpenTasksByProject(List<TaskItem> tasks) {
  final counts = <String, int>{};
  for (final task in tasks) {
    if (task.projectId == inboxProjectId ||
        task.isCompleted ||
        task.isDeleted) {
      continue;
    }
    counts.update(task.projectId, (count) => count + 1, ifAbsent: () => 1);
  }
  return counts;
}
