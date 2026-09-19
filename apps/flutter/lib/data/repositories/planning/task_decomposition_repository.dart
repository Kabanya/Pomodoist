import 'package:pomodoist/domain/models/planning/task_decomposition.dart';

abstract class TaskDecomposer {
  Future<List<DecomposedTaskDraft>> decompose(
    String transcript, {
    required DateTime now,
    required String locale,
    bool smartMode = false,
  });
}
