import 'dart:convert';
import 'package:timezone/timezone.dart' as tz;
import 'package:pomodoist/domain/models/tasks/task_models.dart';

enum TaskBlockReason { dependency, urgent, priority }

class UrgentTaskSelection {
  const UrgentTaskSelection({
    required this.taskId,
    this.seriesId,
    this.repeatWithSeries = true,
  });
  final String taskId;
  final String? seriesId;
  final bool repeatWithSeries;
}

class TaskAvailability {
  const TaskAvailability({
    required this.canStartFocus,
    required this.canComplete,
    this.reasons = const [],
    this.blockingTaskIds = const [],
  });
  final bool canStartFocus;
  final bool canComplete;
  final List<TaskBlockReason> reasons;
  final List<String> blockingTaskIds;
  void requireFocus() {
    if (!canStartFocus) throw TaskBlockedException(this);
  }

  void requireCompletion() {
    if (!canComplete) throw TaskBlockedException(this);
  }
}

class TaskBlockedException implements Exception {
  const TaskBlockedException(this.availability);
  factory TaskBlockedException.fromServer(Object? details) {
    Object? data = details;
    if (data is String) {
      try {
        data = jsonDecode(data);
      } on FormatException {
        data = null;
      }
    }
    final map = data is Map ? data : const {};
    return TaskBlockedException(
      TaskAvailability(
        canStartFocus: false,
        canComplete: false,
        reasons: [
          for (final reason in TaskBlockReason.values)
            if ((map['reasons'] as List? ?? const []).contains(reason.name))
              reason,
        ],
        blockingTaskIds: (map['blockingTaskIds'] as List? ?? const [])
            .whereType<String>()
            .toList(),
      ),
    );
  }
  final TaskAvailability availability;
  @override
  String toString() =>
      'task_blocked: ${availability.reasons.map((r) => r.name).join(', ')}';
}

/// Blocking restricts task completion; Focus only requires an editable open task.
class TaskBlockingPolicy {
  TaskBlockingPolicy({
    required Iterable<TaskItem> tasks,
    required this.actorId,
    this.priorityCascadeEnabled = false,
    this.timeZone = 'UTC',
    this.urgentSelections = const {},
    DateTime? now,
  }) : tasks = Map.unmodifiable({for (final task in tasks) task.id: task}),
       now = now ?? DateTime.now() {
    for (final task in this.tasks.values) {
      if (task.parentId != null) {
        (_children[task.parentId!] ??= []).add(task.id);
      }
    }
  }
  final Map<String, TaskItem> tasks;
  final String actorId;
  final bool priorityCascadeEnabled;
  final String timeZone;
  final Map<String, UrgentTaskSelection> urgentSelections;
  final DateTime now;
  final _children = <String, List<String>>{};

  String queueFor(TaskItem task) =>
      task.scopeId == null ? 'personal' : 'project:${task.projectId}';
  bool _own(TaskItem task) =>
      task.canEdit &&
      (task.scopeId == null || task.assigneeIds.contains(actorId));
  bool _open(TaskItem task, Set<String> completed) =>
      !task.isDeleted && !task.isCompleted && !completed.contains(task.id);
  DateTime _day(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);
  DateTime get _today => _day(
    tz.TZDateTime.from(
      now.toUtc(),
      (timeZone == 'UTC' ? tz.UTC : tz.getLocation(timeZone)),
    ),
  );
  DateTime? _date(TaskItem task) {
    final schedule = task.schedule;
    if (schedule == null) return null;
    return _day(
      schedule.isAllDay
          ? schedule.date!
          : tz.TZDateTime.from(
              schedule.start!,
              (timeZone == 'UTC' ? tz.UTC : tz.getLocation(timeZone)),
            ),
    );
  }

  bool _due(TaskItem task) =>
      _date(task) != null && !_date(task)!.isAfter(_today);
  Iterable<TaskItem> _ancestors(TaskItem task) sync* {
    final seen = <String>{task.id};
    var parent = tasks[task.parentId];
    while (parent != null && seen.add(parent.id)) {
      yield parent;
      parent = tasks[parent.parentId];
    }
  }

  Set<String> subtree(String id) {
    final result = <String>{};
    final pending = [id];
    while (pending.isNotEmpty) {
      final next = pending.removeLast();
      if (result.add(next)) pending.addAll(_children[next] ?? const []);
    }
    return result;
  }

  Set<String> _prerequisites(TaskItem task) => {
    ...task.prerequisiteIds,
    for (final ancestor in _ancestors(task)) ...ancestor.prerequisiteIds,
  };
  Set<String> _missing(TaskItem task, Set<String> completed) => {
    for (final id in _prerequisites(task))
      if (tasks[id] == null || _open(tasks[id]!, completed)) id,
  };
  Set<String> _path(String id, Set<String> completed) {
    final result = <String>{};
    final pending = [id];
    while (pending.isNotEmpty) {
      final next = pending.removeLast();
      if (!result.add(next)) continue;
      final task = tasks[next];
      if (task == null || !_open(task, completed)) continue;
      pending.addAll(_children[next] ?? const []);
      pending.addAll(_missing(task, completed));
    }
    return result;
  }

