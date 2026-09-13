import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';
import 'package:pomodoist/features/tasks/presentation/task_search.dart';

void main() {
  final cutoff = DateTime.utc(2026, 6, 1);
  final tasks = [
    _task('b', content: 'Plan release'),
    _task('a', description: 'RELEASE notes', project: 'other'),
    _task('done', completed: true, completedAt: cutoff),
    _task(
      'old',
      completed: true,
      completedAt: cutoff.subtract(const Duration(seconds: 1)),
    ),
    _task('deleted', deleted: true),
  ];

  test('matches trimmed case-insensitive titles and descriptions in order', () {
    expect(filterTaskSearch(tasks, query: ' ReLeAsE ').map((t) => t.id), [
      'a',
      'b',
    ]);
    expect(filterTaskSearch(tasks, query: '   '), isEmpty);
    expect(filterTaskSearch(tasks, query: 'unknown'), isEmpty);
  });

  test('project and completion status combine with the query', () {
    expect(
      filterTaskSearch(
        tasks,
        query: 'release',
        projectId: 'other',
      ).map((t) => t.id),
      ['a'],
    );
    expect(
      filterTaskSearch(
        tasks,
        query: 'release',
        status: TaskSearchStatus.completed,
        completedTaskCutoff: cutoff,
      ).map((t) => t.id),
      ['done'],
    );
    expect(
      filterTaskSearch(
        tasks,
        query: 'release',
        status: TaskSearchStatus.all,
        completedTaskCutoff: cutoff,
      ).map((t) => t.id),
      ['a', 'b', 'done'],
    );
  });

  test(
    'clearing filters broadens status and projects without clearing query',
    () {
      const query = 'release';
      final filtered = filterTaskSearch(
        tasks,
        query: query,
        projectId: 'other',
      );
      final cleared = filterTaskSearch(
        tasks,
        query: query,
        status: TaskSearchStatus.all,
      );
      expect(filtered.map((t) => t.id), ['a']);
      expect(cleared.map((t) => t.id), ['a', 'b', 'done', 'old']);
      expect(cleared.any((t) => t.isDeleted), isFalse);
    },
  );

  test('history uses updatedAt fallback and does not restrict open tasks', () {
    final oldDate = cutoff.subtract(const Duration(days: 1));
    final items = [
      _task('open', updatedAt: oldDate),
      _task('completed', completed: true, updatedAt: oldDate),
    ];
    expect(
      filterTaskSearch(
        items,
        query: 'release',
        status: TaskSearchStatus.all,
        completedTaskCutoff: cutoff,
      ).map((t) => t.id),
      ['open'],
    );
    expect(
      filterTaskSearch(
        items,
        query: 'release',
        status: TaskSearchStatus.all,
      ).length,
      2,
    );
  });

  test('keeps existing day order before orderKey sorting', () {
    expect(
      filterTaskSearch([
        _task('a'),
        _task('c', dayOrder: 0),
        _task('b', dayOrder: 0),
      ], query: 'release').map((t) => t.id),
      ['b', 'c', 'a'],
    );
  });
}

TaskItem _task(
  String id, {
  String content = 'Release',
  String? description,
  String project = 'project',
  bool completed = false,
  bool deleted = false,
  DateTime? completedAt,
  DateTime? updatedAt,
  int? dayOrder,
}) {
  final now = DateTime.utc(2026, 9, 9);
  return TaskItem(
    id: id,
    userId: 'user',
    content: content,
    description: description,
    projectId: project,
    priority: 4,
    status: completed ? 'completed' : 'open',
    completedFocusIntervals: 0,
    totalFocusSeconds: 0,
    orderKey: id,
    dayOrder: dayOrder,
    isDeleted: deleted,
    createdAt: now,
    updatedAt: updatedAt ?? now,
    completedAt: completedAt,
  );
}
