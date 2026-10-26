import 'dart:async';

import 'package:flutter/services.dart';

import 'distraction_wayland_adapter.dart';

class DistractionNativeApp {
  const DistractionNativeApp({
    required this.id,
    required this.name,
    required this.platform,
  });
  final String id;
  final String name;
  final String platform;

  static DistractionNativeApp? fromNative(Object? value) {
    if (value is! Map) return null;
    final id = value['id'], name = value['name'], platform = value['platform'];
    if (id is! String ||
        name is! String ||
        platform is! String ||
        !const ['macos', 'windows', 'linux'].contains(platform) ||
        !id.startsWith('$platform:') ||
        id.length <= platform.length + 1 ||
        id.length > 512 ||
        id.contains('/') ||
        id.contains('\\') ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(id) ||
        name.length > 512) {
      return null;
    }
    return DistractionNativeApp(id: id, name: name, platform: platform);
  }
}

class DistractionNativeCapabilities {
  const DistractionNativeCapabilities({
    required this.supported,
    required this.platform,
    required this.discoveryAvailable,
    this.reason,
    this.adapter,
  });
  final bool supported;
  final String platform;
  final bool discoveryAvailable;
  final String? reason;
  final String? adapter;
}

/// App-lifetime host for foreground discovery and non-destructive native shields.
/// Consent is controlled by the caller using startDiscovery/stopDiscovery.
class DistractionNativeGateway {
  DistractionNativeGateway({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('pomodoist/distractions') {
    _channel.setMethodCallHandler(_handle);
    _wayland = createDistractionWaylandAdapter((method, payload) {
      unawaited(_handle(MethodCall(method, payload)));
    }, (method, arguments) => _channel.invokeMethod<void>(method, arguments));
  }
  final MethodChannel _channel;
  DistractionWaylandAdapter? _wayland;
  bool _useWayland = false;
  final _quitRequests = StreamController<void>.broadcast();
  Stream<void> get quitRequests => _quitRequests.stream;
  final _foreground = StreamController<DistractionNativeApp>.broadcast();
  final _blocked = StreamController<DistractionNativeApp>.broadcast();
  Stream<DistractionNativeApp> get foregroundApps => _foreground.stream;
  Stream<DistractionNativeApp> get blockedAttempts => _blocked.stream;

  Future<void> _handle(MethodCall call) async {
    if (call.method == 'requestQuit') {
      _quitRequests.add(null);
      return;
    }
    final app = DistractionNativeApp.fromNative(call.arguments);
    if (app == null) return;
    switch (call.method) {
      case 'foregroundApp':
        _foreground.add(app);
      case 'blockedAttempt':
        _blocked.add(app);
    }
  }

  Future<DistractionNativeCapabilities> capabilities() async {
    try {
      var raw = await _channel.invokeMapMethod<String, dynamic>('capabilities');
      if (raw?['supported'] != true && _wayland != null) {
        final wayland = await _wayland!.capabilities();
        if (wayland != null) {
          raw = wayland;
          _useWayland = wayland['supported'] == true;
        }
      }
      return DistractionNativeCapabilities(
        supported: raw?['supported'] == true,
        platform: raw?['platform'] as String? ?? 'unknown',
        discoveryAvailable: raw?['discoveryAvailable'] == true,
        reason: raw?['reason'] as String?,
        adapter: raw?['adapter'] as String?,
      );
    } on MissingPluginException {
      return const DistractionNativeCapabilities(
        supported: false,
        platform: 'unknown',
        discoveryAvailable: false,
        reason: 'Native protection is unavailable on this platform.',
      );
    }
  }

  Future<void> _invoke(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) => _useWayland
      ? _wayland!.command(method, arguments)
      : _channel.invokeMethod<void>(method, arguments);
  Future<void> startDiscovery() => _invoke('startDiscovery');
  Future<void> stopDiscovery() => _invoke('stopDiscovery');
  Future<void> clearProtection() => _invoke('clearProtection');
  Future<void> allowQuit() async {
    await clearProtection();
    await _channel.invokeMethod<void>('allowQuit');
  }

  Future<void> setProtection({
    required bool active,
    required List<String> blockedApps,
    required String taskTitle,
    required int remainingSeconds,
    required DateTime expiresAt,
    Uint8List? mascotImage,
    bool countdown = true,
  }) => _invoke('setProtection', {
    'active': active,
    'blockedApps': blockedApps,
    'taskTitle': taskTitle,
    'remainingSeconds': remainingSeconds,
    'countdown': countdown,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'mascotImage': ?mascotImage,
  });

  Future<void> dispose() async {
    try {
      await clearProtection();
      await stopDiscovery();
    } on MissingPluginException {
      /* Unsupported platform owns no native resources. */
    } finally {
      await _wayland?.dispose();
      _channel.setMethodCallHandler(null);
      await _quitRequests.close();
      await _foreground.close();
      await _blocked.close();
    }
  }
}
