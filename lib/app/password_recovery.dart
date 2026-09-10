import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_auth_feedback.dart';
import 'account_providers.dart';
import 'runtime_public_config.dart';

final passwordRecoveryProvider =
    ChangeNotifierProvider<PasswordRecoveryController>((ref) {
      final baseUrl = ref.watch(runtimePublicConfigProvider).supabaseUrl;
      final controller = PasswordRecoveryController(
        userEndpoint: baseUrl?.replace(
          path: '${baseUrl.path.replaceAll(RegExp(r'/+$'), '')}/auth/v1/user',
        ),
      );
      ref.listen(accountClientProvider, (_, account) {
        controller.attach(
          account == null ? null : Supabase.instance.client.auth,
        );
      }, fireImmediately: true);
      return controller;
    });

enum PasswordRecoveryStage { idle, checking, ready, saving, updated, invalid }

/// Only the SDK's verified recovery event grants permission to edit a password.
/// URL parameters select a screen; they never grant recovery permission.
class PasswordRecoveryController extends ChangeNotifier {
  PasswordRecoveryController({Uri? userEndpoint, http.Client? httpClient})
    : _userEndpoint = userEndpoint,
      _httpClient = httpClient ?? http.Client(),
      _ownsHttpClient = httpClient == null;

  final Uri? _userEndpoint;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  GoTrueClient? _auth;
  StreamSubscription<AuthState>? _subscription;
  Timer? _callbackTimeout;
  Timer? _slowUpdateTimer;
  bool _updating = false;
  bool _takingLonger = false;
  String? _activeRecoveryDigest;
  String? _recoveryUserId;
  String? _lastRecoveryDigest;
  var _generation = 0;
  var _disposed = false;
  var _sending = false;
  PasswordRecoveryStage _stage = PasswordRecoveryStage.idle;
  AccountAuthFailure? _failure;

  PasswordRecoveryStage get stage => _stage;
  AccountAuthFailure? get failure => _failure;
  bool get sending => _sending;
  bool get updating => _updating;
  bool get takingLonger => _takingLonger;
  bool get available => _auth != null;
  bool get canSave =>
      !_updating && _stage == PasswordRecoveryStage.ready && _matchesSession;
  bool get needsRoute =>
      _stage == PasswordRecoveryStage.ready ||
      _stage == PasswordRecoveryStage.saving;
  bool get _matchesSession =>
      _recoveryUserId != null &&
      _auth?.currentUser?.id == _recoveryUserId &&
      _auth?.currentSession != null &&
      _activeRecoveryDigest == _sessionDigest(_auth!.currentSession!);

  void attach(GoTrueClient? auth) {
    if (_disposed || identical(auth, _auth)) return;
    unawaited(_subscription?.cancel());
    _generation++;
    _auth = auth;
    _recoveryUserId = null;
    _activeRecoveryDigest = null;
    if (_stage != PasswordRecoveryStage.checking) {
      _stage = PasswordRecoveryStage.idle;
    }
    _subscription = auth?.onAuthStateChange.listen(
      _onAuthState,
      onError: (Object error, StackTrace stack) {
        if (_stage != PasswordRecoveryStage.checking) return;
        _invalidate(
          classifyAccountAuthFailure(
            error,
            operation: AccountAuthOperation.passwordUpdate,
          ),
        );
      },
    );
    _notify();
  }

  void _onAuthState(AuthState state) {
    if (_disposed) return;
    final session = state.session;
    if (state.event == AuthChangeEvent.passwordRecovery &&
        session != null &&
        session.user.id == _auth?.currentUser?.id) {
      // Retain only a digest for duplicate delivery, never a second copy of tokens.
      final digest = _sessionDigest(session);
      if (digest == _lastRecoveryDigest) return;
      _lastRecoveryDigest = digest;
      _generation++;
      _callbackTimeout?.cancel();
      _recoveryUserId = session.user.id;
      _activeRecoveryDigest = digest;
      _stage = PasswordRecoveryStage.ready;
      _failure = null;
      _notify();
    } else if (state.event == AuthChangeEvent.tokenRefreshed &&
        _recoveryUserId != null &&
        session?.user.id == _recoveryUserId &&
        session?.accessToken == _auth?.currentSession?.accessToken) {
      _activeRecoveryDigest = _sessionDigest(session!);
      _notify();
    } else if (state.event == AuthChangeEvent.signedOut ||
        state.event == AuthChangeEvent.signedIn ||
        (_recoveryUserId != null && session?.user.id != _recoveryUserId)) {
      _generation++;
      _recoveryUserId = null;
      _activeRecoveryDigest = null;
      if (_stage != PasswordRecoveryStage.checking) {
        _stage = PasswordRecoveryStage.idle;
      }
      _notify();
    }
  }

