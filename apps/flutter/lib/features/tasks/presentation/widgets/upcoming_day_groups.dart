import '../../domain/task_models.dart';

class UpcomingDayGroup {
  const UpcomingDayGroup({
    required this.date,
    required this.rows,
    this.isSynthetic = false,
  });

  final DateTime date;
  final List<UpcomingTaskRow> rows;
  final bool isSynthetic;
}

class UpcomingTaskRow {
  const UpcomingTaskRow({required this.task, required this.depth});

  final TaskItem task;
  final int depth;
}

List<UpcomingDayGroup> buildUpcomingDayGroups(
  Iterable<TaskItem> tasks, {
  DateTime? selectedDate,
  DateTime? visibleFromDate,
}) {
  final tasksByDate = <DateTime, List<TaskItem>>{};
  final firstVisibleDay = visibleFromDate == null
      ? null
      : _localDateOnly(visibleFromDate);
  for (final task in tasks) {
    final schedule = task.schedule;
    if (schedule == null) {
      continue;
    }
    final date = _localDateOnly(schedule.displayDate);
    if (firstVisibleDay != null && date.isBefore(firstVisibleDay)) {
      continue;
    }
    tasksByDate.putIfAbsent(date, () => []).add(task);
  }

  final selectedDay = selectedDate == null
      ? null
      : _localDateOnly(selectedDate);
  if (selectedDay != null) {
    tasksByDate.putIfAbsent(selectedDay, () => []);
  }

  final dates = tasksByDate.keys.toList()..sort();
  return List.unmodifiable(
    dates.map((date) {
      final dayTasks = tasksByDate[date]!;
      return UpcomingDayGroup(
        date: date,
        rows: _buildRows(dayTasks),
        isSynthetic: dayTasks.isEmpty && date == selectedDay,
      );
    }),
  );
}

List<UpcomingTaskRow> _buildRows(List<TaskItem> tasks) {
  final byId = <String, TaskItem>{for (final task in tasks) task.id: task};
  final childrenByParent = <String, List<TaskItem>>{};
  final roots = <TaskItem>[];

  for (final task in tasks) {
    final parentId = task.parentId;
    if (parentId == null || !byId.containsKey(parentId)) {
      roots.add(task);
    } else {
      childrenByParent.putIfAbsent(parentId, () => []).add(task);
    }
  }
  roots.sort(_compareRootOrder);
  for (final children in childrenByParent.values) {
    children.sort(_compareTaskOrder);
  }

  final rows = <UpcomingTaskRow>[];
  final visited = <String>{};

  void addSubtree(TaskItem task, int depth) {
    if (!visited.add(task.id)) {
      return;
    }
    rows.add(UpcomingTaskRow(task: task, depth: depth));
    for (final child in childrenByParent[task.id] ?? const <TaskItem>[]) {
      addSubtree(child, depth + 1);
    }
  }

  for (final root in roots) {
    addSubtree(root, 0);
  }

  final remaining = tasks.toList()..sort(_compareRootOrder);
  for (final task in remaining) {
    if (!visited.contains(task.id)) {
      addSubtree(task, 0);
    }
  }

  return List.unmodifiable(rows);
}

int _compareTaskOrder(TaskItem a, TaskItem b) {
  final aDayOrder = a.dayOrder;
  final bDayOrder = b.dayOrder;
  if (aDayOrder == null && bDayOrder != null) {
    return 1;
  }
  if (aDayOrder != null && bDayOrder == null) {
    return -1;
  }
  if (aDayOrder != null && bDayOrder != null) {
    final dayOrder = aDayOrder.compareTo(bDayOrder);
    if (dayOrder != 0) {
      return dayOrder;
    }
  }

  final orderKey = a.orderKey.compareTo(b.orderKey);
  if (orderKey != 0) {
    return orderKey;
  }
  return a.id.compareTo(b.id);
}

int _compareRootOrder(TaskItem a, TaskItem b) {
  if (a.isCompleted != b.isCompleted) {
    return a.isCompleted ? -1 : 1;
  }
  return _compareTaskOrder(a, b);
}

DateTime _localDateOnly(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}
