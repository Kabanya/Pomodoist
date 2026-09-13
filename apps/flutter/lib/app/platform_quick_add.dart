import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'keyboard_shortcuts.dart';
import 'global_quick_add_window.dart';
import 'linux_global_shortcuts.dart';
import 'providers.dart';

const quickAddChannelName = 'pomodoist/quick_add';
const quickAddCreateTaskMethod = 'createTask';
const quickAddGetHintMethod = 'getQuickAddHint';
const quickAddShowWindowMethod = 'showQuickAdd';
const quickAddGetGlobalShortcutMethod = 'getGlobalShortcut';
const quickAddCaptureGlobalShortcutMethod = 'captureGlobalShortcut';
const quickAddCancelGlobalShortcutCaptureMethod = 'cancelGlobalShortcutCapture';
const quickAddSetGlobalShortcutMethod = 'setGlobalShortcut';
const quickAddSetGlobalShortcutEnabledMethod = 'setGlobalShortcutEnabled';
const globalQuickAddEnabledPreferenceKey = 'quick_add.global.enabled';
const globalQuickAddBindingPreferenceKey = 'quick_add.global.binding';

const macOSDefaultGlobalShortcut = GlobalQuickAddBinding(
  keyCode: 49,
  keyLabel: 'Space',
  alt: true,
);

@immutable
class GlobalQuickAddBinding {
  const GlobalQuickAddBinding({
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

  factory GlobalQuickAddBinding.defaultFor(TargetPlatform platform) {
    if (platform == TargetPlatform.macOS) {
      return macOSDefaultGlobalShortcut;
    }
    return const GlobalQuickAddBinding(
      keyCode: 32,
      keyLabel: 'Space',
      control: true,
      alt: true,
    );
  }

  String get displaySignature =>
      '${keyLabel.trim().toUpperCase()}:${meta ? 1 : 0}:${control ? 1 : 0}:${alt ? 1 : 0}:${shift ? 1 : 0}';

  String labelFor(TargetPlatform platform) {
    if (platform == TargetPlatform.macOS) {
      return [
        if (control) '⌃',
        if (alt) '⌥',
        if (shift) '⇧',
        if (meta) '⌘',
        keyLabel,
      ].join();
    }
    return [
      if (control) 'Ctrl',
      if (alt) 'Alt',
      if (shift) 'Shift',
      if (meta) 'Meta',
      keyLabel,
    ].join('+');
  }

  String get label => labelFor(TargetPlatform.macOS);

  String get portalTrigger => [
    if (control) 'CTRL',
    if (alt) 'ALT',
    if (shift) 'SHIFT',
    if (meta) 'LOGO',
    switch (keyLabel.toLowerCase()) {
      'enter' => 'Return',
      'escape' || 'esc' => 'Escape',
      'page up' => 'Page_Up',
      'page down' => 'Page_Down',
      final key => key,
    },
  ].join('+');

  Map<String, Object> toJson() => {
    'keyCode': keyCode,
    'keyLabel': keyLabel,
    'meta': meta,
    'control': control,
    'alt': alt,
    'shift': shift,
  };

  static GlobalQuickAddBinding fromJson(Object? value) {
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
    return GlobalQuickAddBinding(
      keyCode: keyCode,
      keyLabel: keyLabel,
      meta: meta,
      control: control,
      alt: alt,
      shift: shift,
    );
  }
}

typedef MacOSGlobalShortcut = GlobalQuickAddBinding;

@immutable
class GlobalQuickAddState {
  const GlobalQuickAddState({
    required this.enabled,
    required this.binding,
    this.registrationError,
  });

  final bool enabled;
  final GlobalQuickAddBinding binding;
  final Object? registrationError;

  GlobalQuickAddState copyWith({
    bool? enabled,
    GlobalQuickAddBinding? binding,
    Object? registrationError,
    bool clearRegistrationError = false,
  }) {
    return GlobalQuickAddState(
      enabled: enabled ?? this.enabled,
      binding: binding ?? this.binding,
      registrationError: clearRegistrationError
          ? null
          : registrationError ?? this.registrationError,
    );
  }
}

final platformQuickAddControllerProvider = Provider<PlatformQuickAddController>(
  (ref) {
    final controller = PlatformQuickAddController(
      ref,
      platform: ref.watch(shortcutTargetPlatformProvider),
    );
    controller.initialize();
    ref.onDispose(controller.dispose);
    return controller;
  },
);

class PlatformQuickAddController extends ChangeNotifier {
  PlatformQuickAddController(
    this._ref, {
    MethodChannel channel = const MethodChannel(quickAddChannelName),
    TargetPlatform? platform,
    LinuxGlobalShortcutsPortal? linuxPortal,
  }) : _channel = channel,
       _platform = platform ?? defaultTargetPlatform,
       _linuxPortal =
           !kIsWeb &&
               (platform ?? defaultTargetPlatform) == TargetPlatform.linux
           ? linuxPortal ?? LinuxGlobalShortcutsPortal()
           : null,
       state = GlobalQuickAddState(
         enabled: true,
         binding: GlobalQuickAddBinding.defaultFor(
           platform ?? defaultTargetPlatform,
         ),
       );

  final Ref _ref;
  final MethodChannel _channel;
  final TargetPlatform _platform;
  final LinuxGlobalShortcutsPortal? _linuxPortal;
  bool _useLinuxPortal = false;
  bool _initialized = false;
  bool _disposed = false;
  late Future<void> ready;
  GlobalQuickAddState state;

  void initialize() {
    if (_initialized) {
      return;
    }
    _channel.setMethodCallHandler(handleMethodCall);
    _initialized = true;
    ready = _loadState();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_initialized) {
      _channel.setMethodCallHandler(null);
      _initialized = false;
    }
    unawaited(_linuxPortal?.dispose());
    super.dispose();
  }

  @visibleForTesting
  Future<Object?> handleMethodCall(MethodCall call) {
    return switch (call.method) {
      quickAddCreateTaskMethod => _createTask(call.arguments),
      quickAddGetHintMethod => _effectiveHint(),
      quickAddShowWindowMethod => globalQuickAddWindowManager.show(),
      _ => throw MissingPluginException(
        'No method ${call.method} on $quickAddChannelName',
      ),
    };
  }

  Future<GlobalQuickAddBinding> getGlobalShortcut() async {
    final binding = GlobalQuickAddBinding.fromJson(
      await _channel.invokeMethod<Object?>(quickAddGetGlobalShortcutMethod),
    );
    state = state.copyWith(binding: binding, clearRegistrationError: true);
    _notifyListeners();
    return binding;
  }

  Future<GlobalQuickAddBinding> captureGlobalShortcut() async {
    return GlobalQuickAddBinding.fromJson(
      await _channel.invokeMethod<Object?>(quickAddCaptureGlobalShortcutMethod),
    );
  }

  Future<void> cancelGlobalShortcutCapture() {
    return _channel.invokeMethod<void>(
      quickAddCancelGlobalShortcutCaptureMethod,
    );
  }

  Future<void> setGlobalShortcut(GlobalQuickAddBinding shortcut) async {
    try {
      if (_useLinuxPortal && state.enabled) {
        try {
          await _linuxPortal!.enable(
            preferredTrigger: shortcut.portalTrigger,
            onActivated: globalQuickAddWindowManager.show,
          );
        } catch (_) {
          try {
            await _linuxPortal!.enable(
              preferredTrigger: state.binding.portalTrigger,
              onActivated: globalQuickAddWindowManager.show,
            );
          } on Object {
            // Keep reporting the candidate registration failure.
          }
          rethrow;
        }
      } else if (!_useLinuxPortal && state.enabled) {
        await _channel.invokeMethod<void>(
          quickAddSetGlobalShortcutMethod,
          shortcut.toJson(),
        );
      }
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        globalQuickAddBindingPreferenceKey,
        jsonEncode(shortcut.toJson()),
      );
      state = state.copyWith(binding: shortcut, clearRegistrationError: true);
      _notifyListeners();
    } catch (error) {
      state = state.copyWith(registrationError: error);
      _notifyListeners();
      rethrow;
    }
  }

