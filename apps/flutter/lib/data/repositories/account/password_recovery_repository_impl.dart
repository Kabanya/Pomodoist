import 'dart:async';

import 'package:pomodoist/domain/models/account/account_auth_failure.dart';
import 'package:pomodoist/domain/models/account/password_recovery.dart';
import 'package:pomodoist/data/repositories/account/password_recovery_repository.dart';
import 'package:pomodoist/data/services/auth/account_auth_errors.dart';
import 'package:pomodoist/data/services/auth/password_recovery_service.dart';

class SdkPasswordRecoveryRepository implements PasswordRecoveryRepository {
  SdkPasswordRecoveryRepository({
    String Function()? locale,
    Duration requestTimeout = const Duration(seconds: 15),
  }) : _locale = locale,
       _requestTimeout = requestTimeout;

  final String Function()? _locale;
  final Duration _requestTimeout;
  PasswordRecoveryService? _service;
  StreamSubscription<PasswordRecoveryAuthState>? _subscription;
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

  @override
  PasswordRecoveryStage get stage => _stage;

  @override
  AccountAuthFailure? get failure => _failure;

  @override
  bool get sending => _sending;

  @override
  bool get updating => _updating;

  @override
  bool get takingLonger => _takingLonger;

  @override
  bool get available => _service != null;

  @override
  bool get canSave =>
      !_updating && _stage == PasswordRecoveryStage.ready && _matchesSession;

  @override
  bool get needsRoute =>
      _stage == PasswordRecoveryStage.ready ||
      _stage == PasswordRecoveryStage.saving;

  bool get _matchesSession =>
      _recoveryUserId != null &&
      _service?.currentSession?.userId == _recoveryUserId &&
      _activeRecoveryDigest == _service?.currentSession?.digest;

  void attach(PasswordRecoveryService? service) {
    if (_disposed || identical(service, _service)) return;
    unawaited(_subscription?.cancel());
    _generation++;
    _service = service;
    _recoveryUserId = null;
    _activeRecoveryDigest = null;
    if (_stage != PasswordRecoveryStage.checking) {
      _stage = PasswordRecoveryStage.idle;
    }
    _subscription = service?.authStateChanges.listen(
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

  void _onAuthState(PasswordRecoveryAuthState state) {
    if (_disposed) return;
    final session = state.session;
    if (state.event == PasswordRecoveryAuthEvent.recovery &&
        session != null &&
        session.userId == _service?.currentSession?.userId) {
      final digest = session.digest;
      if (digest == _lastRecoveryDigest) return;
      _lastRecoveryDigest = digest;
      _generation++;
      _callbackTimeout?.cancel();
      _recoveryUserId = session.userId;
      _activeRecoveryDigest = digest;
      _stage = PasswordRecoveryStage.ready;
      _failure = null;
      _notify();
    } else if (state.event == PasswordRecoveryAuthEvent.tokenRefreshed &&
        _recoveryUserId != null &&
        session?.userId == _recoveryUserId &&
        session?.digest == _service?.currentSession?.digest) {
      _activeRecoveryDigest = session!.digest;
      _notify();
    } else if (state.event == PasswordRecoveryAuthEvent.signedOut ||
        state.event == PasswordRecoveryAuthEvent.signedIn ||
        (_recoveryUserId != null && session?.userId != _recoveryUserId)) {
      _generation++;
      _recoveryUserId = null;
      _activeRecoveryDigest = null;
      if (_stage != PasswordRecoveryStage.checking) {
        _stage = PasswordRecoveryStage.idle;
      }
      _notify();
    }
  }

  @override
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
    _callbackTimeout = Timer(_requestTimeout, () {
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

  @override
  Future<bool> requestEmail(
    String email, {
    required String redirectTo,
    String? captchaToken,
  }) async {
    if (_disposed || _sending) return false;
    _failure = validateAccountEmail(email);
    final service = _service;
    if (_failure != null || service == null) {
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
      await service.requestEmail(
        email.trim(),
        redirectTo: localizedAccountAuthRedirect(redirectTo, _locale?.call()),
        captchaToken: captchaToken,
      );
      return !_disposed;
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

  @override
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
    final service = _service!;
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
      await service.updatePassword(password);
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

  @override
  void clearFailure() {
    if (_failure == null) return;
    _failure = null;
    _notify();
  }

  @override
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

  final _states = StreamController<PasswordRecoveryState>.broadcast(sync: true);
  @override
  PasswordRecoveryState get state => (
    stage: stage,
    failure: failure,
    sending: sending,
    updating: updating,
    takingLonger: takingLonger,
    available: available,
    canSave: canSave,
    needsRoute: needsRoute,
  );
  @override
  Stream<PasswordRecoveryState> watchState() async* {
    yield state;
    yield* _states.stream;
  }

  void _notify() {
    if (!_disposed) _states.add(state);
  }

  @override
  void dispose() {
    _disposed = true;
    _callbackTimeout?.cancel();
    _slowUpdateTimer?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_states.close());
  }
}
