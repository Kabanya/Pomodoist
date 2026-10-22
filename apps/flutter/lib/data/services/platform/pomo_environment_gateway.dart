import 'package:flutter/services.dart';

abstract interface class PomoNativeEnvironmentGateway {
  Future<Object?> environment();
  Future<Object?> cursor();
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
}
