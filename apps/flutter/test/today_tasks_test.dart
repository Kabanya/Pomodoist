import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/planning/presentation/today_tasks.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';

void main() {
  test('completed today uses local completion date and legacy fallback', () {
    final today = DateTime(2026, 9, 9);
    TaskItem task(
      String id,
      DateTime updated, {
      DateTime? completed,
      bool deleted = false,
      String status = 'completed',
    }) => TaskItem(
      id: id,
      userId: 'user',
      content: id,
      projectId: 'inbox',
      priority: 4,
      status: status,
      completedFocusIntervals: 0,
      totalFocusSeconds: 0,
      orderKey: id,
      isDeleted: deleted,
      createdAt: today,
      updatedAt: updated,
      completedAt: completed,
    );
    final end = DateTime(2026, 9, 9, 23, 59, 59);
    final items = [
      task('legacy', today),
      task('utc', today, completed: end.toUtc()),
      task('old', today, completed: today.subtract(const Duration(days: 1))),
      task('future', today, completed: DateTime(2026, 9, 10)),
      task('deleted', today, deleted: true),
      task('open', today, status: 'open'),
    ];
    expect(completedTasksForDay(items, today).map((task) => task.id), [
      'legacy',
      'utc',
    ]);
  });
}
