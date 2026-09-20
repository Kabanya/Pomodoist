import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_conflict.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_responses.dart';
import 'package:pomodoist/domain/models/collaboration/public_project.dart';
import 'package:pomodoist/utils/result.dart';

abstract interface class CollaborationRepository {
  Stream<List<SharedScope>> watchScopes();
  Stream<List<CollaborationComment>> watchComments(
    String scopeId, {
    String? taskId,
  });
  Stream<List<CollaborationFocusContribution>> watchFocusContributions(
    String scopeId, {
    String? taskId,
  });
  Stream<List<CollaborationConflict>> watchConflicts();
  Future<Result<String>> actorId();
  Future<Result<PublicProject>> publicRead(String token);
  Future<Result<CollaborationState>> state();
  Future<Result<SharedScope>> acceptInvitation(String token);
  Future<Result<SharedScope>> share(String projectId);
  Future<Result<void>> unshare(String scopeId);
  Future<Result<CollaborationMembers>> members(String scopeId);
  Future<Result<CollaborationInviteOutcome>> invite(
    String scopeId, {
    required String email,
    required CollaborationRole role,
  });
  Future<Result<void>> revokeInvitation(String scopeId, String invitationId);
  Future<Result<void>> setMemberRole(
    String scopeId,
    String userId,
    CollaborationRole role,
  );
  Future<Result<void>> removeMember(String scopeId, String userId);
  Future<Result<void>> transferOwnership(String scopeId, String userId);
  Future<Result<void>> leaveScope(String scopeId);
  Future<Result<void>> deleteScope(String scopeId);
  Future<Result<void>> markNotificationRead(String notificationId);
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
