import 'dart:async';

import 'package:pomodoist/data/repositories/account/account_management_repository.dart';
import 'package:pomodoist/domain/models/account/account_management.dart';
import 'package:pomodoist/utils/result.dart';

import 'strict_fake.dart';

/// Configurable [AccountManagementRepository] double.
///
/// Every method has a working default, so a test only has to set the fields it
/// cares about. Calls are appended to the matching recording list, and a
/// `Result`-returning method returns its `<method>Error` failure when that field
/// is non-null.
///
/// To hold a call open, push a [Completer] onto the matching `<method>Requests`
/// list first: the call consumes it and settles with the completer's value, so
/// a test can decide when the call resolves. With no queued completer the call
/// answers from the fields immediately.
class FakeAccountManagementRepository extends StrictFake
    implements AccountManagementRepository {
  FakeAccountManagementRepository({this.userId = 'user-1'});

  /// Identity reported by [userId].
  @override
  String? userId;

  /// Identity reported by [email].
  @override
  String? email = 'person@example.com';

  /// Identity reported by [isCurrent].
  @override
  bool isCurrent = true;

  /// Agents [connectedAgents] succeeds with.
  List<ConnectedAgent> agents = const [];

  /// Authorization [authorization] succeeds with.
  OAuthAuthorization authorizationValue = const OAuthAuthorizationRedirect(
    'https://example.com/authorize',
  );

  /// Code [consent] succeeds with; null means consent was not granted.
  String? consentValue;

  Object? connectedAgentsError;
  Object? revokeAgentError;
  Object? authorizationError;
  Object? consentError;
  Object? connectTelegramError;
  Object? deleteRemoteAccountError;
  Object? signOutError;
  Object? updateNicknameError;

  final connectedAgentsCalls = <void>[];
  final revokeAgentCalls = <String>[];
  final authorizationCalls = <String>[];
  final consentCalls = <({String id, bool approve})>[];
  final connectTelegramCalls = <String>[];
  final deleteRemoteAccountCalls = <void>[];
  final signOutCalls = <void>[];
  final updateNicknameCalls = <String>[];

  /// Completers consumed by the next [connectedAgents] calls, in order.
  final connectedAgentsRequests = <Completer<List<ConnectedAgent>>>[];

  /// Completers consumed by the next [revokeAgent] calls, in order.
  final revokeAgentRequests = <Completer<void>>[];

  @override
  Future<Result<List<ConnectedAgent>>> connectedAgents() async {
    connectedAgentsCalls.add(null);
    final request = connectedAgentsRequests.isEmpty
        ? null
        : connectedAgentsRequests.removeAt(0);
    if (request != null) return Result.ok(await request.future);
    final error = connectedAgentsError;
    if (error != null) return Result.error(error, StackTrace.current);
    return Result.ok(agents);
  }

  @override
  Future<Result<void>> revokeAgent(String clientId) async {
    revokeAgentCalls.add(clientId);
    final request = revokeAgentRequests.isEmpty
        ? null
        : revokeAgentRequests.removeAt(0);
    if (request != null) {
      await request.future;
      return const Result.ok(null);
    }
    final error = revokeAgentError;
    if (error != null) return Result.error(error, StackTrace.current);
    return const Result.ok(null);
  }

  @override
  Future<Result<OAuthAuthorization>> authorization(String id) async {
    authorizationCalls.add(id);
    final error = authorizationError;
    if (error != null) return Result.error(error, StackTrace.current);
    return Result.ok(authorizationValue);
  }

  @override
  Future<Result<String?>> consent(String id, {required bool approve}) async {
    consentCalls.add((id: id, approve: approve));
    final error = consentError;
    if (error != null) return Result.error(error, StackTrace.current);
    return Result.ok(consentValue);
  }

  @override
  Future<Result<void>> connectTelegram(String token) async {
    connectTelegramCalls.add(token);
    final error = connectTelegramError;
    if (error != null) return Result.error(error, StackTrace.current);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> deleteRemoteAccount() async {
    deleteRemoteAccountCalls.add(null);
    final error = deleteRemoteAccountError;
    if (error != null) return Result.error(error, StackTrace.current);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> signOut() async {
    signOutCalls.add(null);
    final error = signOutError;
    if (error != null) return Result.error(error, StackTrace.current);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> updateNickname(String name) async {
    updateNicknameCalls.add(name);
    final error = updateNicknameError;
    if (error != null) return Result.error(error, StackTrace.current);
    return const Result.ok(null);
  }
}
