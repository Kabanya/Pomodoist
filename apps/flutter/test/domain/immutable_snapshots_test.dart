import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/productivity/productivity_models.dart';
import 'package:pomodoist/domain/models/planning/task_decomposition.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';

void main() {
  test('task snapshot owns an immutable copy of its assignees', () {
    final ids = <String>['alice'];
    final task = TaskItem(
      id: 'task',
      userId: 'owner',
      content: 'Task',
      projectId: inboxProjectId,
      priority: 4,
      status: 'active',
      completedFocusIntervals: 0,
      totalFocusSeconds: 0,
      orderKey: '1',
      isDeleted: false,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      assigneeIds: ids,
    );
    ids[0] = 'bob';
    expect(task.assigneeIds, ['alice']);
    expect(() => task.assigneeIds[0] = 'mallory', throwsUnsupportedError);
    expect(() => task.assigneeIds.add('mallory'), throwsUnsupportedError);
  });

  test('productivity snapshot owns an immutable copy of its days', () {
    final day = ProductivityDaySummary(
      localDate: DateTime.utc(2026),
      completedTasks: 2,
      completedFocusIntervals: 1,
      totalFocusSeconds: 1500,
    );
    final days = [day];
    final summary = ProductivitySummary(
      completedTasks: 2,
      completedFocusIntervals: 1,
      totalFocusSeconds: 1500,
      plannedFocusIntervals: 1,
      openTasks: 3,
      allTimeCompletedTasks: 2,
      allTimeCompletedFocusIntervals: 1,
      lastSevenDays: days,
    );
    days.clear();
    expect(summary.lastSevenDays, [day]);
    expect(() => summary.lastSevenDays[0] = day, throwsUnsupportedError);
    expect(() => summary.lastSevenDays.clear(), throwsUnsupportedError);
  });

  test('a voice draft owns its nested children', () {
    final children = <DecomposedTaskDraft>[
      DecomposedTaskDraft(quickAdd: 'original'),
    ];
    final draft = DecomposedTaskDraft(quickAdd: 'parent', subtasks: children);
    children.clear();
    expect(draft.subtasks.single.quickAdd, 'original');
    expect(() => draft.subtasks.clear(), throwsUnsupportedError);
  });
  test('shared scope snapshot owns nested transport collections', () {
    final members = <Map<String, dynamic>>[
      {'userId': 'a', 'role': 'member'},
    ];
    final scope = SharedScope.fromJson({
      'id': 'scope',
      'rootProjectId': 'root',
      'ownerId': 'owner',
      'role': 'member',
      'members': members,
    });
    members.first['role'] = 'administrator';
    expect((scope.data['members'] as List).first['role'], 'member');
    expect(
      () => (scope.data['members'] as List).clear(),
      throwsUnsupportedError,
    );
  });
}
