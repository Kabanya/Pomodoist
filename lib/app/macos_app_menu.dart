import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'keyboard_shortcuts.dart';

const macOSAppMenuChannelName = 'pomodoist/app_menu';
const macOSAppMenuSetCommandsMethod = 'setCommands';
const macOSAppMenuSelectedMethod = 'selected';

class MacOSAppMenuController {
  MacOSAppMenuController({
    MethodChannel channel = const MethodChannel(macOSAppMenuChannelName),
    TargetPlatform? platform,
    ValueChanged<AppShortcutCommand>? onSelected,
  }) : _channel = channel,
       _platform = platform ?? defaultTargetPlatform,
       _onSelected = onSelected {
    if (_platform == TargetPlatform.macOS) {
      _channel.setMethodCallHandler(handleMethodCall);
    }
  }

  final MethodChannel _channel;
  final TargetPlatform _platform;
  final ValueChanged<AppShortcutCommand>? _onSelected;
  String? _lastPayload;

  Future<void> sync({
    required Map<AppShortcutCommand, String> labels,
    required Map<AppShortcutCommand, AppShortcutBinding> bindings,
  }) async {
    if (_platform != TargetPlatform.macOS) return;

    final payload = {
      for (final command in AppShortcutCommand.values)
        command.name: {
          'label': labels[command]!,
          'keyLabel': bindings[command]!.keyLabel,
          'meta': bindings[command]!.meta,
          'control': bindings[command]!.control,
          'alt': bindings[command]!.alt,
          'shift': bindings[command]!.shift,
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
    final name = call.arguments as String;
    for (final command in AppShortcutCommand.values) {
      if (command.name == name) {
        _onSelected?.call(command);
        return;
      }
    }
  }

  void dispose() {
    if (_platform == TargetPlatform.macOS) {
      _channel.setMethodCallHandler(null);
    }
  }
}
