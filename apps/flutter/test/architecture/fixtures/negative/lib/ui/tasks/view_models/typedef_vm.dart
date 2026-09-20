import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';

typedef RepositoryAlias = DriftTaskRepository;

final typedefFixtureProvider = Provider<RepositoryAlias>(
  (ref) => throw UnimplementedError(),
);

class TypedefViewModel extends Notifier<int> {
  @override
  int build() => ref.watch(typedefFixtureProvider).hashCode;
}
