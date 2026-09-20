import '../../data/repositories/planning/task_decomposition_repository.dart';
import '../../data/repositories/tasks/task_repository.dart';
import '../models/domain_task.dart';

/// A use case may depend on a repository contract and receive a pure local
/// transaction runner through its constructor.
class CompleteTaskUseCase {
  const CompleteTaskUseCase({
    required TaskRepository tasks,
    required Future<T> Function<T>(Future<T> Function() action)
    runLocalTransaction,
  }) : _tasks = tasks,
       _runLocalTransaction = runLocalTransaction;

  final TaskRepository _tasks;
  final Future<T> Function<T>(Future<T> Function() action) _runLocalTransaction;

  Future<void> call(DomainTask task) =>
      _runLocalTransaction(() => _tasks.complete(task.id));
}

Future<List<DomainTask>> decompose(
  TaskDecomposer repository,
  DomainTask task,
) => repository.decompose(task);
