import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

const quickAddChannelName = 'pomodoist/quick_add';
const quickAddCreateTaskMethod = 'createTask';
const quickAddGetHintMethod = 'getQuickAddHint';
const quickAddGetGlobalShortcutMethod = 'getGlobalShortcut';
const quickAddCaptureGlobalShortcutMethod = 'captureGlobalShortcut';
const quickAddCancelGlobalShortcutCaptureMethod = 'cancelGlobalShortcutCapture';
const quickAddSetGlobalShortcutMethod = 'setGlobalShortcut';

const macOSDefaultGlobalShortcut = MacOSGlobalShortcut(
  keyCode: 49,
  keyLabel: 'Space',
  alt: true,
);

@immutable
class MacOSGlobalShortcut {
  const MacOSGlobalShortcut({
    required this.keyCode,
    required this.keyLabel,
    this.meta = false,
    this.control = false,
    this.alt = false,
    this.shift = false,
  });

  final int keyCode;
  final String keyLabel;
  final bool meta;
  final bool control;
  final bool alt;
  final bool shift;

  String get displaySignature =>
      '${keyLabel.trim().toUpperCase()}:${meta ? 1 : 0}:${control ? 1 : 0}:${alt ? 1 : 0}:${shift ? 1 : 0}';

  String get label => [
    if (control) '⌃',
    if (alt) '⌥',
    if (shift) '⇧',
    if (meta) '⌘',
    keyLabel,
  ].join();

  Map<String, Object> toJson() => {
    'keyCode': keyCode,
    'keyLabel': keyLabel,
    'meta': meta,
    'control': control,
    'alt': alt,
    'shift': shift,
  };

  static MacOSGlobalShortcut fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Missing macOS shortcut payload.');
    }
    final keyCode = value['keyCode'];
    final keyLabel = value['keyLabel'];
    final meta = value['meta'];
    final control = value['control'];
    final alt = value['alt'];
    final shift = value['shift'];
    if (keyCode is! int ||
        keyLabel is! String ||
        meta is! bool ||
        control is! bool ||
        alt is! bool ||
        shift is! bool) {
      throw const FormatException('Invalid macOS shortcut payload.');
    }
    return MacOSGlobalShortcut(
      keyCode: keyCode,
      keyLabel: keyLabel,
      meta: meta,
      control: control,
      alt: alt,
      shift: shift,
    );
  }
}

final platformQuickAddControllerProvider = Provider<PlatformQuickAddController>(
  (ref) {
    final controller = PlatformQuickAddController(ref);
    controller.initialize();
    ref.onDispose(controller.dispose);
    return controller;
  },
);

class PlatformQuickAddController {
  PlatformQuickAddController(
    this._ref, {
    MethodChannel channel = const MethodChannel(quickAddChannelName),
  }) : _channel = channel;

  final Ref _ref;
  final MethodChannel _channel;
  bool _initialized = false;

  void initialize() {
    if (_initialized) {
      return;
    }
    _channel.setMethodCallHandler(handleMethodCall);
    _initialized = true;
  }

  void dispose() {
    if (!_initialized) {
      return;
    }
    _channel.setMethodCallHandler(null);
    _initialized = false;
  }

  @visibleForTesting
  Future<Object?> handleMethodCall(MethodCall call) {
    return switch (call.method) {
      quickAddCreateTaskMethod => _createTask(call.arguments),
      quickAddGetHintMethod => _effectiveHint(),
      _ => throw MissingPluginException(
        'No method ${call.method} on $quickAddChannelName',
      ),
    };
  }

  Future<MacOSGlobalShortcut> getGlobalShortcut() async {
    return MacOSGlobalShortcut.fromJson(
      await _channel.invokeMethod<Object?>(quickAddGetGlobalShortcutMethod),
    );
  }

  Future<MacOSGlobalShortcut> captureGlobalShortcut() async {
    return MacOSGlobalShortcut.fromJson(
      await _channel.invokeMethod<Object?>(quickAddCaptureGlobalShortcutMethod),
    );
  }

  Future<void> cancelGlobalShortcutCapture() {
    return _channel.invokeMethod<void>(
      quickAddCancelGlobalShortcutCaptureMethod,
    );
  }

  Future<void> setGlobalShortcut(MacOSGlobalShortcut shortcut) {
    return _channel.invokeMethod<void>(
      quickAddSetGlobalShortcutMethod,
      shortcut.toJson(),
    );
  }

  Future<String> _effectiveHint() async {
    return _ref.read(effectiveQuickAddHintProvider);
  }

  Future<String> _createTask(Object? arguments) async {
    if (arguments is! String) {
      throw PlatformException(
        code: 'invalid_arguments',
        message: 'Expected a task description string.',
      );
    }

    final input = arguments.trim();
    if (input.isEmpty) {
      throw PlatformException(
        code: 'empty_task',
        message: 'Task content is empty.',
      );
    }

    try {
      await _ref.read(appStartupProvider.future);
      return await _ref.read(quickAddServiceProvider).createTask(input);
    } on PlatformException {
      rethrow;
    } catch (error) {
      throw PlatformException(
        code: 'create_task_failed',
        message: error.toString(),
      );
    }
  }
}
