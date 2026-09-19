import 'dart:convert';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';

class PublicProject {
  PublicProject(List<PublicProjectSection> sections)
    : sections = List.unmodifiable(sections);

  final List<PublicProjectSection> sections;

  bool get isEmpty => sections.isEmpty;

  /// The only section, when the link covers a single named project.
  PublicProjectSection? get singleProject {
    final only = sections.length == 1 ? sections.single : null;
    return only == null || only.name == null ? null : only;
  }

  static PublicProject fromResponse(Map<String, dynamic> response) {
    final commentsByTask = <String, List<PublicComment>>{};
    for (final comment in collaborationMaps(response['comments'])) {
      final taskId = _text(comment['taskId']);
      final body = _text(comment['body']);
      if (taskId == null || body == null) continue;
      (commentsByTask[taskId] ??= []).add(
        PublicComment(
          id: _text(comment['id']) ?? taskId,
          body: body,
          author: _text(comment['creatorName']),
          createdAt: _text(comment['createdAt']),
        ),
      );
    }
    for (final comments in commentsByTask.values) {
      comments.sort((a, b) => _compareText(a.createdAt, b.createdAt));
    }

    final tasksByProject = <String, List<Map<String, dynamic>>>{};
    for (final task in collaborationMaps(response['tasks'])) {
      if (_text(task['id']) == null || _text(task['content']) == null) continue;
      (tasksByProject[_text(task['projectId']) ?? ''] ??= []).add(task);
    }

    final sections = <PublicProjectSection>[];
    final named = <String>{};
    for (final project in collaborationMaps(response['projects'])) {
      final id = _text(project['id']);
      if (id == null) continue;
      named.add(id);
      sections.add(
        PublicProjectSection(
          id: id,
          name: _text(project['name']),
          tasks: _taskTree(tasksByProject[id] ?? const [], commentsByTask),
        ),
      );
    }
    // Tasks of a project the projection did not name stay visible.
    final ungrouped = <PublicTaskNode>[
      for (final entry in tasksByProject.entries)
        if (!named.contains(entry.key))
          ..._taskTree(entry.value, commentsByTask),
    ];
    if (ungrouped.isNotEmpty) {
      sections.add(PublicProjectSection(id: 'shared', tasks: ungrouped));
    }
    return PublicProject(sections);
  }

  static List<PublicTaskNode> _taskTree(
    List<Map<String, dynamic>> rows,
    Map<String, List<PublicComment>> commentsByTask,
  ) {
    final ordered = [...rows]
      ..sort((a, b) {
        final byOrder = _compareText(a['orderKey'], b['orderKey']);
        return byOrder != 0
            ? byOrder
            : _compareText(a['createdAt'], b['createdAt']);
      });
    final tasks = [
      for (final row in ordered)
        PublicTask(
          id: _text(row['id'])!,
          content: _text(row['content'])!,
          parentId: _text(row['parentId']),
          status: _text(row['status']),
          creatorName: _text(row['creatorName']),
          assigneeNames: _names(row['assigneeNames']),
          schedule: TaskSchedule.fromJsonString(_text(row['dueJson'])),
          deadline: _deadline(row['deadlineJson']),
        ),
    ];
    final byId = {for (final task in tasks) task.id: task};
    final childTasks = <String, List<PublicTask>>{};
    final roots = <PublicTask>[];
    for (final task in tasks) {
      final parentId = task.parentId;
      if (parentId == null ||
          parentId == task.id ||
          !byId.containsKey(parentId)) {
        roots.add(task);
      } else {
        (childTasks[parentId] ??= []).add(task);
      }
    }

    final nodes = <PublicTaskNode>[];
    final visited = <String>{};
    void walk(PublicTask task, int depth) {
      // A cycle or a repeated parent must never repeat or drop a task.
      if (!visited.add(task.id)) return;
      nodes.add(
        PublicTaskNode(
          task: task,
          depth: depth,
          comments: commentsByTask[task.id] ?? const [],
        ),
      );
      for (final child in childTasks[task.id] ?? const <PublicTask>[]) {
        walk(child, depth + 1);
      }
    }

    for (final root in roots) {
      walk(root, 0);
    }
    for (final task in tasks) {
      walk(task, 0);
    }
    return nodes;
  }
}

class PublicProjectSection {
  PublicProjectSection({
    required this.id,
    this.name,
    required List<PublicTaskNode> tasks,
  }) : tasks = List.unmodifiable(tasks);

  final String id;
  final String? name;
  final List<PublicTaskNode> tasks;

  String title(String fallback) => name ?? fallback;
}

class PublicTaskNode {
  PublicTaskNode({
    required this.task,
    required this.depth,
    required List<PublicComment> comments,
  }) : comments = List.unmodifiable(comments);

  final PublicTask task;
  final int depth;
  final List<PublicComment> comments;
}

class PublicTask {
  PublicTask({
    required this.id,
    required this.content,
    this.parentId,
    this.status,
    this.creatorName,
    List<String> assigneeNames = const [],
    this.schedule,
    this.deadline,
  }) : assigneeNames = List.unmodifiable(assigneeNames);

  final String id;
  final String content;
  final String? parentId;
  final String? status;
  final String? creatorName;
  final List<String> assigneeNames;
  final TaskSchedule? schedule;
  final DateTime? deadline;

  bool get isCompleted => status == 'completed';
}

class PublicComment {
  PublicComment({
    required this.id,
    required this.body,
    this.author,
    this.createdAt,
  });

  final String id;
  final String body;
  final String? author;
  final String? createdAt;
}

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String> _names(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}

int _compareText(Object? a, Object? b) {
  if (a is! String) return b is String ? 1 : 0;
  if (b is! String) return -1;
  return a.compareTo(b);
}

DateTime? _deadline(Object? json) {
  if (json is! String) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final raw = decoded['date'];
  final parsed = raw is String ? DateTime.tryParse(raw) : null;
  return parsed == null
      ? null
      : DateTime(parsed.year, parsed.month, parsed.day);
}
