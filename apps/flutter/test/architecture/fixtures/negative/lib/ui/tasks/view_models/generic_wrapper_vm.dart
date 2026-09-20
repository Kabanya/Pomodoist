import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';

final genericWrapperFixtureProvider = Provider<List<DriftTaskRepository>>(
  (ref) => throw UnimplementedError(),
);

class GenericWrapperViewModel extends Notifier<int> {
  @override
  int build() => ref.watch(genericWrapperFixtureProvider).length;
}
