import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/tasks/barrel.dart';

final reexportFixtureProvider = Provider<DriftTaskRepository>(
  (ref) => throw UnimplementedError(),
);

class ReexportViewModel extends Notifier<int> {
  @override
  int build() => ref.watch(reexportFixtureProvider).hashCode;
}
