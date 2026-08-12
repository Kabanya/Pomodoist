import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

import 'captcha_security.dart';

class NativeCaptchaBroker {
  NativeCaptchaBroker({
    required Stream<Uri> uriStream,
    NativeCaptchaBuildConfig? config,
    Future<bool> Function(Uri uri)? launch,
    CaptchaTimeoutSchedule? scheduleTimeout,
  }) : _uriStream = uriStream,
       _config = config ?? NativeCaptchaBuildConfig.fromEnvironment(),
       _launch = launch ?? _launchExternally,
       _scheduleTimeout = scheduleTimeout ?? _scheduleRequestTimeout;

  final Stream<Uri> _uriStream;
  final NativeCaptchaBuildConfig _config;
  final Future<bool> Function(Uri uri) _launch;
  final CaptchaTimeoutSchedule _scheduleTimeout;
  _NativeCaptchaRequest? _activeRequest;

  Future<String> requestToken() {
    if (_activeRequest != null) {
      throw StateError('A CAPTCHA challenge is already active');
    }
    final session = NativeCaptchaSession(
      registrationUrl: _config.registrationUrl,
    );
    final completer = Completer<String>();
    final request = _NativeCaptchaRequest(session, completer);
    _activeRequest = request;
    request.subscription = _uriStream.listen(
      (uri) => _handleUri(request, uri),
      onError: (_) =>
          _fail(request, const FormatException('Invalid CAPTCHA callback')),
    );
    request.cancelTimeout = _scheduleTimeout(
      session.ttl,
      () => _fail(request, StateError('Security verification expired')),
    );
    _launch(session.begin()).then(
      (launched) {
        if (!launched) {
          _fail(request, StateError('Unable to open security verification'));
        }
      },
      onError: (_) {
        _fail(request, StateError('Unable to open security verification'));
      },
    );
    return completer.future;
  }

  void _handleUri(_NativeCaptchaRequest request, Uri uri) {
    if (!identical(_activeRequest, request)) return;
    if (uri.scheme != 'pomodoist' || uri.host != 'captcha-callback') return;
    try {
      if (!request.session.isCallbackForPendingRequest(uri)) return;
      final token = request.session.consumeCallback(uri);
      _clear(request);
      request.completer.complete(token);
    } on Object {
      _fail(request, const FormatException('Invalid CAPTCHA callback'));
    }
  }

  void _fail(_NativeCaptchaRequest request, Object error) {
    if (!_clear(request)) return;
    if (!request.completer.isCompleted) {
      request.completer.completeError(error);
    }
  }

  void cancel() {
    final request = _activeRequest;
    if (request == null || !_clear(request)) return;
    if (!request.completer.isCompleted) {
      request.completer.completeError(
        StateError('Security verification cancelled'),
      );
    }
  }

  bool _clear(_NativeCaptchaRequest request) {
    if (!identical(_activeRequest, request)) return false;
    _activeRequest = null;
    final subscription = request.subscription;
    request.subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    request.cancelTimeout?.call();
    request.cancelTimeout = null;
    request.session.cancel();
    return true;
  }

  void dispose() => cancel();
}

final class _NativeCaptchaRequest {
  _NativeCaptchaRequest(this.session, this.completer);

  final NativeCaptchaSession session;
  final Completer<String> completer;
  StreamSubscription<Uri>? subscription;
  CaptchaTimeoutCancel? cancelTimeout;
}

Future<bool> _launchExternally(Uri uri) {
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

CaptchaTimeoutCancel _scheduleRequestTimeout(
  Duration timeout,
  void Function() callback,
) {
  final timer = Timer(timeout, callback);
  return timer.cancel;
}
