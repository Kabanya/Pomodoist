import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';

import '../../../data/services/tasks/repository_tools.dart';

final extensionFixtureProvider = Provider<DriftTaskRepository>(
  (ref) => throw UnimplementedError(),
);

class ExtensionViewModel extends Notifier<int> {
  @override
  int build() => ref.watch(extensionFixtureProvider).toolLength;
}
