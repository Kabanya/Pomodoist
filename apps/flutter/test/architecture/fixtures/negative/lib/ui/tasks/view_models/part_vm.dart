import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';

part 'part_vm_actions.dart';

final partFixtureProvider = Provider<DriftTaskRepository>(
  (ref) => throw UnimplementedError(),
);

class PartViewModel extends Notifier<int> {
  @override
  int build() => 0;
}
