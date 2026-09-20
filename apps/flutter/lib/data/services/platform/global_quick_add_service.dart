import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pomodoist/data/services/platform/global_shortcut_codec.dart';
import 'package:pomodoist/data/services/platform/linux_global_shortcuts.dart';
import 'package:pomodoist/domain/models/platform/global_shortcut.dart';

const quickAddChannelName = 'pomodoist/quick_add';
const quickAddCreateTaskMethod = 'createTask';
const quickAddGetHintMethod = 'getQuickAddHint';
const quickAddShowWindowMethod = 'showQuickAdd';
const quickAddGetGlobalShortcutMethod = 'getGlobalShortcut';
const quickAddCaptureGlobalShortcutMethod = 'captureGlobalShortcut';
const quickAddCancelGlobalShortcutCaptureMethod = 'cancelGlobalShortcutCapture';
const quickAddSetGlobalShortcutMethod = 'setGlobalShortcut';
const quickAddSetGlobalShortcutEnabledMethod = 'setGlobalShortcutEnabled';

/// Native channel and shortcut-registration I/O. Application state belongs to
/// the repository; composition supplies the window and task entry points.
class GlobalQuickAddService {
  GlobalQuickAddService({
    required this.createTask,
    required this.readHint,
    required this.showWindow,
    required this.closeWindow,
    required TargetPlatform platform,
    MethodChannel channel = const MethodChannel(quickAddChannelName),
    LinuxGlobalShortcutsPortal? linuxPortal,
  }) : _channel = channel,
       supported =
           !kIsWeb &&
           const {
             TargetPlatform.macOS,
             TargetPlatform.windows,
             TargetPlatform.linux,
           }.contains(platform),
       defaultBinding = GlobalQuickAddBinding.defaultFor(
         isMacOS: platform == TargetPlatform.macOS,
       ),
       _linuxPortal = !kIsWeb && platform == TargetPlatform.linux
           ? linuxPortal ?? LinuxGlobalShortcutsPortal()
           : null {
    _channel.setMethodCallHandler(handleMethodCall);
  }

  final Future<String> Function(String) createTask;
  final Future<String> Function() readHint;
  final Future<void> Function() showWindow;
  final Future<void> Function() closeWindow;
  final MethodChannel _channel;
  final LinuxGlobalShortcutsPortal? _linuxPortal;
  final bool supported;
  final GlobalQuickAddBinding defaultBinding;
  bool _useLinuxPortal = false;
  bool _disposed = false;

  Future<void> initialize() async {
    if (_disposed) return;
    _useLinuxPortal = await _linuxPortal?.isAvailable() ?? false;
  }

  Future<GlobalQuickAddBinding> readBinding() async => _useLinuxPortal
      ? defaultBinding
      : decodeGlobalShortcut(
          await _channel.invokeMethod<Object?>(quickAddGetGlobalShortcutMethod),
        );

  /// Restore the host's registration without re-registering its default key.
  Future<GlobalQuickAddBinding> restore({
    required bool enabled,
    GlobalQuickAddBinding? savedBinding,
  }) async {
    final binding = savedBinding ?? await readBinding();
    if (_disposed) return binding;
    if (_useLinuxPortal) {
      await setEnabled(enabled, binding);
    } else {
      if (!enabled) await setEnabled(false, binding);
      if (savedBinding != null) await register(binding);
      if (enabled && !_disposed) {
        await _channel.invokeMethod<void>(
          quickAddSetGlobalShortcutEnabledMethod,
          true,
        );
      }
    }
    return binding;
  }

  Future<GlobalQuickAddBinding> captureShortcut() async => decodeGlobalShortcut(
    await _channel.invokeMethod<Object?>(quickAddCaptureGlobalShortcutMethod),
  );

  Future<void> cancelCapture() =>
      _channel.invokeMethod<void>(quickAddCancelGlobalShortcutCaptureMethod);

  Future<void> register(GlobalQuickAddBinding binding) async {
    if (_disposed) return;
    if (_useLinuxPortal) {
      await _linuxPortal!.enable(
        preferredTrigger: binding.portalTrigger,
        onActivated: showWindow,
      );
    } else {
      await _channel.invokeMethod<void>(
        quickAddSetGlobalShortcutMethod,
        binding.toJson(),
      );
    }
  }

  Future<void> setEnabled(bool enabled, GlobalQuickAddBinding binding) async {
    if (_disposed) return;
    if (_useLinuxPortal) {
      if (enabled) {
        await register(binding);
      } else {
        await _linuxPortal!.disable();
      }
    } else {
      if (enabled) await register(binding);
      if (!_disposed) {
        await _channel.invokeMethod<void>(
          quickAddSetGlobalShortcutEnabledMethod,
          enabled,
        );
      }
    }
  }

  /// Portal rebinding can release the previous registration before failing.
  Future<void> restoreRegistration(GlobalQuickAddBinding binding) async {
    if (_useLinuxPortal) await register(binding);
  }

  void dispose() {
    _disposed = true;
    _channel.setMethodCallHandler(null);
    unawaited(_linuxPortal?.dispose());
  }

  Future<Object?> handleMethodCall(MethodCall call) => switch (call.method) {
    quickAddCreateTaskMethod => _createTask(call.arguments),
    quickAddGetHintMethod => readHint(),
    quickAddShowWindowMethod => showWindow(),
    _ => throw MissingPluginException(
      'No method ${call.method} on $quickAddChannelName',
    ),
  };

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
      return await createTask(input);
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
