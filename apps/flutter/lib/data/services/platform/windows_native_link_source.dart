import 'dart:async';

// `package:flutter/services.dart` exports its own `appFlavor` (the raw
// `FLUTTER_APP_FLAVOR` define). The domain `appFlavor` is the richer one this
// file needs, so the Flutter constant is hidden.
import 'package:flutter/services.dart' hide appFlavor;

import 'package:pomodoist/domain/models/app_flavor.dart';

/// Name of the Windows platform channel that forwards deep links.
///
/// Deliberately flavor-independent: the native runner registers the same
/// channel in every build, and the flavor is decided by the URL scheme of the
/// links it forwards.
const windowsNativeLinksChannelName = 'pomodoist/native_links';

final class WindowsNativeLinkSource {
  WindowsNativeLinkSource({
    MethodChannel channel = const MethodChannel(windowsNativeLinksChannelName),
    Future<void> Function(Uri uri)? beforeEmit,
  }) : _channel = channel,
       _beforeEmit = beforeEmit;

  final MethodChannel _channel;
  final Future<void> Function(Uri uri)? _beforeEmit;
  final StreamController<Uri> _links = StreamController<Uri>();
  bool _started = false;
  bool _disposed = false;

  Stream<Uri> get links => _links.stream;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _channel.setMethodCallHandler(handleMethodCall);
  }

  Future<Object?> handleMethodCall(MethodCall call) async {
    if (_disposed || call.method != 'link' || call.arguments is! String) {
      return null;
    }
    final uri = Uri.tryParse(call.arguments as String);
    if (uri == null || uri.scheme != appFlavor.urlScheme) return null;
    try {
      await _beforeEmit?.call(uri);
    } on Object {
      // The sanitized route still needs to receive callback failures.
    }
    if (!_disposed) _links.add(uri);
    return null;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _channel.setMethodCallHandler(null);
    await _links.close();
  }
}

bool isWindowsAccountAuthCallback(Uri uri) {
  if (uri.scheme != appFlavor.urlScheme ||
      uri.host != 'login-callback' ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort) {
    return false;
  }
  final fragmentParameters = uri.hasFragment
      ? Uri(query: uri.fragment).queryParameters
      : const <String, String>{};
  bool hasParameter(String key) =>
      uri.queryParameters.containsKey(key) ||
      fragmentParameters.containsKey(key);
  return const {
    'access_token',
    'code',
    'error',
    'error_code',
    'error_description',
  }.any(hasParameter);
}
