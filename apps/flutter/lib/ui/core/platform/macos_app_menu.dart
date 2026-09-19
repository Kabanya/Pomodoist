import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const macOSAppMenuChannelName = 'pomodoist/app_menu';
const macOSAppMenuSetCommandsMethod = 'setCommands';
const macOSAppMenuSelectedMethod = 'selected';

class MacOSMenuCommand {
  const MacOSMenuCommand({
    required this.id,
    required this.label,
    required this.keyLabel,
    required this.meta,
    required this.control,
    required this.alt,
    required this.shift,
  });

  final String id;
  final String label;
  final String keyLabel;
  final bool meta;
  final bool control;
  final bool alt;
  final bool shift;
}

class MacOSAppMenuController {
  MacOSAppMenuController({
    MethodChannel channel = const MethodChannel(macOSAppMenuChannelName),
    TargetPlatform? platform,
    ValueChanged<String>? onSelected,
    this.allowedCommandIds = const {},
  }) : _channel = channel,
       _platform = platform ?? defaultTargetPlatform,
       _onSelected = onSelected {
    if (_platform == TargetPlatform.macOS) {
      _channel.setMethodCallHandler(handleMethodCall);
    }
  }

  final MethodChannel _channel;
  final TargetPlatform _platform;
  final ValueChanged<String>? _onSelected;
  final Set<String> allowedCommandIds;
  String? _lastPayload;

  Future<void> sync({
    required Iterable<MacOSMenuCommand> commands,
    String? locale,
  }) async {
    if (_platform != TargetPlatform.macOS) return;

    final payload = {
      'locale': ?locale,
      for (final command in commands)
        command.id: {
          'label': command.label,
          'keyLabel': command.keyLabel,
          'meta': command.meta,
          'control': command.control,
          'alt': command.alt,
          'shift': command.shift,
        },
    };
    final signature = jsonEncode(payload);
    if (_lastPayload == signature) return;
    _lastPayload = signature;
    try {
      await _channel.invokeMethod<void>(macOSAppMenuSetCommandsMethod, payload);
    } on MissingPluginException {
      if (_lastPayload == signature) _lastPayload = null;
    }
  }

  Future<void> handleMethodCall(MethodCall call) async {
    if (call.method != macOSAppMenuSelectedMethod ||
        call.arguments is! String) {
      return;
    }
    final command = call.arguments as String;
    if (allowedCommandIds.contains(command)) _onSelected?.call(command);
  }

  void dispose() {
    if (_platform == TargetPlatform.macOS) {
      _channel.setMethodCallHandler(null);
    }
  }
}
