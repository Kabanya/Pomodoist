import 'package:pomodoist/utils/result.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

abstract interface class KanbanRepository {
  Stream<KanbanBoardSnapshot> watchBoard();
  Future<Result<String>> createStatus(String name, {String? color});
  Future<Result<void>> renameStatus(String id, String name);
  Future<Result<void>> reorderStatus(String id, int targetIndex);
  Future<Result<void>> deleteStatus(String id);
  Future<Result<void>> setSelectedProjectIds(Set<String> projectIds);
  Future<Result<void>> setFocusStatus(String statusId);
  Future<Result<void>> moveTask(
    String taskId, {
    required String statusId,
    int? targetIndex,
  });
}
