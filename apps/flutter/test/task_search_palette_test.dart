import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';
import 'package:pomodoist/features/tasks/presentation/task_search_palette.dart';

void main() {
  final now = DateTime.utc(2026);
  TaskItem task(String id, {bool completed = false, bool deleted = false}) =>
      TaskItem(
        id: id,
        userId: 'user',
        projectId: 'inbox',
        content: 'Title',
        description: 'Release notes',
        orderKey: id,
        createdAt: now,
        updatedAt: now,
        status: completed ? 'completed' : 'open',
        priority: 4,
        completedFocusIntervals: 0,
        totalFocusSeconds: 0,
        isDeleted: deleted,
      );
  ProjectItem project(
    String id, {
    bool archived = false,
    bool deleted = false,
  }) => ProjectItem(
    id: id,
    userId: 'user',
    name: 'Release $id',
    orderKey: id,
    createdAt: now,
    updatedAt: now,
    isArchived: archived,
    isDeleted: deleted,
  );

  test(
    'local results match descriptions and active project names with separate limits',
    () {
      final results = taskSearchPaletteResults(
        [
          task('completed', completed: true),
          task('deleted', deleted: true),
          for (var i = 0; i < 9; i++) task('$i'),
        ],
        [
          project('archived', archived: true),
          project('deleted', deleted: true),
          for (var i = 0; i < 5; i++) project('$i'),
        ],
        ' ReLeAsE ',
      );
      expect(results.map((result) => result.id), [
        for (var i = 0; i < 6; i++) 'task:$i',
        for (var i = 0; i < 3; i++) 'project:$i',
      ]);
      expect(
        taskSearchPaletteResults([task('a')], [project('a')], '  '),
        isEmpty,
      );
      expect(
        taskSearchPaletteResults([task('a')], [project('a')], 'missing'),
        isEmpty,
      );
    },
  );

  test(
    'selection follows identity across reordered rows and wraps at either end',
    () {
      expect(taskSearchPaletteSelection(['b', 'a', 'create'], 'a', 0), 'a');
      expect(taskSearchPaletteSelection(['a', 'create'], 'a', -1), 'create');
      expect(taskSearchPaletteSelection(['a', 'create'], 'create', 1), 'a');
      expect(taskSearchPaletteSelection(['b', 'create'], 'removed', 0), isNull);
      expect(taskSearchPaletteSelection(['b', 'create'], null, 0), isNull);
      expect(taskSearchPaletteSelection(['b', 'create'], null, 1), 'b');
      expect(taskSearchPaletteSelection([], 'removed', 1), isNull);
    },
  );

  test('activation rejects removed ids and query changes before rebuild', () {
    expect(
      taskSearchPaletteCanActivate(['b', 'create'], 'a', 'query', 'query'),
      isFalse,
    );
    expect(
      taskSearchPaletteCanActivate(['a', 'create'], 'a', 'old', 'new'),
      isFalse,
    );
    expect(
      taskSearchPaletteCanActivate(['b', 'a', 'create'], 'a', 'query', 'query'),
      isTrue,
    );
  });
}