  Future<void> setGlobalQuickAddEnabled(bool enabled) async {
    if (state.enabled == enabled) {
      return;
    }
    try {
      if (_useLinuxPortal) {
        if (enabled) {
          await _linuxPortal!.enable(
            preferredTrigger: state.binding.portalTrigger,
            onActivated: globalQuickAddWindowManager.show,
          );
        } else {
          await _linuxPortal!.disable();
        }
      } else {
        if (enabled) {
          await _channel.invokeMethod<void>(
            quickAddSetGlobalShortcutMethod,
            state.binding.toJson(),
          );
        }
        await _channel.invokeMethod<void>(
          quickAddSetGlobalShortcutEnabledMethod,
          enabled,
        );
      }
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(globalQuickAddEnabledPreferenceKey, enabled);
      if (!enabled) await globalQuickAddWindowManager.close();
      state = state.copyWith(enabled: enabled, clearRegistrationError: true);
      _notifyListeners();
    } catch (error) {
      state = state.copyWith(registrationError: error);
      _notifyListeners();
      rethrow;
    }
  }

  Future<void> _loadState() async {
    final preferences = await SharedPreferences.getInstance();
    final enabled =
        preferences.getBool(globalQuickAddEnabledPreferenceKey) ?? true;
    state = state.copyWith(enabled: enabled);
    if (kIsWeb ||
        !const {
          TargetPlatform.macOS,
          TargetPlatform.windows,
          TargetPlatform.linux,
        }.contains(_platform)) {
      _notifyListeners();
      return;
    }
    try {
      _useLinuxPortal = await _linuxPortal?.isAvailable() ?? false;
      final storedBinding = preferences.getString(
        globalQuickAddBindingPreferenceKey,
      );
      final binding = storedBinding == null
          ? _useLinuxPortal
                ? state.binding
                : await getGlobalShortcut()
          : GlobalQuickAddBinding.fromJson(jsonDecode(storedBinding));
      if (_useLinuxPortal) {
        if (enabled) {
          await _linuxPortal!.enable(
            preferredTrigger: binding.portalTrigger,
            onActivated: globalQuickAddWindowManager.show,
          );
        } else {
          await _linuxPortal!.disable();
        }
      } else {
        if (!enabled) {
          await _channel.invokeMethod<void>(
            quickAddSetGlobalShortcutEnabledMethod,
            false,
          );
        }
        if (storedBinding != null) {
          await _channel.invokeMethod<void>(
            quickAddSetGlobalShortcutMethod,
            binding.toJson(),
          );
        }
        if (enabled) {
          await _channel.invokeMethod<void>(
            quickAddSetGlobalShortcutEnabledMethod,
            true,
          );
        }
      }
      state = state.copyWith(
        enabled: enabled,
        binding: binding,
        clearRegistrationError: true,
      );
    } catch (error) {
      state = state.copyWith(registrationError: error);
    }
    _notifyListeners();
  }

  void _notifyListeners() {
    if (!_disposed) notifyListeners();
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
