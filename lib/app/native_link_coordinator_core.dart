import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'captcha_security.dart';

typedef NativeLinkClock = DateTime Function();
typedef NativeRouteSink = void Function(String location);
typedef NativeLinkExpirySchedule =
    CaptchaTimeoutCancel Function(Duration timeout, void Function() callback);

final class NativeLinkCoordinator {
  NativeLinkCoordinator({
    required Future<Uri?> Function() loadInitialLink,
    required Stream<Uri> linkStream,
    NativeLinkClock? now,
    NativeLinkExpirySchedule? scheduleFingerprintExpiry,
    this.duplicateWindow = const Duration(seconds: 2),
  }) : _loadInitialLink = loadInitialLink,
       _linkStream = linkStream,
       _now = now ?? DateTime.now,
       _scheduleFingerprintExpiry =
           scheduleFingerprintExpiry ?? _scheduleNativeLinkExpiry;

  final Future<Uri?> Function() _loadInitialLink;
  final Stream<Uri> _linkStream;
  final NativeLinkClock _now;
  final NativeLinkExpirySchedule _scheduleFingerprintExpiry;
  final Duration duplicateWindow;
  final StreamController<Uri> _captchaController =
      StreamController<Uri>.broadcast();
  StreamSubscription<Uri>? _subscription;
  NativeRouteSink? _routeSink;
  String? _pendingRoute;
  int _routeSinkGeneration = 0;
  String? _lastFingerprintDigest;
  DateTime? _lastHandledAt;
  CaptchaTimeoutCancel? _cancelFingerprintExpiry;
  int _fingerprintGeneration = 0;
  bool _prepared = false;
  bool _started = false;
  bool _disposed = false;

  Stream<Uri> get captchaCallbacks => _captchaController.stream;

  Future<void> prepare() async {
    if (_prepared || _disposed) return;
    _prepared = true;
    try {
      final initialLink = await _loadInitialLink();
      if (initialLink != null) _dispatch(initialLink);
    } on Object {
      // Initial link failures must not expose link contents through diagnostics.
    }
  }

  Future<void> start() async {
    if (_started || _disposed) return;
    if (!_prepared) {
      throw StateError('NativeLinkCoordinator.prepare must run first');
    }
    _started = true;
    _subscription = _linkStream.listen(
      _dispatch,
      onError: (Object error, StackTrace stackTrace) {},
    );
  }

  void Function() attachRouteSink(NativeRouteSink sink) {
    if (_disposed) return () {};
    final generation = ++_routeSinkGeneration;
    _routeSink = sink;
    final pendingRoute = _pendingRoute;
    _pendingRoute = null;
    if (pendingRoute != null) _deliverRoute(pendingRoute);
    return () {
      if (_routeSinkGeneration == generation) _routeSink = null;
    };
  }

  void _dispatch(Uri uri) {
    if (_disposed || _isDuplicate(uri)) return;
    if (isExactCaptchaCallbackUri(uri)) {
      _captchaController.add(uri);
      return;
    }
    final route = nativeRouteForLink(uri);
    if (route == null) return;
    if (_routeSink == null) {
      _pendingRoute = route;
    } else {
      _deliverRoute(route);
    }
  }

  bool _isDuplicate(Uri uri) {
    final now = _now();
    final fingerprint = nativeLinkFingerprint(uri);
    final lastHandledAt = _lastHandledAt;
    if (_lastFingerprintDigest == fingerprint &&
        lastHandledAt != null &&
        now.difference(lastHandledAt) <= duplicateWindow) {
      return true;
    }
    _clearFingerprint();
    _lastFingerprintDigest = fingerprint;
    _lastHandledAt = now;
    final generation = ++_fingerprintGeneration;
    _cancelFingerprintExpiry = _scheduleFingerprintExpiry(duplicateWindow, () {
      if (_disposed || generation != _fingerprintGeneration) return;
      _lastFingerprintDigest = null;
      _lastHandledAt = null;
      _cancelFingerprintExpiry = null;
    });
    return false;
  }

  void _clearFingerprint() {
    _fingerprintGeneration += 1;
    _cancelFingerprintExpiry?.call();
    _cancelFingerprintExpiry = null;
    _lastFingerprintDigest = null;
    _lastHandledAt = null;
  }

  void _deliverRoute(String route) {
    try {
      _routeSink?.call(route);
    } on Object {
      // Native link handling must not expose link contents through diagnostics.
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _routeSink = null;
    _pendingRoute = null;
    _clearFingerprint();
    await _subscription?.cancel();
    _subscription = null;
    await _captchaController.close();
  }
}

String nativeLinkFingerprint(Uri uri) {
  return sha256.convert(utf8.encode(uri.toString())).toString();
}

CaptchaTimeoutCancel _scheduleNativeLinkExpiry(
  Duration timeout,
  void Function() callback,
) {
  final timer = Timer(timeout, callback);
  return timer.cancel;
}

String? nativeRouteForLink(Uri uri) {
  if (_isExactFocusLink(uri)) return '/focus';
  if (_isExactPurchaseSuccessLink(uri)) {
    return '/purchase-success?source=stripe';
  }
  if (!_isLoginCallbackLink(uri)) return null;
  final returnToValues = uri.queryParametersAll['returnTo'];
  final returnTo = returnToValues?.length == 1
      ? _safeNativeReturnTo(returnToValues!.single)
      : '/settings';
  return Uri(
    path: '/login-callback',
    queryParameters: {'returnTo': returnTo},
  ).toString();
}

bool _isExactPurchaseSuccessLink(Uri uri) {
  return uri.scheme == 'pomodoist' &&
      uri.host == 'purchase-success' &&
      uri.path.isEmpty &&
      uri.userInfo.isEmpty &&
      !uri.hasPort &&
      !uri.hasQuery &&
      !uri.hasFragment;
}

bool _isExactFocusLink(Uri uri) {
  return uri.scheme == 'pomodoist' &&
      uri.host == 'focus' &&
      uri.path.isEmpty &&
      uri.userInfo.isEmpty &&
      !uri.hasPort &&
      !uri.hasQuery &&
      !uri.hasFragment;
}

bool _isLoginCallbackLink(Uri uri) {
  return uri.scheme == 'pomodoist' &&
      uri.host == 'login-callback' &&
      uri.path.isEmpty &&
      uri.userInfo.isEmpty &&
      !uri.hasPort;
}

String _safeNativeReturnTo(String value) {
  if (!value.startsWith('/') || value.startsWith('//')) return '/settings';
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.hasScheme ||
      uri.host.isNotEmpty ||
      uri.path == '/login-callback' ||
      uri.hasFragment) {
    return '/settings';
  }
  return uri.toString();
}
