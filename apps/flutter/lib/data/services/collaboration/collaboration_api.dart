import 'package:app_account/app_account.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';

class CollaborationApi {
  CollaborationApi(this.invoke);
  factory CollaborationApi.account(AccountClient account) => CollaborationApi((
    body,
  ) async {
    late AccountFunctionResponse response;
    try {
      response = await account.invokeFunction(
        'pomodoist-collaboration',
        body: body,
      );
    } on FunctionException catch (error) {
      final data = error.details;
      throw CollaborationException(
        error.status == 404
            ? 'function_not_found'
            : data is Map
            ? data['code']?.toString() ?? 'request_failed'
            : 'request_failed',
        data is Map ? data['error']?.toString() : null,
      );
    }
    if (response.status == 404) {
      throw const CollaborationException('function_not_found');
    }
    final data = response.data;
    if (data is! Map) throw const CollaborationException('invalid_response');
    if (response.status >= 400 && data['error'] == null) {
      throw const CollaborationException('request_failed');
    }
    return Map<String, dynamic>.from(data);
  });
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> body) invoke;

  Future<Map<String, dynamic>> state() => call('state');

  Future<Map<String, dynamic>> publicRead(String token) =>
      call('publicRead', {'token': token});

  Future<Map<String, dynamic>> acceptInvitation(String token) =>
      call('accept', {'token': token});

  Future<Map<String, dynamic>> share({
    required String projectId,
    required int expectedRevision,
  }) => call('share', {
    'rootProjectId': projectId,
    'expectedRevision': expectedRevision,
  });

  Future<Map<String, dynamic>> unshare(String scopeId) =>
      call('unshare', {'scopeId': scopeId});

  Future<Map<String, dynamic>> members(String scopeId) =>
      call('members', {'scopeId': scopeId});

  Future<Map<String, dynamic>> invite({
    required String scopeId,
    required String email,
    required CollaborationRole role,
  }) => call('invite', {'scopeId': scopeId, 'email': email, 'role': role.name});

  Future<Map<String, dynamic>> revokeInvitation({
    required String scopeId,
    required String invitationId,
  }) => call('invite', {
    'scopeId': scopeId,
    'invitationId': invitationId,
    'revoke': 'true',
  });

  Future<Map<String, dynamic>> setMemberRole({
    required String scopeId,
    required String userId,
    required CollaborationRole role,
  }) => call('role', {'scopeId': scopeId, 'userId': userId, 'role': role.name});

  Future<Map<String, dynamic>> removeMember({
    required String scopeId,
    required String userId,
  }) => call('remove', {'scopeId': scopeId, 'userId': userId});

  Future<Map<String, dynamic>> transferOwnership({
    required String scopeId,
    required String userId,
  }) => call('transfer', {'scopeId': scopeId, 'userId': userId});

  Future<Map<String, dynamic>> leaveScope(String scopeId) =>
      call('leave', {'scopeId': scopeId});

  Future<Map<String, dynamic>> deleteScope(String scopeId) =>
      call('delete', {'scopeId': scopeId});

  Future<Map<String, dynamic>> markNotificationRead(String notificationId) =>
      call('readNotification', {'notificationId': notificationId});

  /// Low-level wire call used by the shared synchronization engine for actions
  /// that do not surface in the UI, such as `pull`, `push` and `preferences`.
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> arguments = const {},
  ]) async {
    final result = await invoke({
      'action': action,
      ...arguments,
    }).timeout(const Duration(seconds: 30));
    if (result['error'] != null) {
      throw CollaborationException(
        result['code'] as String? ?? 'request_failed',
        result['error'].toString(),
      );
    }
    return result;
  }
}
