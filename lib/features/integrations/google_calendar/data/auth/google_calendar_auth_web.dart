import 'package:google_sign_in/google_sign_in.dart';

import '../google_calendar_config.dart';
import 'google_calendar_auth_contract.dart';

GoogleCalendarAuthService createGoogleCalendarAuthService({
  required GoogleCalendarConfig config,
}) {
  return _GoogleSignInCalendarAuthService(config);
}

class _GoogleSignInCalendarAuthService implements GoogleCalendarAuthService {
  _GoogleSignInCalendarAuthService(this._config);

  final GoogleCalendarConfig _config;
  GoogleSignInAccount? _currentUser;
  Future<void>? _initializing;

  @override
  Future<void> initialize() => _ensureInitialized();

  Future<void> _ensureInitialized() {
    return _initializing ??= GoogleSignIn.instance
        .initialize(clientId: _config.requiredWebClientId)
        .then((_) {
          GoogleSignIn.instance.authenticationEvents.listen((event) {
            _currentUser = switch (event) {
              GoogleSignInAuthenticationEventSignIn() => event.user,
              GoogleSignInAuthenticationEventSignOut() => null,
            };
          });
        });
  }

  @override
  Future<GoogleCalendarAuthAccount> signIn() async {
    await _ensureInitialized();
    final account = GoogleSignIn.instance.supportsAuthenticate()
        ? await GoogleSignIn.instance.authenticate(
            scopeHint: GoogleCalendarConfig.scopes,
          )
        : await GoogleSignIn.instance.attemptLightweightAuthentication();
    if (account == null) {
      throw UnsupportedError(
        'Google Sign-In on web requires the official Google web sign-in '
        'button before authorization can continue.',
      );
    }
    _currentUser = account;
    await account.authorizationClient.authorizeScopes(
      GoogleCalendarConfig.scopes,
    );
    return GoogleCalendarAuthAccount(
      email: account.email,
      displayName: account.displayName,
    );
  }

  @override
  Future<String?> accessToken({bool interactive = false}) async {
    await _ensureInitialized();
    final user =
        _currentUser ??
        await GoogleSignIn.instance.attemptLightweightAuthentication();
    if (user == null) {
      if (!interactive) {
        return null;
      }
      await signIn();
      return accessToken();
    }
    _currentUser = user;
    final headers = await user.authorizationClient.authorizationHeaders(
      GoogleCalendarConfig.scopes,
      promptIfNecessary: interactive,
    );
    final authorization = headers?['Authorization'];
    if (authorization == null || !authorization.startsWith('Bearer ')) {
      return null;
    }
    return authorization.substring('Bearer '.length);
  }

  @override
  Future<void> disconnect() async {
    await _ensureInitialized();
    _currentUser = null;
    await GoogleSignIn.instance.disconnect();
  }
}
