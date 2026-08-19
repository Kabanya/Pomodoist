import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

enum CaptchaStatus { awaiting, ready, submitting, expired, error }

enum NativeCaptchaFailureCode {
  cancelled,
  expired,
  unavailable,
  openFailed,
  invalidCallback,
}

final class NativeCaptchaException implements Exception {
  const NativeCaptchaException(this.code);

  final NativeCaptchaFailureCode code;

  @override
  String toString() => 'NativeCaptchaException(${code.name})';
}

typedef CaptchaTimeoutCancel = void Function();
typedef CaptchaTimeoutSchedule =
    CaptchaTimeoutCancel Function(Duration timeout, void Function() callback);

final class CaptchaLoadTimeoutGuard {
  CaptchaLoadTimeoutGuard({
    required Duration timeout,
    required void Function() onTimeout,
    CaptchaTimeoutSchedule? schedule,
  }) : _onTimeout = onTimeout {
    _cancel = (schedule ?? _scheduleTimeout)(timeout, _fire);
  }

  final void Function() _onTimeout;
  late final CaptchaTimeoutCancel _cancel;
  bool _active = true;

  void complete() {
    if (!_active) return;
    _active = false;
    _cancel();
  }

  void _fire() {
    if (!_active) return;
    _active = false;
    _onTimeout();
  }
}

CaptchaTimeoutCancel _scheduleTimeout(
  Duration timeout,
  void Function() callback,
) {
  final timer = Timer(timeout, callback);
  return timer.cancel;
}

final class CaptchaTokenController {
  CaptchaTokenController({required this.required});

  final bool required;
  CaptchaStatus _status = CaptchaStatus.awaiting;
  String? _token;
  int _generation = 0;

  CaptchaStatus get status => required ? _status : CaptchaStatus.ready;
  int get generation => _generation;
  bool get canSubmit => !required || _status == CaptchaStatus.ready;
  bool get submitting => _status == CaptchaStatus.submitting;

  bool acceptSolved(String token, int generation) {
    if (!required ||
        generation != _generation ||
        _status == CaptchaStatus.submitting ||
        !isValidCaptchaToken(token)) {
      return false;
    }
    _token = token;
    _status = CaptchaStatus.ready;
    return true;
  }

  void expire(int generation) {
    if (!required || generation != _generation || submitting) return;
    _generation += 1;
    _token = null;
    _status = CaptchaStatus.expired;
  }

  void reportError(int generation) {
    if (!required || generation != _generation || submitting) return;
    _generation += 1;
    _token = null;
    _status = CaptchaStatus.error;
  }

  String? beginRequest() {
    if (submitting) {
      throw const NativeCaptchaException(NativeCaptchaFailureCode.unavailable);
    }
    if (required && (_status != CaptchaStatus.ready || _token == null)) {
      throw const NativeCaptchaException(
        NativeCaptchaFailureCode.invalidCallback,
      );
    }
    final token = _token;
    _token = null;
    _status = CaptchaStatus.submitting;
    return token;
  }

  void finishRequest({Object? error}) {
    if (!submitting) return;
    _generation += 1;
    _token = null;
    _status = CaptchaStatus.awaiting;
  }

  void reset() {
    _generation += 1;
    _token = null;
    _status = CaptchaStatus.awaiting;
  }
}

final class CaptchaProtectedExecutor {
  const CaptchaProtectedExecutor(this.controller);

  final CaptchaTokenController controller;

  Future<T> run<T>(Future<T> Function(String? captchaToken) operation) async {
    final token = controller.beginRequest();
    try {
      return await operation(token);
    } finally {
      controller.finishRequest();
    }
  }
}

T? renderTurnstileSafely<T extends Object>({
  required CaptchaTokenController controller,
  required int generation,
  required void Function() onChanged,
  required T? Function() render,
}) {
  if (controller.generation != generation) return null;
  try {
    final result = render();
    if (result != null) return result;
  } on Object {
    // Browser interop errors must become a recoverable verification state.
  }
  if (controller.generation != generation) return null;
  controller.reportError(generation);
  onChanged();
  return null;
}

bool isValidCaptchaToken(String value) =>
    value.isNotEmpty &&
    value.length <= 2048 &&
    value.runes.every(
      (rune) => rune >= 0x20 && rune != 0x7f && (rune < 0x80 || rune > 0x9f),
    );

bool isValidCaptchaState(String value) =>
    value.length >= 32 &&
    value.length <= 128 &&
    RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);

