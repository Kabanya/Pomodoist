import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/view_models/task_list_view_model.dart';
import 'package:pomodoist/ui/tasks/view_models/task_subtask_progress.dart';

void main() {
  test(
    'groups annotate complete branches without grouping unrelated tasks',
    () {
      final tasks = [
        _task('a'),
        _task('b', parentId: 'a'),
        _task('c', parentId: 'b'),
        _task('d', parentId: 'a'),
        _task('e'),
      ];
      final rows = visibleTaskRows(tasks, tasks, expansion: {'b': true});
      expect(rows.map((r) => r.task.id), ['a', 'b', 'c', 'd', 'e']);
      expect(rows.map((r) => r.groupRootId), ['a', 'a', 'a', 'a', null]);
      expect(rows.where((r) => r.startsGroup).map((r) => r.task.id), ['a']);
      expect(rows.where((r) => r.endsGroup).map((r) => r.task.id), ['d']);
      expect(rows[2].groupDisplayDepth, 2);
    },
  );

  test(
    'collapsed branches keep a single closed block and independent siblings',
    () {
      final tasks = [
        _task('a'),
        _task('b', parentId: 'a'),
        _task('c'),
        _task('d', parentId: 'c'),
      ];
      final rows = visibleTaskRows(tasks, tasks, expansion: {'a': false});
      expect(rows.first.startsGroup, isTrue);
      expect(rows.first.endsGroup, isTrue);
      expect(rows.map((r) => r.groupRootId), ['a', 'c', 'c']);
    },
  );

  test(
    'group membership never pulls tasks from other day or filter selections',
    () {
      final tasks = [
        _task('a'),
        _task('b', parentId: 'a'),
        _task('c', parentId: 'b'),
      ];
      final parentDay = visibleTaskRows(tasks, [tasks.first]);
      final childDay = visibleTaskRows(tasks, tasks.skip(1).toList());
      expect(parentDay.single.groupRootId, isNull);
      expect(childDay.map((r) => r.task.id), ['b', 'c']);
      expect(childDay.map((r) => r.groupRootId), ['b', 'b']);
      expect(childDay.first.ancestors.single.id, 'a');
    },
  );

  test(
    'details regroup displayed subtrees after removing their owning task',
    () {
      final tasks = [
        _task('a'),
        _task('b', parentId: 'a'),
        _task('c', parentId: 'b'),
        _task('d', parentId: 'a'),
      ];
      final projected = visibleTaskRows(tasks, tasks, expansion: {'b': true});
      final rows = withTaskBranchGroups(projected.skip(1).toList());
      expect(rows.map((r) => r.groupRootId), ['b', 'b', null]);
      expect(rows.first.startsGroup, isTrue);
      expect(rows.first.groupDisplayDepth, 0);
      expect(rows[1].groupDisplayDepth, 1);
      expect(rows[1].endsGroup, isTrue);
    },
  );

  test('retained and restored descendants keep the group endpoint current', () {
    final root = _task('a');
    final child = _task('b', parentId: 'a');
    final completed = _task('b', parentId: 'a', completed: true);
    final retained = visibleTaskRows([root], [root, completed]);
    expect(retained.last.endsGroup, isTrue);
    expect(retained.last.task.isCompleted, isTrue);
    final settled = visibleTaskRows([root, completed], [root]);
    expect(settled.single.groupRootId, isNull);
    final undone = visibleTaskRows([root, child], [root, child]);
    expect(undone.first.startsGroup, isTrue);
    expect(undone.last.endsGroup, isTrue);
    expect(undone.last.task.isCompleted, isFalse);
  });

  test('opens roots and collapses nested branches by default', () {
    final tasks = [
      _task('root'),
      _task('child', parentId: 'root'),
      _task('grandchild', parentId: 'child'),
    ];
    expect(visibleTaskRows(tasks, tasks).map((r) => r.task.id), [
      'root',
      'child',
    ]);
  });

  test(
    'stored expansion applies independently without leaking hidden rows',
    () {
      final tasks = [
        _task('r'),
        _task('a', parentId: 'r'),
        _task('b', parentId: 'a'),
        _task('other'),
      ];
      expect(
        visibleTaskRows(
          tasks,
          tasks,
          expansion: {'a': true},
        ).map((r) => r.task.id),
        ['other', 'r', 'a', 'b'],
      );
      expect(
        visibleTaskRows(
          tasks,
          tasks,
          expansion: {'r': false, 'a': true},
        ).map((r) => r.task.id),
        ['other', 'r'],
      );
      final filtered = visibleTaskRows(
        tasks,
        [tasks[2]],
        expansion: {'r': false, 'a': false},
      );
      expect(filtered.single.task.id, 'b');
      expect(filtered.single.visibleParentId, isNull);
      expect(filtered.single.ancestors.map((t) => t.id), ['r', 'a']);
    },
  );

  test('deep nesting keeps ancestry while capping only visual indentation', () {
    final tasks = [
      for (var i = 0; i < 5; i++)
        _task('$i', parentId: i == 0 ? null : '${i - 1}'),
    ];
    final rows = visibleTaskRows(
      tasks,
      tasks,
      expansion: {for (final t in tasks) t.id: true},
    );
    expect(rows.last.depth, 4);
    expect(rows.last.displayDepth, 2);
    expect(rows.last.needsAncestorContext, isTrue);
    expect(rows.last.ancestors.map((t) => t.id), ['0', '1', '2', '3']);
    expect(descendantTaskIds('0', tasks), {'1', '2', '3', '4'});
  });

  test('connector continuations follow visible siblings and survive Undo', () {
    final tasks = [
      _task('r'),
      _task('a', parentId: 'r'),
      _task('leaf', parentId: 'a'),
      _task('z', parentId: 'r'),
    ];
    const expansion = {'a': true};
    final rows = visibleTaskRows(tasks, tasks, expansion: expansion);
    expect(rows[2].ancestorContinuations, [false, true]);
    expect(rows[2].isLastSibling, isTrue);
    expect(rows.last.isLastSibling, isTrue);
    final removed = visibleTaskRows(
      tasks,
      tasks.where((t) => t.id != 'z').toList(),
      expansion: expansion,
    );
    expect(removed.last.ancestorContinuations, [false, false]);
    expect(
      visibleTaskRows(tasks, tasks, expansion: expansion).map((r) => r.task.id),
      rows.map((r) => r.task.id),
    );
  });

  test('capped rail continues from a deep last child to its visible uncle', () {
    final tasks = _deepBranchTasks();
    final rows = visibleTaskRows(
      tasks,
      tasks,
      expansion: {'b': true, 'c': true},
    );
    expect(rows.map((r) => r.task.id), ['a', 'b', 'c', 'd', 'e']);
    expect(rows.map((r) => r.depth), [0, 1, 2, 3, 2]);
    expect(rows.map((r) => r.continuesDisplayRail), [
      false,
      false,
      true,
      true,
      false,
    ]);
    expect(rows[3].isLastSibling, isTrue);
    expect(rows[3].visibleParentId, 'c');
    expect(rows[3].ancestors.map((t) => t.id), ['a', 'b', 'c']);
  });

  test('capped rail spans deeper descendants and stops at a shallower row', () {
    final tasks = [
      ..._deepBranchTasks(),
      _task('d1', parentId: 'd'),
      _task('f', parentId: 'a'),
      _task('z'),
    ];
    final rows = visibleTaskRows(
      tasks,
      tasks,
      expansion: {'b': true, 'c': true, 'd': true},
    );
    expect(rows.map((r) => r.task.id), [
      'a',
      'b',
      'c',
      'd',
      'd1',
      'e',
      'f',
      'z',
    ]);
    expect(rows.map((r) => r.continuesDisplayRail), [
      false,
      true,
      true,
      true,
      true,
      false,
      false,
      false,
    ]);
    expect(rows[4].ancestorContinuations[1], isTrue);
  });

  test('collapse and filtering recompute the final capped rail endpoint', () {
    final tasks = _deepBranchTasks();
    final collapsed = visibleTaskRows(tasks, tasks, expansion: {'b': true});
    expect(collapsed.map((r) => r.task.id), ['a', 'b', 'c', 'e']);
    expect(collapsed.map((r) => r.continuesDisplayRail), [
      false,
      false,
      true,
      false,
    ]);
    final filtered = visibleTaskRows(
      tasks,
      tasks.where((t) => t.id != 'e').toList(),
      expansion: {'b': true, 'c': true},
    );
    expect(filtered.map((r) => r.task.id), ['a', 'b', 'c', 'd']);
    expect(filtered.map((r) => r.continuesDisplayRail), [
      false,
      false,
      true,
      false,
    ]);
  });

  test(
    'completion retention and Undo keep the capped rail endpoint current',
    () {
      final tasks = _deepBranchTasks();
      final completed = _task('e', parentId: 'b', completed: true);
      final open = tasks.where((t) => t.id != 'e').toList();
      const expansion = {'b': true, 'c': true};
      final retained = visibleTaskRows(open, [
        ...open,
        completed,
      ], expansion: expansion);
      expect(retained[3].continuesDisplayRail, isTrue);
      expect(retained.last.continuesDisplayRail, isFalse);
      expect(retained.last.task.isCompleted, isTrue);
      final settled = visibleTaskRows(tasks, open, expansion: expansion);
      expect(settled.last.task.id, 'd');
      expect(settled.last.continuesDisplayRail, isFalse);
      final undone = visibleTaskRows(tasks, tasks, expansion: expansion);
      expect(undone[3].continuesDisplayRail, isTrue);
      expect(undone.last.task.isCompleted, isFalse);
    },
  );

  test('details reannotation replaces stale capped rail continuation', () {
    final tasks = _deepBranchTasks();
    final projected = visibleTaskRows(
      tasks,
      tasks,
      expansion: {'b': true, 'c': true},
    );
    final children = withTaskBranchGroups(projected.skip(1).toList());
    expect(children.map((r) => r.continuesDisplayRail), [
      false,
      true,
      true,
      false,
    ]);
    final shortened = withTaskBranchGroups(children.take(3).toList());
    expect(shortened.last.task.id, 'd');
    expect(shortened.last.continuesDisplayRail, isFalse);
  });

  test(
    'shallow last siblings do not extend their incoming rail to children',
    () {
      final tasks = [
        _task('a'),
        _task('b', parentId: 'a'),
        _task('c', parentId: 'b'),
        _task('z'),
      ];
      final rows = visibleTaskRows(tasks, tasks, expansion: {'b': true});
      expect(rows.map((r) => r.continuesDisplayRail), [
        false,
        false,
        false,
        false,
      ]);
      expect(rows[1].hasVisibleChildren, isTrue);
    },
  );

  test(
    'missing parent has no fabricated path and collapsed cycles stay closed',
    () {
      final orphan = _task('orphan', parentId: 'missing');
      expect(visibleTaskRows([orphan], [orphan]).single.ancestors, isEmpty);
      final cycle = [_task('a', parentId: 'b'), _task('b', parentId: 'a')];
      expect(
        visibleTaskRows(cycle, cycle, expansion: {'a': false, 'b': false}),
        hasLength(1),
      );
    },
  );

  test('filtered parent does not leave phantom indentation', () {
    final root = _task('root');
    final child = _task('child', parentId: 'root');
    final rows = visibleTaskRows([root, child], [child]);
    expect(rows.single.depth, 0);
  });

  test('current eligible snapshot overrides ancestry metadata', () {
    final stale = _task('child', parentId: 'root');
    final current = _task('child', content: 'Current');
    final rows = visibleTaskRows([_task('root'), stale], [current]);
    expect(rows.single.task.content, 'Current');
    expect(rows.single.depth, 0);
  });

  test('duplicates and cycles keep each eligible task once', () {
    final tasks = [
      _task('a', parentId: 'b'),
      _task('b', parentId: 'a'),
      _task('self', parentId: 'self'),
      _task('orphan', parentId: 'missing'),
    ];
    final rows = visibleTaskRows(tasks, [...tasks, tasks.first]);
    expect(rows.map((r) => r.task.id).toSet(), {'a', 'b', 'self', 'orphan'});
    expect(rows, hasLength(4));
  });

  test('progress counts all descendants without counting self in a cycle', () {
    final progress = taskSubtaskProgressById([
      _task('a', parentId: 'b', completed: true),
      _task('b', parentId: 'a'),
      _task('c', parentId: 'b', completed: true),
      _task('self', parentId: 'self'),
    ]);
    expect(progress['a']!.label, '1/2');
    expect(progress['b']!.label, '2/2');
    expect(progress.containsKey('self'), isFalse);
  });

  test('current visible snapshots replace retained snapshots', () {
    final retained = _task('retained', content: 'Stale', completed: true);
    final current = _task('retained', content: 'Current');
    final state = TaskListState(
      tasks: AsyncData([current, _task('filtered', completed: true)]),
      allTasks: [],
    );
    final visible = state.visibleTasks([retained], (t) => !t.isCompleted);
    expect(visible.map((t) => t.content), ['Current']);
  });
}

List<TaskItem> _deepBranchTasks() => [
  _task('a'),
  _task('b', parentId: 'a'),
  _task('c', parentId: 'b'),
  _task('d', parentId: 'c'),
  _task('e', parentId: 'b'),
];

TaskItem _task(
  String id, {
  String? parentId,
  String? content,
  bool completed = false,
  int? dayOrder,
  String? orderKey,
}) => TaskItem(
  id: id,
  userId: 'user',
  content: content ?? id,
  projectId: 'project',
  parentId: parentId,
  priority: 4,
  status: completed ? 'completed' : 'open',
  completedFocusIntervals: 0,
  totalFocusSeconds: 0,
  orderKey: orderKey ?? id,
  dayOrder: dayOrder,
  isDeleted: false,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