  TaskItem? _selected(String queue, Set<String> completed) {
    final selection = urgentSelections[queue];
    if (selection == null) return null;
    final source = tasks[selection.taskId];
    if (source == null || queueFor(source) != queue) {
      return null;
    }
    if (_open(source, const {}) && !_own(source)) return null;
    if (_open(source, completed) && _own(source)) return source;
    if (!selection.repeatWithSeries || selection.seriesId == null) return null;
    final next =
        tasks.values
            .where(
              (t) =>
                  _open(t, completed) &&
                  _own(t) &&
                  queueFor(t) == queue &&
                  t.schedule?.recurrenceSeriesKey == selection.seriesId,
            )
            .toList()
          ..sort((a, b) => (_date(a) ?? _today).compareTo(_date(b) ?? _today));
    return next.firstOrNull;
  }

  TaskItem? _activeUrgent(String queue, Set<String> completed) {
    final task = _selected(queue, completed);
    return task != null && (_date(task) == null || _due(task)) ? task : null;
  }

  UrgentTaskSelection? selectionFor(TaskItem task) =>
      _selected(queueFor(task), const {})?.id == task.id
      ? urgentSelections[queueFor(task)]
      : null;
  bool isUrgent(TaskItem task) => selectionFor(task) != null;

  ({Set<TaskBlockReason> reasons, Set<String> ids}) _blocks(
    TaskItem task,
    Set<String> completed,
  ) {
    final reasons = <TaskBlockReason>{};
    final ids = _missing(task, completed);
    if (ids.isNotEmpty) reasons.add(TaskBlockReason.dependency);
    if (!_own(task)) return (reasons: reasons, ids: ids);
    final queue = queueFor(task);
    final urgent = _activeUrgent(queue, const {});
    if (urgent != null && completed.contains(urgent.id)) {
      return (reasons: reasons, ids: ids);
    }
    if (urgent != null) {
      if (!_path(urgent.id, completed).contains(task.id)) {
        reasons.add(TaskBlockReason.urgent);
        ids.add(urgent.id);
      }
      return (reasons: reasons, ids: ids);
    }
    if (!priorityCascadeEnabled) return (reasons: reasons, ids: ids);
    // Include dependency steps outside Today without changing their saved rank.
    final rank = <String, int>{};
    final sources = tasks.values.where(
      (t) => _open(t, completed) && _own(t) && queueFor(t) == queue && _due(t),
    );
    for (final source in sources) {
      for (final id in _path(source.id, completed)) {
        final step = tasks[id];
        if (step == null ||
            !_open(step, completed) ||
            !_own(step) ||
            queueFor(step) != queue ||
            _missing(step, completed).isNotEmpty) {
          continue;
        }
        final value = rank[id];
        if (value == null || source.priority < value) {
          rank[id] = source.priority;
        }
      }
    }
    if (rank.isNotEmpty && (_due(task) || rank.containsKey(task.id))) {
      final best = rank.values.reduce((a, b) => a < b ? a : b);
      if ((rank[task.id] ?? task.priority) > best) {
        reasons.add(TaskBlockReason.priority);
        ids.addAll(rank.keys.where((id) => rank[id] == best));
      }
    }
    return (reasons: reasons, ids: ids);
  }

  TaskAvailability availability(
    String? taskId, {
    Set<String> completingIds = const {},
  }) {
    if (taskId == null) {
      return const TaskAvailability(canStartFocus: true, canComplete: false);
    }
    final task = tasks[taskId];
    if (task == null || task.isDeleted || task.isCompleted || !task.canEdit) {
      return const TaskAvailability(canStartFocus: false, canComplete: false);
    }
    final focus = _blocks(task, completingIds);
    final batch = {...completingIds, ...subtree(taskId)};
    final completionReasons = <TaskBlockReason>{};
    final completionIds = <String>{};
    for (final id in subtree(taskId)) {
      final child = tasks[id];
      if (child == null || child.isDeleted || child.isCompleted) continue;
      final blocked = _blocks(child, batch);
      completionReasons.addAll(blocked.reasons);
      completionIds.addAll(blocked.ids);
    }
    return TaskAvailability(
      canStartFocus: true,
      canComplete: completionReasons.isEmpty,
      reasons: List.unmodifiable({...focus.reasons, ...completionReasons}),
      blockingTaskIds: List.unmodifiable({...focus.ids, ...completionIds}),
    );
  }

  void validateDependencies(String taskId, List<String> prerequisites) {
    final task = tasks[taskId];
    if (task == null ||
        prerequisites.length > 200 ||
        prerequisites.toSet().length != prerequisites.length) {
      throw ArgumentError('Invalid task dependencies');
    }
    for (final id in prerequisites) {
      final predecessor = tasks[id];
      if (predecessor == null ||
          predecessor.isDeleted ||
          id == taskId ||
          predecessor.scopeId != task.scopeId ||
          task.scopeId != null && predecessor.projectId != task.projectId ||
          _ancestors(task).any((t) => t.id == id) ||
          subtree(taskId).contains(id)) {
        throw ArgumentError(
          'Dependencies must reference available tasks outside their own branch in the same scope',
        );
      }
    }
    final visiting = <String>{}, visited = <String>{};
    void visit(String id) {
      if (visited.contains(id)) return;
      if (!visiting.add(id)) {
        throw ArgumentError('Task dependencies cannot contain a cycle');
      }
      final current = tasks[id];
      if (current != null && !current.isDeleted) {
        for (final next in {
          ...(id == taskId ? prerequisites : current.prerequisiteIds),
          ...?_children[id],
        }) {
          visit(next);
        }
      }
      visiting.remove(id);
      visited.add(id);
    }

    for (final id in tasks.keys) {
      visit(id);
    }
  }
}
