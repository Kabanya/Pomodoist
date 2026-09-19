import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_conflict.dart';
import 'package:pomodoist/utils/result.dart';

abstract interface class CollaborationRepository {
  Stream<List<SharedScope>> watchScopes();
  Stream<List<Map<String, dynamic>>> watchEntities(
    String scopeId,
    String type, {
    String? taskId,
  });
  Stream<List<CollaborationConflict>> watchConflicts();
  Future<Result<String>> actorId();
  Future<Result<Map<String, dynamic>>> publicRead(String token);
  Future<Result<Map<String, dynamic>>> action(
    String action, [
    Map<String, dynamic> args = const {},
  ]);
  Future<Result<Map<String, dynamic>>> state();
  Future<Result<Map<String, dynamic>>> acceptInvitation(String token);
  Future<Result<Map<String, dynamic>>> unshare(String scopeId);
  Future<Result<Map<String, dynamic>>> share(String projectId);
  Future<Result<void>> setAssignees(String taskId, Set<String> ids);
  Future<Result<void>> comment(
    String scopeId,
    String taskId,
    String text, {
    String? commentId,
    List<String> mentions = const [],
  });
  Future<Result<void>> deleteComment(String scopeId, String id);
  Future<Result<void>> resolveConflict(
    CollaborationConflict command, {
    required bool keepLocal,
  });
}
