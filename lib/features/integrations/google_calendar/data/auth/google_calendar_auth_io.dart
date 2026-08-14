import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';

import '../google_calendar_config.dart';
import 'google_calendar_auth_contract.dart';

GoogleCalendarAuthService createGoogleCalendarAuthService({
  required GoogleCalendarConfig config,
}) {
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    return _LoopbackCalendarAuthService(config);
  }
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
        .initialize(
          clientId: _config.nativeGoogleSignInClientId,
          serverClientId: _config.googleSignInServerClientId,
        )
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
    final account = await GoogleSignIn.instance.authenticate(
      scopeHint: GoogleCalendarConfig.scopes,
    );
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

class _LoopbackCalendarAuthService implements GoogleCalendarAuthService {
  _LoopbackCalendarAuthService(
    this._config, {
    Dio? dio,
    FlutterSecureStorage? storage,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: googleCalendarRequestTimeout,
               sendTimeout: googleCalendarRequestTimeout,
               receiveTimeout: googleCalendarRequestTimeout,
             ),
           ),
       _storage =
           storage ??
           const FlutterSecureStorage(
             mOptions: MacOsOptions(usesDataProtectionKeychain: false),
           );

  static const _tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const _authEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const _refreshTokenKey = 'google_calendar_refresh_token';
  static const _accessTokenKey = 'google_calendar_access_token';
  static const _accessTokenExpiresAtKey =
      'google_calendar_access_token_expires_at';

  final GoogleCalendarConfig _config;
  final Dio _dio;
  final FlutterSecureStorage _storage;
  String? _accessToken;
  int? _accessTokenExpiresAt;
  String? _refreshToken;
  bool _keychainUnavailable = false;

  @override
  Future<void> initialize() async {}

