import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/view_models/priority_matrix_view_model.dart';

void main() {
  test(
    'matrix exposes live open tasks and keeps animation rows out of selection',
    () async {
      final source = StreamController<List<TaskItem>>();
      final container = ProviderContainer(
        overrides: [
          tasksByQueryProvider(
            const TaskQuery.all(),
          ).overrideWith((_) => source.stream),
        ],
      );
      addTearDown(source.close);
      addTearDown(container.dispose);
      final subscription = container.listen(
        priorityMatrixViewModelProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      final open = _task('open', priority: 3);
      final completed = _task('done', priority: 1, completed: true);
      source.add([open, completed]);
      await pumpEventQueue();

      final state = container.read(priorityMatrixViewModelProvider);
      expect(state.tasks.requireValue, [open]);
      expect(state.buckets[3], [open]);
      expect(state.buckets[1], isEmpty);
      expect(() => state.tasks.requireValue.clear(), throwsUnsupportedError);
      expect(state.tasksById, {'open': open});
      expect(() => state.tasksById.clear(), throwsUnsupportedError);

      source.add([_task('open', priority: 3, completed: true), completed]);
      await pumpEventQueue();
      expect(
        container.read(priorityMatrixViewModelProvider).tasks.requireValue,
        isEmpty,
      );
      expect(
        container.read(priorityMatrixViewModelProvider).tasksById,
        isEmpty,
      );
      final viewModel = container.read(
        priorityMatrixViewModelProvider.notifier,
      );
      expect(viewModel.bucketsWithRetained([open])[3], [open]);
      expect(viewModel.bucketsWithRetained([])[3], isEmpty);
    },
  );
}

TaskItem _task(String id, {required int priority, bool completed = false}) =>
    TaskItem(
      id: id,
      userId: 'user',
      content: id,
      projectId: inboxProjectId,
      priority: priority,
      status: completed ? 'completed' : 'open',
      completedFocusIntervals: 0,
      totalFocusSeconds: 0,
      orderKey: id,
      isDeleted: false,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
