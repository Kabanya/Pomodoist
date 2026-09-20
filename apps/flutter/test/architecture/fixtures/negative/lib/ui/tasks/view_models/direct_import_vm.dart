import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';

class DirectImportViewModel extends Notifier<int> {
  DriftTaskRepository? repository;

  @override
  int build() => repository.hashCode;
}
