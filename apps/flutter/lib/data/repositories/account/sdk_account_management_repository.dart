import 'package:pomodoist/data/services/account/account_management_service.dart';
import 'package:pomodoist/domain/models/account/account_management.dart';
import 'package:pomodoist/utils/result.dart';
import 'account_management_repository.dart';

class SdkAccountManagementRepository implements AccountManagementRepository {
  SdkAccountManagementRepository({
    required AccountManagementService service,
    required String? userId,
    required Duration timeout,
    required Future<void> Function(String userId, String name) saveNickname,
  }) : _service = service,
       _userId = userId,
       _timeout = timeout,
       _saveNickname = saveNickname;
  final AccountManagementService _service;
  final String? _userId;
  final Duration _timeout;
  final Future<void> Function(String userId, String name) _saveNickname;
  @override
  String? get userId => _userId;
  @override
  String? get email => _service.email;
  @override
  bool get isCurrent => _userId != null && _service.currentUserId == _userId;
  void _requireCurrent() {
    if (!isCurrent) throw StateError('The account session has changed.');
  }

  @override
  Future<Result<List<ConnectedAgent>>> connectedAgents() =>
      Result.capture(() async {
        _requireCurrent();
        final grants = await _service.connectedAgents().timeout(_timeout);
        _requireCurrent();
        return grants;
      });
  @override
  Future<Result<void>> revokeAgent(String clientId) => Result.capture(() async {
    _requireCurrent();
    await _service.revokeAgent(clientId).timeout(_timeout);
    _requireCurrent();
  });
  @override
  Future<Result<OAuthAuthorization>> authorization(String id) =>
      Result.capture(() async {
        _requireCurrent();
        final value = await _service.authorization(id);
        _requireCurrent();
        return value;
      });
  @override
  Future<Result<String?>> consent(String id, {required bool approve}) =>
      Result.capture(() async {
        _requireCurrent();
        final value = await _service.consent(id, approve: approve);
        _requireCurrent();
        return value;
      });
  @override
  Future<Result<void>> connectTelegram(String token) =>
      Result.capture(() async {
        _requireCurrent();
        await _service.connectTelegram(token);
        _requireCurrent();
      });
  @override
  Future<Result<void>> deleteRemoteAccount() => Result.capture(() async {
    _requireCurrent();
    await _service.deleteRemoteAccount().timeout(_timeout);
  });
  @override
  Future<Result<void>> signOut() => Result.capture(_service.signOut);
  @override
  Future<Result<void>> updateNickname(String name) => Result.capture(() async {
    _requireCurrent();
    final value = name.trim();
    if (value.isEmpty) throw ArgumentError.value(name, 'nickname');
    await _saveNickname(_userId!, value).timeout(_timeout);
  });
}