bool isExactCaptchaReturnTarget(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.toString() == value &&
      _isCaptchaReturnTargetUri(uri);
}

bool _isCaptchaReturnTargetUri(Uri uri) {
  final customProtocol =
      uri.scheme == 'pomodoist' &&
      uri.host == 'captcha-callback' &&
      uri.path.isEmpty &&
      !uri.hasPort;
  final desktopLoopback =
      uri.scheme == 'http' &&
      uri.host == '127.0.0.1' &&
      uri.hasPort &&
      uri.port >= 1024 &&
      uri.port <= 65535 &&
      uri.path == '/captcha-callback';
  return (customProtocol || desktopLoopback) &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment;
}

bool isExactCaptchaCallbackUri(Uri uri) {
  return _isCaptchaCallbackForTarget(
    uri,
    Uri.parse('pomodoist://captcha-callback'),
  );
}

bool _isCaptchaCallbackForTarget(Uri uri, Uri target) {
  final keys = uri.queryParametersAll.keys.toSet();
  return _isCaptchaReturnTargetUri(target) &&
      uri.scheme == target.scheme &&
      uri.host == target.host &&
      uri.port == target.port &&
      uri.path == target.path &&
      uri.userInfo.isEmpty &&
      !uri.hasFragment &&
      keys.length == 2 &&
      keys.containsAll(const {'state', 'token'}) &&
      uri.queryParametersAll.values.every((values) => values.length == 1) &&
      isValidCaptchaState(uri.queryParameters['state'] ?? '') &&
      isValidCaptchaToken(uri.queryParameters['token'] ?? '');
}

final class CaptchaChallengeRequest {
  const CaptchaChallengeRequest._(this.state, this.returnTarget);

  final String state;
  final Uri returnTarget;

  factory CaptchaChallengeRequest.parse(Uri uri) {
    final parameters = uri.queryParametersAll;
    final fragmentParameters = Uri(query: uri.fragment).queryParametersAll;
    final relative = !uri.hasScheme && uri.host.isEmpty;
    final approvedAbsolute =
        uri.scheme == 'https' &&
        const {
          'app-test.pomodoist.com',
          'app.pomodoist.com',
        }.contains(uri.host);
    if ((!relative && !approvedAbsolute) ||
        uri.path != '/auth/challenge' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        !uri.hasFragment ||
        parameters.keys.toSet().length != 1 ||
        !parameters.keys.toSet().contains('returnTo') ||
        parameters.values.any((values) => values.length != 1) ||
        fragmentParameters.keys.toSet().length != 1 ||
        !fragmentParameters.keys.toSet().contains('state') ||
        fragmentParameters.values.any((values) => values.length != 1) ||
        !isExactCaptchaReturnTarget(uri.queryParameters['returnTo'] ?? '') ||
        !isValidCaptchaState(fragmentParameters['state']?.single ?? '')) {
      throw const FormatException('Invalid CAPTCHA challenge request');
    }
    return CaptchaChallengeRequest._(
      fragmentParameters['state']!.single,
      Uri.parse(uri.queryParameters['returnTo']!),
    );
  }

  Uri handoffUri(String token) {
    if (!isValidCaptchaToken(token)) {
      throw const FormatException('Invalid CAPTCHA token');
    }
    return returnTarget.replace(
      queryParameters: {'state': state, 'token': token},
    );
  }
}

typedef CaptchaHandoff = void Function(Uri callback);

final class CaptchaHandoffController {
  Uri? _callbackUri;

  Uri? get callbackUri => _callbackUri;

  bool solveAndHandoff(
    CaptchaChallengeRequest request,
    String token,
    CaptchaHandoff handoff,
  ) {
    if (_callbackUri != null) return false;
    final callback = request.handoffUri(token);
    _callbackUri = callback;
    _attempt(handoff, callback);
    return true;
  }

  bool retry(CaptchaHandoff handoff) {
    final callback = _callbackUri;
    if (callback == null) return false;
    _attempt(handoff, callback);
    return true;
  }

  void _attempt(CaptchaHandoff handoff, Uri callback) {
    try {
      handoff(callback);
    } on Object {
      // The visible fallback remains available when protocol launch is blocked.
    }
  }
}

typedef CaptchaClock = DateTime Function();
typedef CaptchaStateFactory = String Function();

final class NativeCaptchaBuildConfig {
  const NativeCaptchaBuildConfig._(this.registrationUrl);

  final Uri registrationUrl;

