import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';

final driftRowFixtureProvider = Provider<TaskRow?>(
  (ref) => throw UnimplementedError(),
);

class DriftRowViewModel extends Notifier<int> {
  @override
  int build() => ref.watch(driftRowFixtureProvider).hashCode;
}
