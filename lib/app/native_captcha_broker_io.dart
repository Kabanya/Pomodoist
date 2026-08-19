import 'dart:async';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import 'captcha_security.dart';

class NativeCaptchaBroker {
  NativeCaptchaBroker({
    required Stream<Uri> uriStream,
    NativeCaptchaBuildConfig? config,
    Future<bool> Function(Uri uri)? launch,
    CaptchaTimeoutSchedule? scheduleTimeout,
    bool? useLoopback,
  }) : _uriStream = uriStream,
       _config = config ?? NativeCaptchaBuildConfig.fromEnvironment(),
       _launch = launch ?? _launchExternally,
       _scheduleTimeout = scheduleTimeout ?? _scheduleRequestTimeout,
       _useLoopback = useLoopback ?? (Platform.isWindows || Platform.isLinux);

  final Stream<Uri> _uriStream;
  final NativeCaptchaBuildConfig _config;
  final Future<bool> Function(Uri uri) _launch;
  final CaptchaTimeoutSchedule _scheduleTimeout;
  final bool _useLoopback;
  _NativeCaptchaRequest? _activeRequest;

  Future<String> requestToken() {
    if (_activeRequest != null) {
      throw const NativeCaptchaException(NativeCaptchaFailureCode.unavailable);
    }
    final completer = Completer<String>();
    final request = _NativeCaptchaRequest(completer);
    _activeRequest = request;
    unawaited(_beginRequest(request));
    return completer.future;
  }

  Future<void> _beginRequest(_NativeCaptchaRequest request) async {
    try {
      final callbackTarget = _useLoopback
          ? await _startLoopbackServer(request)
          : Uri.parse('pomodoist://captcha-callback');
      if (!identical(_activeRequest, request)) return;
      final session = NativeCaptchaSession(
        registrationUrl: _config.registrationUrl,
        callbackTarget: callbackTarget,
      );
      request.session = session;
      if (!_useLoopback) {
        request.linkSubscription = _uriStream.listen(
          (uri) => _handleUri(request, uri),
          onError: (_) => _fail(
            request,
            const NativeCaptchaException(
              NativeCaptchaFailureCode.invalidCallback,
            ),
          ),
        );
      }
      request.cancelTimeout = _scheduleTimeout(
        session.ttl,
        () => _fail(
          request,
          const NativeCaptchaException(NativeCaptchaFailureCode.expired),
        ),
      );
      final launched = await _launch(session.begin());
      if (identical(_activeRequest, request) && !launched) {
        _fail(
          request,
          const NativeCaptchaException(NativeCaptchaFailureCode.openFailed),
        );
      }
    } on NativeCaptchaException catch (error) {
      _fail(request, error);
    } on Object {
      _fail(
        request,
        const NativeCaptchaException(NativeCaptchaFailureCode.unavailable),
      );
    }
  }

  Future<Uri> _startLoopbackServer(_NativeCaptchaRequest request) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    if (!identical(_activeRequest, request)) {
      await server.close(force: true);
      throw const NativeCaptchaException(NativeCaptchaFailureCode.cancelled);
    }
    request.server = server;
    final callbackTarget = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: server.port,
      path: '/captcha-callback',
    );
    request.callbackTarget = callbackTarget;
    request.serverSubscription = server.listen(
      (httpRequest) => unawaited(_handleLoopbackRequest(request, httpRequest)),
      onError: (_) => _fail(
        request,
        const NativeCaptchaException(NativeCaptchaFailureCode.unavailable),
      ),
      cancelOnError: false,
    );
    return callbackTarget;
  }

  Future<void> _handleLoopbackRequest(
    _NativeCaptchaRequest request,
    HttpRequest httpRequest,
  ) async {
    if (!identical(_activeRequest, request)) {
      await _respondToLoopback(httpRequest, HttpStatus.gone, success: false);
      return;
    }
    final session = request.session;
    final target = request.callbackTarget;
    if (session == null ||
        target == null ||
        httpRequest.method != 'GET' ||
        httpRequest.uri.path != target.path) {
      await _respondToLoopback(
        httpRequest,
        HttpStatus.badRequest,
        success: false,
      );
      return;
    }
    final callback = target.replace(
      query: httpRequest.uri.hasQuery ? httpRequest.uri.query : null,
    );
    try {
      if (!session.isCallbackForPendingRequest(callback)) {
        await _respondToLoopback(
          httpRequest,
          HttpStatus.badRequest,
          success: false,
        );
        return;
      }
      final token = session.consumeCallback(callback);
      await _respondToLoopback(httpRequest, HttpStatus.ok, success: true);
      if (_clear(request) && !request.completer.isCompleted) {
        request.completer.complete(token);
      }
    } on Object {
      await _respondToLoopback(
        httpRequest,
        HttpStatus.badRequest,
        success: false,
      );
    }
  }

  void _handleUri(_NativeCaptchaRequest request, Uri uri) {
    if (!identical(_activeRequest, request)) return;
    if (uri.scheme != 'pomodoist' || uri.host != 'captcha-callback') return;
    final session = request.session;
    if (session == null) return;
    try {
      if (!session.isCallbackForPendingRequest(uri)) return;
      final token = session.consumeCallback(uri);
      _clear(request);
      request.completer.complete(token);
    } on Object {
      _fail(
        request,
        const NativeCaptchaException(NativeCaptchaFailureCode.invalidCallback),
      );
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
        const NativeCaptchaException(NativeCaptchaFailureCode.cancelled),
      );
    }
  }

  bool _clear(_NativeCaptchaRequest request) {
    if (!identical(_activeRequest, request)) return false;
    _activeRequest = null;
    final linkSubscription = request.linkSubscription;
    request.linkSubscription = null;
    if (linkSubscription != null) unawaited(linkSubscription.cancel());
    final serverSubscription = request.serverSubscription;
    request.serverSubscription = null;
    if (serverSubscription != null) unawaited(serverSubscription.cancel());
    final server = request.server;
    request.server = null;
    if (server != null) unawaited(server.close(force: true));
    request.cancelTimeout?.call();
    request.cancelTimeout = null;
    request.session?.cancel();
    request.session = null;
    return true;
  }

  void dispose() => cancel();
}