  @override
  Future<GoogleCalendarAuthAccount> signIn() async {
    final clientId = await _requiredDesktopClientId();
    final verifier = _randomUrlSafeString(64);
    final challenge = _codeChallenge(verifier);
    final state = _randomUrlSafeString(24);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://127.0.0.1:${server.port}';
    try {
      final uri = Uri.parse(_authEndpoint).replace(
        queryParameters: {
          'client_id': clientId,
          'redirect_uri': redirectUri,
          'response_type': 'code',
          'scope': GoogleCalendarConfig.scopes.join(' '),
          'access_type': 'offline',
          'prompt': 'consent',
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
          'state': state,
        },
      );
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw StateError('Could not open the system browser for Google OAuth.');
      }
      final request = await server.first.timeout(
        googleCalendarInteractiveAuthTimeout,
      );
      final params = request.uri.queryParameters;
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(
          '<!doctype html><html><body><p>Google Calendar is connected. '
          'You can close this tab and return to Pomodoist.</p></body></html>',
        );
      await request.response.close();
      if (params['state'] != state) {
        throw StateError('OAuth state mismatch.');
      }
      final error = params['error'];
      if (error != null) {
        throw StateError('Google OAuth failed: $error');
      }
      final code = params['code'];
      if (code == null || code.isEmpty) {
        throw StateError('Google OAuth did not return an authorization code.');
      }
      await _exchangeCode(
        clientId: clientId,
        code: code,
        redirectUri: redirectUri,
        verifier: verifier,
      );
      return const GoogleCalendarAuthAccount();
    } finally {
      await server.close(force: true);
    }
  }

  @override
  Future<String?> accessToken({bool interactive = false}) async {
    final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    if (_accessToken != null &&
        _accessTokenExpiresAt != null &&
        _accessTokenExpiresAt! - nowSeconds > 60) {
      return _accessToken;
    }
    final token = await _readToken(_accessTokenKey);
    final expiresAtRaw = await _readToken(_accessTokenExpiresAtKey);
    final expiresAt = int.tryParse(expiresAtRaw ?? '');
    if (token != null && expiresAt != null && expiresAt - nowSeconds > 60) {
      _accessToken = token;
      _accessTokenExpiresAt = expiresAt;
      return token;
    }
    final refreshToken = _refreshToken ?? await _readToken(_refreshTokenKey);
    if (refreshToken == null) {
      if (!interactive) {
        return null;
      }
      await signIn();
      return accessToken();
    }
    return _refresh(refreshToken);
  }

  @override
  Future<void> disconnect() async {
    _refreshToken = null;
    _accessToken = null;
    _accessTokenExpiresAt = null;
    await _deleteToken(_refreshTokenKey);
    await _deleteToken(_accessTokenKey);
    await _deleteToken(_accessTokenExpiresAtKey);
  }

  Future<void> _exchangeCode({
    required String clientId,
    required String code,
    required String redirectUri,
    required String verifier,
  }) async {
    final data = {
      'client_id': clientId,
      'code': code,
      'code_verifier': verifier,
      'redirect_uri': redirectUri,
      'grant_type': 'authorization_code',
    };
    final clientSecret = await _desktopClientSecret();
    if (clientSecret != null) {
      data['client_secret'] = clientSecret;
    }
    final response = await _postToken(data);
    await _storeTokenResponse(response);
  }

  Future<String> _refresh(String refreshToken) async {
    final clientId = await _requiredDesktopClientId();
    final data = {
      'client_id': clientId,
      'refresh_token': refreshToken,
      'grant_type': 'refresh_token',
    };
    final clientSecret = await _desktopClientSecret();
    if (clientSecret != null) {
      data['client_secret'] = clientSecret;
    }
    final response = await _postToken(data);
    await _storeTokenResponse(response);
    final token = _accessToken ?? await _readToken(_accessTokenKey);
    if (token == null) {
      throw StateError('Google OAuth refresh did not return an access token.');
    }
    return token;
  }

  Future<Map<String, Object?>> _postToken(Map<String, String> data) async {
    try {
      final response = await _dio.post<Map<String, Object?>>(
        _tokenEndpoint,
        options: Options(contentType: Headers.formUrlEncodedContentType),
        data: data,
      );
      return response.data ?? const {};
    } on DioException catch (error) {
      throw GoogleCalendarOAuthException(
        googleCalendarOAuthTokenErrorMessage(
          error.response?.data,
          error.response?.statusCode,
        ),
      );
    }
  }

  Future<String> _requiredDesktopClientId() async {
    final candidates = [
      _config.desktopClientId,
      Platform.environment['GOOGLE_DESKTOP_CLIENT_ID'],
      _config.clientId,
      Platform.environment['GOOGLE_CLIENT_ID'],
      await _macOSInfoPlistValue('GoogleDesktopClientID'),
    ];
    for (final value in candidates) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    throw const GoogleCalendarConfigException(
      'GOOGLE_DESKTOP_CLIENT_ID or GOOGLE_CLIENT_ID is required for '
      'Google Calendar on macOS/Windows/Linux.',
    );
  }

  Future<String?> _desktopClientSecret() async {
    return resolveGoogleCalendarDesktopClientSecret(
      dartDefineValue: _config.desktopGoogleSignInClientSecret,
      environmentValue: Platform.environment['GOOGLE_DESKTOP_CLIENT_SECRET'],
      macOSInfoPlistValue: await _macOSInfoPlistValue(
        'GoogleDesktopClientSecret',
      ),
    );
  }

  Future<String?> _macOSInfoPlistValue(String key) async {
    if (!Platform.isMacOS) {
      return null;
    }
    final executable = File(Platform.resolvedExecutable);
    final infoPlist = File.fromUri(
      executable.parent.parent.uri.resolve('Info.plist'),
    );
    if (!await infoPlist.exists()) {
      return null;
    }
    final contents = await infoPlist.readAsString();
    final pattern = RegExp(
      '<key>${RegExp.escape(key)}</key>\\s*<string>([^<]*)</string>',
    );
    final match = pattern.firstMatch(contents);
    return match?.group(1)?.trim();
  }

  Future<void> _storeTokenResponse(Map<String, Object?> data) async {
    final accessToken = data['access_token'];
    if (accessToken is! String || accessToken.isEmpty) {
      throw StateError('Google OAuth did not return an access token.');
    }
    final expiresIn = data['expires_in'] is int
        ? data['expires_in'] as int
        : int.tryParse('${data['expires_in']}') ?? 3600;
    final refreshToken = data['refresh_token'];
    final expiresAt =
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + expiresIn;
    _accessToken = accessToken;
    _accessTokenExpiresAt = expiresAt;
    await _writeToken(_accessTokenKey, accessToken);
    await _writeToken(_accessTokenExpiresAtKey, expiresAt.toString());
    if (refreshToken is String && refreshToken.isNotEmpty) {
      _refreshToken = refreshToken;
      await _writeToken(_refreshTokenKey, refreshToken);
    }
  }

  Future<String?> _readToken(String key) async {
    if (_keychainUnavailable) {
      return null;
    }
    try {
      return await _storage.read(key: key);
    } catch (error) {
      if (googleCalendarIsMissingKeychainEntitlement(error)) {
        _keychainUnavailable = true;
        return null;
      }
      rethrow;
    }
  }

  Future<void> _writeToken(String key, String value) async {
    if (_keychainUnavailable) {
      return;
    }
    try {
      await _storage.write(key: key, value: value);
    } catch (error) {
      if (googleCalendarIsMissingKeychainEntitlement(error)) {
        _keychainUnavailable = true;
        return;
      }
      rethrow;
    }
  }

  Future<void> _deleteToken(String key) async {
    if (_keychainUnavailable) {
      return;
    }
    try {
      await _storage.delete(key: key);
    } catch (error) {
      if (googleCalendarIsMissingKeychainEntitlement(error)) {
        _keychainUnavailable = true;
        return;
      }
      rethrow;
    }
  }

  String _codeChallenge(String verifier) {
    final digest = sha256.convert(ascii.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  String _randomUrlSafeString(int length) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

String? resolveGoogleCalendarDesktopClientSecret({
  required String? dartDefineValue,
  required String? environmentValue,
  required String? macOSInfoPlistValue,
}) {
  for (final value in [
    dartDefineValue,
    environmentValue,
    macOSInfoPlistValue,
  ]) {
    final trimmed = value?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}

bool googleCalendarIsMissingKeychainEntitlement(Object error) {
  return error is PlatformException &&
      error.code == 'Unexpected security result code' &&
      (error.details == -34018 ||
          (error.message?.contains('-34018') ?? false) ||
          (error.message?.contains("required entitlement") ?? false));
}

class GoogleCalendarOAuthException implements Exception {
  const GoogleCalendarOAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

String googleCalendarOAuthTokenErrorMessage(Object? data, int? statusCode) {
  if (data is Map) {
    final error = data['error'];
    final description = data['error_description'];
    if (error is String && description is String && description.isNotEmpty) {
      if (description == 'client_secret is missing.') {
        return 'Google OAuth failed: client secret is missing. Set '
            'GOOGLE_DESKTOP_CLIENT_SECRET for this OAuth client.';
      }
      return 'Google OAuth failed: $error: $description';
    }
    if (error is String && error.isNotEmpty) {
      return 'Google OAuth failed: $error';
    }
  }
  if (data is String && data.trim().isNotEmpty) {
    return 'Google OAuth failed: ${data.trim()}';
  }
  if (statusCode != null) {
    return 'Google OAuth token request failed with HTTP $statusCode.';
  }
  return 'Google OAuth token request failed.';
}