  void beginCallback({AccountAuthFailure? failure}) {
    if (_disposed || needsRoute || _stage == PasswordRecoveryStage.updated) {
      return;
    }
    if (failure != null) {
      _invalidate(failure);
      return;
    }
    if (_stage == PasswordRecoveryStage.checking) return;
    _stage = PasswordRecoveryStage.checking;
    _failure = null;
    _callbackTimeout?.cancel();
    _callbackTimeout = Timer(accountRequestTimeout, () {
      _invalidate(
        const AccountAuthFailure(
          AccountAuthFailureKind.linkExpired,
          field: AccountAuthField.form,
          recovery: AccountAuthRecovery.sendNewLink,
        ),
      );
    });
    _notify();
  }

  Future<bool> requestEmail(
    String email, {
    required String redirectTo,
    String? captchaToken,
  }) async {
    if (_disposed || _sending) return false;
    _failure = validateAccountEmail(email);
    final auth = _auth;
    if (_failure != null || auth == null) {
      _failure ??= const AccountAuthFailure(
        AccountAuthFailureKind.serviceUnavailable,
        field: AccountAuthField.form,
        recovery: AccountAuthRecovery.retry,
      );
      _notify();
      return false;
    }
    _sending = true;
    _notify();
    try {
      await auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: redirectTo,
        captchaToken: captchaToken,
      );
      return !_disposed;
    } on AuthException catch (error) {
      // Keep the response neutral even on backends that reveal unknown emails.
      if (error.code == 'user_not_found') return !_disposed;
      _failure = classifyAccountAuthFailure(
        error,
        operation: AccountAuthOperation.passwordReset,
      );
      return false;
    } on Object catch (error) {
      _failure = classifyAccountAuthFailure(
        error,
        operation: AccountAuthOperation.passwordReset,
      );
      return false;
    } finally {
      _sending = false;
      _notify();
    }
  }

  Future<bool> savePassword(String password, String confirmation) async {
    if (_disposed || _updating || _stage == PasswordRecoveryStage.updated) {
      return false;
    }
    if (!canSave) {
      _invalidate(
        const AccountAuthFailure(
          AccountAuthFailureKind.linkExpired,
          field: AccountAuthField.form,
          recovery: AccountAuthRecovery.sendNewLink,
        ),
      );
      return false;
    }
    _failure = validateAccountPassword(password);
    if (_failure == null && password != confirmation) {
      _failure = const AccountAuthFailure(
        AccountAuthFailureKind.passwordMismatch,
        field: AccountAuthField.password,
        recovery: AccountAuthRecovery.editPassword,
      );
    }
    if (_failure != null) {
      _notify();
      return false;
    }
    final generation = _generation;
    final auth = _auth!;
    _stage = PasswordRecoveryStage.saving;
    _updating = true;
    _takingLonger = false;
    _slowUpdateTimer = Timer(const Duration(seconds: 30), () {
      _takingLonger = true;
      _notify();
    });
    _failure = null;
    _notify();
    try {
      await _updatePassword(auth, password);
      if (_disposed || generation != _generation || !_matchesSession) {
        return false;
      }
      _recoveryUserId = null;
      _activeRecoveryDigest = null;
      _stage = PasswordRecoveryStage.updated;
      _notify();
      return true;
    } on Object catch (error) {
      if (_disposed || generation != _generation) return false;
      final failure = classifyAccountAuthFailure(
        error,
        operation: AccountAuthOperation.passwordUpdate,
      );
      if (!_matchesSession ||
          failure.kind == AccountAuthFailureKind.linkExpired) {
        _invalidate(failure);
      } else {
        _stage = PasswordRecoveryStage.ready;
        _failure = failure;
        _notify();
      }
      return false;
    } finally {
      _slowUpdateTimer?.cancel();
      _updating = false;
      _takingLonger = false;
      _notify();
    }
  }

  Future<void> _updatePassword(GoTrueClient auth, String password) async {
    final endpoint = _userEndpoint;
    final session = auth.currentSession;
    if (endpoint == null || session == null) {
      throw AuthSessionMissingException();
    }
    // GoTrue 2.26 updateUser applies its late response to whichever session is
    // current at completion. This request must never mutate a newer account.
    final http.Response response;
    try {
      response = await _httpClient.put(
        endpoint,
        headers: {
          for (final entry in auth.headers.entries)
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

  void clearFailure() {
    if (_failure == null) return;
    _failure = null;
    _notify();
  }

  void dismiss() {
    _generation++;
    _callbackTimeout?.cancel();
    _recoveryUserId = null;
    _activeRecoveryDigest = null;
    _stage = PasswordRecoveryStage.idle;
    _failure = null;
    _notify();
  }

  void _invalidate(AccountAuthFailure failure) {
    _generation++;
    _callbackTimeout?.cancel();
    _recoveryUserId = null;
    _activeRecoveryDigest = null;
    _stage = PasswordRecoveryStage.invalid;
    _failure = failure;
    _notify();
  }

  String _sessionDigest(Session session) =>
      sha256.convert(utf8.encode(session.accessToken)).toString();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _callbackTimeout?.cancel();
    _slowUpdateTimer?.cancel();
    if (_ownsHttpClient) _httpClient.close();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

String passwordRecoveryRedirect(String loginRedirect) => Uri.parse(
  loginRedirect,
).replace(queryParameters: {'returnTo': '/reset-password'}).toString();
