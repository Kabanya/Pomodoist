import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

enum PasswordRecoveryAuthEvent {
  recovery,
  tokenRefreshed,
  signedIn,
  signedOut,
  other,
}

final class PasswordRecoverySession {
  const PasswordRecoverySession({required this.userId, required this.digest});

  final String userId;
  final String digest;
}

final class PasswordRecoveryAuthState {
  const PasswordRecoveryAuthState({required this.event, this.session});

  final PasswordRecoveryAuthEvent event;
  final PasswordRecoverySession? session;
}

/// Isolates Supabase session and HTTP details from the recovery state machine.
final class PasswordRecoveryService {
  PasswordRecoveryService({
    required GoTrueClient auth,
    required Uri userEndpoint,
    http.Client? httpClient,
  }) : _auth = auth,
       _userEndpoint = userEndpoint,
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  final GoTrueClient _auth;
  final Uri _userEndpoint;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  PasswordRecoverySession? get currentSession => _session(_auth.currentSession);

  Stream<PasswordRecoveryAuthState> get authStateChanges =>
      _auth.onAuthStateChange.map(
        (state) => PasswordRecoveryAuthState(
          event: switch (state.event) {
            AuthChangeEvent.passwordRecovery =>
              PasswordRecoveryAuthEvent.recovery,
            AuthChangeEvent.tokenRefreshed =>
              PasswordRecoveryAuthEvent.tokenRefreshed,
            AuthChangeEvent.signedIn => PasswordRecoveryAuthEvent.signedIn,
            AuthChangeEvent.signedOut => PasswordRecoveryAuthEvent.signedOut,
            _ => PasswordRecoveryAuthEvent.other,
          },
          session: _session(state.session),
        ),
      );

  Future<void> requestEmail(
    String email, {
    required String redirectTo,
    String? captchaToken,
  }) async {
    try {
      await _auth.resetPasswordForEmail(
        email,
        redirectTo: redirectTo,
        captchaToken: captchaToken,
      );
    } on AuthException catch (error) {
      // Keep the response neutral even on backends that reveal unknown emails.
      if (error.code != 'user_not_found') rethrow;
    }
  }

  Future<void> updatePassword(String password) async {
    final session = _auth.currentSession;
    if (session == null) throw AuthSessionMissingException();
    // GoTrue 2.26 updateUser applies its late response to whichever session is
    // current at completion. A direct request cannot mutate a newer account.
    final http.Response response;
    try {
      response = await _httpClient.put(
        _userEndpoint,
        headers: {
          for (final entry in _auth.headers.entries)
            if (entry.key.toLowerCase() != 'authorization')
              entry.key: entry.value,
          'Authorization': 'Bearer ${session.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(UserAttributes(password: password).toJson()),
      );
    } on http.ClientException {
      throw AuthRetryableFetchException(
        message: 'Password update connection failed.',
      );
    }
    final Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      throw AuthApiException(
        'Invalid password update response.',
        statusCode: '${response.statusCode}',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final code = body is Map ? (body['code'] ?? body['error_code']) : null;
      throw AuthApiException(
        'Password update failed.',
        statusCode: '${response.statusCode}',
        code: code is String ? code : null,
      );
    }
    if (body is! Map<String, dynamic> ||
        UserResponse.fromJson(body).user?.id != session.user.id) {
      throw const AuthException('Invalid password update response.');
    }
  }

  void dispose() {
    if (_ownsHttpClient) _httpClient.close();
  }

  static PasswordRecoverySession? _session(Session? session) => session == null
      ? null
      : PasswordRecoverySession(
          userId: session.user.id,
          digest: sha256.convert(utf8.encode(session.accessToken)).toString(),
        );
}
