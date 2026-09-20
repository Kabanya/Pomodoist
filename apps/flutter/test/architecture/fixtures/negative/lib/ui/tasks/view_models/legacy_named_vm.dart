import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/tasks/legacy_tasks_repository.dart';

final legacyNamedFixtureProvider = Provider<LegacyTasksRepository>(
  (ref) => throw UnimplementedError(),
);

class LegacyNamedViewModel extends Notifier<int> {
  @override
  int build() => ref.watch(legacyNamedFixtureProvider).length;
}