  factory NativeCaptchaBuildConfig.fromEnvironment() {
    return NativeCaptchaBuildConfig.fromValues(
      environment: const String.fromEnvironment(
        'POMODOIST_ENVIRONMENT',
        defaultValue: 'local',
      ),
      registrationUrl: const String.fromEnvironment(
        'POMODOIST_REGISTRATION_URL',
      ),
    );
  }

  factory NativeCaptchaBuildConfig.fromValues({
    required String environment,
    required String registrationUrl,
  }) {
    if (environment == 'local' && registrationUrl.isEmpty) {
      throw const FormatException(
        'Native CAPTCHA is unavailable in unconfigured local builds',
      );
    }
    final uri = Uri.tryParse(registrationUrl);
    if (uri == null) {
      throw const FormatException('Invalid CAPTCHA challenge URL');
    }
    _validateRegistrationUrl(uri);
    final expectedHost = switch (environment) {
      'staging' => 'app-test.pomodoist.com',
      'production' => 'app.pomodoist.com',
      _ => throw FormatException(
        'Native CAPTCHA is not configured for $environment',
      ),
    };
    if (uri.host != expectedHost) {
      throw const FormatException(
        'CAPTCHA challenge URL does not match the environment',
      );
    }
    return NativeCaptchaBuildConfig._(uri);
  }
}

final class NativeCaptchaSession {
  NativeCaptchaSession({
    required this.registrationUrl,
    Uri? callbackTarget,
    CaptchaClock? now,
    CaptchaStateFactory? stateFactory,
    this.ttl = const Duration(minutes: 5),
  }) : callbackTarget =
           callbackTarget ?? Uri.parse('pomodoist://captcha-callback'),
       _now = now ?? DateTime.now,
       _stateFactory = stateFactory ?? generateCaptchaState {
    _validateRegistrationUrl(registrationUrl);
    if (!_isCaptchaReturnTargetUri(this.callbackTarget)) {
      throw const FormatException('Unsupported CAPTCHA return target');
    }
  }

  final Uri registrationUrl;
  final Uri callbackTarget;
  final Duration ttl;
  final CaptchaClock _now;
  final CaptchaStateFactory _stateFactory;
  String? _pendingState;
  DateTime? _createdAt;

  bool get hasPending => _pendingState != null;

  Uri begin() {
    final state = _stateFactory();
    if (!isValidCaptchaState(state)) {
      throw const NativeCaptchaException(NativeCaptchaFailureCode.unavailable);
    }
    _pendingState = state;
    _createdAt = _now();
    return registrationUrl.replace(
      queryParameters: {'returnTo': callbackTarget.toString()},
      fragment: Uri(queryParameters: {'state': state}).query,
    );
  }

  String consumeCallback(Uri callback) {
    final pending = _pendingState;
    final createdAt = _createdAt;
    if (pending == null || createdAt == null) {
      throw const NativeCaptchaException(
        NativeCaptchaFailureCode.invalidCallback,
      );
    }
    if (_now().difference(createdAt) > ttl) {
      cancel();
      throw const NativeCaptchaException(NativeCaptchaFailureCode.expired);
    }
    _validateCallbackShape(callback, callbackTarget);
    final state = callback.queryParameters['state']!;
    final token = callback.queryParameters['token']!;
    if (state != pending) {
      throw const NativeCaptchaException(
        NativeCaptchaFailureCode.invalidCallback,
      );
    }
    cancel();
    return token;
  }

  bool isCallbackForPendingRequest(Uri callback) {
    final pending = _pendingState;
    if (pending == null) return false;
    _validateCallbackShape(callback, callbackTarget);
    return callback.queryParameters['state'] == pending;
  }

  void cancel() {
    _pendingState = null;
    _createdAt = null;
  }
}

String generateCaptchaState() {
  final bytes = Uint8List(32);
  final random = Random.secure();
  for (var index = 0; index < bytes.length; index += 1) {
    bytes[index] = random.nextInt(256);
  }
  return base64Url.encode(bytes).replaceAll('=', '');
}

void _validateRegistrationUrl(Uri uri) {
  if (uri.scheme != 'https' ||
      !const {
        'app-test.pomodoist.com',
        'app.pomodoist.com',
      }.contains(uri.host) ||
      uri.path != '/auth/challenge' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const FormatException('Unsupported CAPTCHA challenge URL');
  }
}

void _validateCallbackShape(Uri uri, Uri target) {
  if (!_isCaptchaCallbackForTarget(uri, target)) {
    throw const NativeCaptchaException(
      NativeCaptchaFailureCode.invalidCallback,
    );
  }
}