final class _NativeCaptchaRequest {
  _NativeCaptchaRequest(this.completer);

  final Completer<String> completer;
  NativeCaptchaSession? session;
  Uri? callbackTarget;
  StreamSubscription<Uri>? linkSubscription;
  HttpServer? server;
  StreamSubscription<HttpRequest>? serverSubscription;
  CaptchaTimeoutCancel? cancelTimeout;
}

Future<void> _respondToLoopback(
  HttpRequest request,
  int status, {
  required bool success,
}) async {
  try {
    final locale = _preferredLoopbackLocale(
      request.headers.value(HttpHeaders.acceptLanguageHeader),
    );
    final copy = _loopbackCopy(locale);
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.html
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
      ..headers.set('Referrer-Policy', 'no-referrer')
      ..headers.set('X-Content-Type-Options', 'nosniff')
      ..write(
        success
            ? '<!doctype html><html lang="$locale" dir="${copy.direction}">'
                  '<meta charset="utf-8"><title>Pomodoist</title>'
                  '<p>${copy.success}</p></html>'
            : '<!doctype html><html lang="$locale" dir="${copy.direction}">'
                  '<meta charset="utf-8"><title>Pomodoist</title>'
                  '<p>${copy.invalid}</p></html>',
      );
    await request.response.close();
  } on Object {
    // A browser closing the callback tab must not expose or invalidate tokens.
  }
}

String _preferredLoopbackLocale(String? acceptLanguage) {
  const supported = {'ar', 'de', 'en', 'es', 'fr', 'ru', 'zh'};
  for (final entry in (acceptLanguage ?? '').split(',')) {
    final language = entry
        .split(';')
        .first
        .trim()
        .toLowerCase()
        .split('-')
        .first;
    if (supported.contains(language)) return language;
  }
  return 'en';
}

({String success, String invalid, String direction}) _loopbackCopy(
  String locale,
) {
  return switch (locale) {
    'ar' => (
      success: 'اكتمل التحقق. يمكنك إغلاق علامة التبويب والعودة إلى Pomodoist.',
      invalid: 'رابط التحقق هذا غير صالح.',
      direction: 'rtl',
    ),
    'de' => (
      success:
          'Prüfung abgeschlossen. Du kannst diesen Tab schließen und zu Pomodoist zurückkehren.',
      invalid: 'Dieser Prüfungslink ist ungültig.',
      direction: 'ltr',
    ),
    'es' => (
      success:
          'Verificación completada. Puedes cerrar esta pestaña y volver a Pomodoist.',
      invalid: 'Este enlace de verificación no es válido.',
      direction: 'ltr',
    ),
    'fr' => (
      success:
          'Vérification terminée. Vous pouvez fermer cet onglet et revenir dans Pomodoist.',
      invalid: 'Ce lien de vérification est invalide.',
      direction: 'ltr',
    ),
    'ru' => (
      success:
          'Проверка завершена. Закройте эту вкладку и вернитесь в Pomodoist.',
      invalid: 'Ссылка проверки недействительна.',
      direction: 'ltr',
    ),
    'zh' => (
      success: '验证完成。你可以关闭此标签页并返回 Pomodoist。',
      invalid: '此验证链接无效。',
      direction: 'ltr',
    ),
    _ => (
      success:
          'Verification complete. You can close this tab and return to Pomodoist.',
      invalid: 'This verification callback is invalid.',
      direction: 'ltr',
    ),
  };
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
