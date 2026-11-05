import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/tasks/task_blocking.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/view_models/task_item_view_model.dart';

TaskItem task(
  String id, {
  List<String> needs = const [],
  String status = 'open',
  bool deleted = false,
}) => TaskItem(
  id: id,
  userId: 'me',
  content: id,
  projectId: 'inbox',
  priority: 4,
  status: status,
  completedFocusIntervals: 0,
  totalFocusSeconds: 0,
  orderKey: id,
  isDeleted: deleted,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  prerequisiteIds: needs,
);

void main() {
  test('ordinary and loading rows have no blocking decoration', () {
    final item = task('ordinary');
    expect(TaskRowBlockingStatus.resolve(item, null), isNull);
    expect(
      TaskRowBlockingStatus.resolve(
        item,
        TaskBlockingPolicy(tasks: [item], actorId: 'me'),
      ),
      isNull,
    );
  });

  test('urgent task is warm while tasks it blocks show a lock', () {
    final urgent = task('urgent');
    final other = task('other');
    final policy = TaskBlockingPolicy(
      tasks: [urgent, other],
      actorId: 'me',
      urgentSelections: {
        'personal': const UrgentTaskSelection(taskId: 'urgent'),
      },
    );
    expect(
      TaskRowBlockingStatus.resolve(urgent, policy),
      TaskRowBlockingStatus.urgent,
    );
    expect(
      TaskRowBlockingStatus.resolve(other, policy),
      TaskRowBlockingStatus.blocked,
    );
  });

  test(
    'dependency lock takes precedence over urgency without blocking Focus',
    () {
      final urgent = task('urgent', needs: ['first']);
      final policy = TaskBlockingPolicy(
        tasks: [task('first'), urgent],
        actorId: 'me',
        urgentSelections: {
          'personal': const UrgentTaskSelection(taskId: 'urgent'),
        },
      );
      expect(policy.availability(urgent.id).canStartFocus, isTrue);
      expect(
        TaskRowBlockingStatus.resolve(urgent, policy),
        TaskRowBlockingStatus.blocked,
      );
    },
  );

  test('completion and deletion hide stale urgency and sync conflicts', () {
    final open = task('urgent');
    final policy = TaskBlockingPolicy(
      tasks: [open],
      actorId: 'me',
      urgentSelections: {
        'personal': const UrgentTaskSelection(taskId: 'urgent'),
      },
    );
    for (final inactive in [
      task('urgent', status: 'completed'),
      task('urgent', deleted: true),
    ]) {
      expect(
        TaskRowBlockingStatus.resolve(inactive, policy, syncConflict: true),
        isNull,
      );
      expect(
        TaskRowBlockingStatus.resolve(
          open,
          TaskBlockingPolicy(tasks: [inactive], actorId: 'me'),
        ),
        isNull,
      );
    }
  });

  test('sync conflict remains visible even while policy is loading', () {
    expect(
      TaskRowBlockingStatus.resolve(task('conflict'), null, syncConflict: true),
      TaskRowBlockingStatus.blocked,
    );
  });
}
