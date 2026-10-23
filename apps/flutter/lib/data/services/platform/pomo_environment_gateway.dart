import 'package:flutter/services.dart';

abstract interface class PomoNativeEnvironmentGateway {
  Future<Object?> environment();
  Future<Object?> cursor();
  Future<Object?> gnomeExtensionStatus();
  Future<Object?> installGnomeExtension();
  Future<Object?> enableGnomeExtension();
  Future<void> setFollowing(bool enabled);
}

class MethodChannelPomoEnvironmentGateway
    implements PomoNativeEnvironmentGateway {
  const MethodChannelPomoEnvironmentGateway({
    MethodChannel channel = const MethodChannel('pomodoist/pomo_window'),
  }) : _channel = channel;
  final MethodChannel _channel;

  @override
  Future<Object?> environment() =>
      _channel.invokeMethod<Object?>('environment');
  @override
  Future<Object?> cursor() => _channel.invokeMethod<Object?>('cursor');
  @override
  Future<Object?> gnomeExtensionStatus() =>
      _channel.invokeMethod<Object?>('gnomeExtensionStatus');
  @override
  Future<Object?> installGnomeExtension() =>
      _channel.invokeMethod<Object?>('installGnomeExtension');
  @override
  Future<Object?> enableGnomeExtension() =>
      _channel.invokeMethod<Object?>('enableGnomeExtension');
  @override
  Future<void> setFollowing(bool enabled) =>
      _channel.invokeMethod<void>('setFollowing', {'enabled': enabled});
}
