import 'package:app_account/app_account.dart';
import 'package:pomodoist/domain/models/account/account_management.dart';

class AccountManagementService {
  const AccountManagementService(this._account);

  final AccountClient _account;

  String? get currentUserId => _account.currentUserId;
  String? get email => _account.currentEmail ?? _account.currentSession?.email;

  Future<List<ConnectedAgent>> connectedAgents() async => List.unmodifiable(
    (await _account.listOAuthGrants()).map(
      (grant) => ConnectedAgent(
        clientId: grant.clientId,
        clientName: grant.clientName,
        connectedAt: grant.connectedAt,
      ),
    ),
  );

  Future<void> revokeAgent(String clientId) =>
      _account.revokeOAuthGrant(clientId);

  Future<OAuthAuthorization> authorization(String id) async =>
      switch (await _account.getOAuthAuthorization(id)) {
        AccountOAuthAuthorizationDetails value => OAuthAuthorizationDetails(
          authorizationId: value.authorizationId,
          clientName: value.clientName,
          redirectUri: value.redirectUri,
          scopes: value.scopes,
        ),
        AccountOAuthAuthorizationRedirect value => OAuthAuthorizationRedirect(
          value.redirectUrl,
        ),
      };

  Future<String?> consent(String id, {required bool approve}) async =>
      (approve
              ? await _account.approveOAuthAuthorization(id)
              : await _account.denyOAuthAuthorization(id))
          .redirectUrl;

  Future<void> connectTelegram(String token) async {
    final response = await _account.invokeFunction(
      'pomodoist-telegram',
      body: {'action': 'complete_link', 'token': token},
    );
    final data = response.data;
    if (response.status < 200 ||
        response.status >= 300 ||
        data is! Map ||
        data['ok'] != true) {
      throw StateError(
        data is Map ? '${data['code'] ?? 'link_failed'}' : 'link_failed',
      );
    }
  }

  Future<void> deleteRemoteAccount() async {
    final response = await _account.invokeFunction(
      'account-delete',
      body: const {'confirm': true},
    );
    final data = response.data;
    if (data is! Map || data['deleted'] != true) {
      throw StateError('Account deletion was not confirmed by the server.');
    }
  }

  Future<void> signOut() => _account.signOut();
}
