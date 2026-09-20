import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/planning/task_decomposition_repository.dart';
import '../data/repositories/tasks/task_repository.dart';
import '../data/repositories/tasks/task_repository_impl.dart';
import '../data/services/local/task_store.dart';
import '../domain/models/domain_task.dart';

final localTaskStoreProvider = Provider<LocalTaskStore>(
  (ref) => LocalTaskStore(),
);

final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => DriftTaskRepository(ref.watch(localTaskStoreProvider)),
);

/// A domain-returning provider; composition may construct implementations.
final tasksProvider = StreamProvider<List<DomainTask>>(
  (ref) => const Stream<List<DomainTask>>.empty(),
);

final taskDecomposerProvider = Provider<TaskDecomposer>(
  (ref) => throw UnimplementedError(),
);
