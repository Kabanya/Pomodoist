import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/dependencies.dart';
import '../../../domain/models/domain_task.dart';

class TaskListState {
  const TaskListState({required this.tasks, required this.loading});

  final List<DomainTask> tasks;
  final bool loading;
}

class TaskListViewModel extends Notifier<TaskListState> {
  @override
  TaskListState build() {
    final tasks = ref.watch(tasksProvider);
    return TaskListState(
      tasks: tasks.value ?? const <DomainTask>[],
      loading: tasks.isLoading,
    );
  }

  Future<void> complete(DomainTask task) =>
      ref.read(taskRepositoryProvider).complete(task.id);

  Future<List<DomainTask>> decompose(DomainTask task) =>
      ref.read(taskDecomposerProvider).decompose(task);
}
