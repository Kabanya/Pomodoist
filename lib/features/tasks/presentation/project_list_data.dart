import '../../../core/db/app_database.dart' show inboxProjectId;
import '../domain/task_models.dart';

class ProjectListRow {
  const ProjectListRow({required this.project, required this.depth});

  final ProjectItem project;
  final int depth;
}

class _ProjectTreeNode {
  _ProjectTreeNode(this.project);

  final ProjectItem project;
  final List<_ProjectTreeNode> children = [];
}

List<ProjectListRow> projectRows(List<ProjectItem> projects) {
  final nodes = {
    for (final project in projects) project.id: _ProjectTreeNode(project),
  };
  final roots = <_ProjectTreeNode>[];

  for (final project in projects) {
    final node = nodes[project.id]!;
    final parentId = project.parentId;
    if (parentId != null && nodes.containsKey(parentId)) {
      nodes[parentId]!.children.add(node);
    } else {
      roots.add(node);
    }
  }

  final rows = <ProjectListRow>[];
  void visit(_ProjectTreeNode node, int depth) {
    rows.add(ProjectListRow(project: node.project, depth: depth));
    for (final child in node.children) {
      visit(child, depth + 1);
    }
  }

  for (final root in roots) {
    visit(root, 0);
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
