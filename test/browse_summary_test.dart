import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/core/db/app_database.dart' show inboxProjectId;
import 'package:pomodoist/features/productivity/domain/productivity_models.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';
import 'package:pomodoist/features/tasks/presentation/browse_summary.dart';
import 'package:pomodoist/features/tasks/presentation/project_list_data.dart';

void main() {
  test('periods use daily totals and keep the current open count', () {
    final days = List.generate(
      7,
      (index) => ProductivityDaySummary(
        localDate: DateTime(2026, 9, 3 + index),
        completedTasks: index,
        completedFocusIntervals: index * 2,
        totalFocusSeconds: index * 600,
      ),
    );
    final summary = ProductivitySummary(
      completedTasks: 6,
      completedFocusIntervals: 12,
      totalFocusSeconds: 3600,
      plannedFocusIntervals: 9,
      openTasks: 17,
      allTimeCompletedTasks: 1000,
      allTimeCompletedFocusIntervals: 2000,
      lastSevenDays: days,
    );

    expect(browseSummary(summary, BrowsePeriod.today), (
      completedTasks: 6,
      focusIntervals: 12,
      focusSeconds: 3600,
      openTasks: 17,
    ));
    expect(browseSummary(summary, BrowsePeriod.sevenDays), (
      completedTasks: 21,
      focusIntervals: 42,
      focusSeconds: 12600,
      openTasks: 17,
    ));
    // Switching back neither mutates the source nor adds today's totals twice.
    expect(browseSummary(summary, BrowsePeriod.today).completedTasks, 6);
    expect(summary.lastSevenDays, same(days));
  });

  test('an empty week does not fall back to all-time totals', () {
    const summary = ProductivitySummary(
      completedTasks: 0,
      completedFocusIntervals: 0,
      totalFocusSeconds: 0,
      plannedFocusIntervals: 0,
      openTasks: 3,
      allTimeCompletedTasks: 42,
      allTimeCompletedFocusIntervals: 64,
    );
    for (final period in BrowsePeriod.values) {
      expect(browseSummary(summary, period), (
        completedTasks: 0,
        focusIntervals: 0,
        focusSeconds: 0,
        openTasks: 3,
      ));
    }
  });

  test('project counts include direct open tasks and subtasks only', () {
    final counts = countOpenTasksByProject([
      _task('1', 'parent'),
      _task('2', 'parent', parentId: '1'),
      _task('3', 'child'),
      _task('4', 'parent', completed: true),
      _task('5', 'parent', deleted: true),
      _task('6', inboxProjectId),
    ]);
    expect(counts, {'parent': 2, 'child': 1});
    expect(countOpenTasksByProject([]), isEmpty);
  });

  test('project rows preserve sibling order, nesting and orphan roots', () {
    final rows = projectRows([
      _project('child', parentId: 'parent'),
      _project('first'),
      _project('parent'),
      _project('sibling', parentId: 'parent'),
      _project('grandchild', parentId: 'child'),
      _project('orphan', parentId: 'hidden'),
    ]);
    expect(rows.map((row) => (row.project.id, row.depth)), [
      ('first', 0),
      ('parent', 0),
      ('child', 1),
      ('grandchild', 2),
      ('sibling', 1),
      ('orphan', 0),
    ]);
  });
}

TaskItem _task(
  String id,
  String projectId, {
  bool completed = false,
  bool deleted = false,
  String? parentId,
}) => TaskItem(
  id: id,
  userId: 'user',
  content: id,
  projectId: projectId,
  parentId: parentId,
  priority: 4,
  status: completed ? 'completed' : 'active',
  completedFocusIntervals: 0,
  totalFocusSeconds: 0,
  orderKey: id,
  isDeleted: deleted,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

ProjectItem _project(String id, {String? parentId}) => ProjectItem(
  id: id,
  userId: 'user',
  name: id,
  orderKey: id,
  parentId: parentId,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);
