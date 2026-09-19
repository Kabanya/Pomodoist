import 'package:pomodoist/domain/models/account/account_management.dart';
import 'package:pomodoist/utils/result.dart';

abstract interface class AccountManagementRepository {
  String? get userId;
  String? get email;
  bool get isCurrent;
  Future<Result<List<ConnectedAgent>>> connectedAgents();
  Future<Result<void>> revokeAgent(String clientId);
  Future<Result<OAuthAuthorization>> authorization(String id);
  Future<Result<String?>> consent(String id, {required bool approve});
  Future<Result<void>> connectTelegram(String token);
  Future<Result<void>> deleteRemoteAccount();
  Future<Result<void>> signOut();
  Future<Result<void>> updateNickname(String name);
}
