import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';

final concreteRepositoryProvider = Provider<DriftTaskRepository>(
  (ref) => throw UnimplementedError(),
);

class ConcreteRepositoryViewModel extends Notifier<int> {
  @override
  int build() => ref.watch(concreteRepositoryProvider).hashCode;
}
