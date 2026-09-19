// ignore_for_file: deprecated_member_use

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/keyboard_shortcuts.dart';
import 'package:pomodoist/config/platform/platform_quick_add.dart';

typedef ShortcutBinding = AppShortcutBinding;
typedef GlobalShortcutBinding = GlobalQuickAddBinding;

ShortcutBinding shortcutBindingFromEvent(
  KeyEvent event,
  HardwareKeyboard keyboard,
) => AppShortcutBinding.fromEvent(event, keyboard);

ShortcutBinding shortcutBindingFromRawEvent(RawKeyEvent event) =>
    AppShortcutBinding.fromRawEvent(event);

final class KeyboardShortcutsState {
  const KeyboardShortcutsState({
    required this.platform,
    required this.bindings,
    required this.global,
    required this.supportsGlobal,
  });

  final TargetPlatform platform;
  final Map<AppShortcutCommand, ShortcutBinding> bindings;
  final GlobalQuickAddState global;
  final bool supportsGlobal;
}

final keyboardShortcutsViewModelProvider =
    NotifierProvider.autoDispose<
      KeyboardShortcutsViewModel,
      KeyboardShortcutsState
    >(KeyboardShortcutsViewModel.new);

class KeyboardShortcutsViewModel extends Notifier<KeyboardShortcutsState> {
  PlatformQuickAddController? _global;

  @override
  KeyboardShortcutsState build() {
    final platform = ref.watch(shortcutTargetPlatformProvider);
    final bindings = ref.watch(keyboardShortcutsProvider);
    ref.watch(keyboardShortcutsLoadedProvider);
    final supportsGlobal =
        !kIsWeb &&
        const {
          TargetPlatform.macOS,
          TargetPlatform.windows,
          TargetPlatform.linux,
        }.contains(platform);
    final controller = supportsGlobal
        ? ref.watch(platformQuickAddControllerProvider)
        : null;
    if (!identical(_global, controller)) {
      _global?.removeListener(_refreshGlobalState);
      _global = controller;
      controller?.addListener(_refreshGlobalState);
    }
    ref.onDispose(() => _global?.removeListener(_refreshGlobalState));
    return KeyboardShortcutsState(
      platform: platform,
      bindings: bindings,
      global:
          controller?.state ??
          GlobalQuickAddState(
            enabled: false,
            binding: GlobalQuickAddBinding.defaultFor(platform),
          ),
      supportsGlobal: supportsGlobal,
    );
  }

  Future<void> waitUntilReady() async {
    await _global?.ready;
    _refreshGlobalState();
  }

  void _refreshGlobalState() {
    final controller = _global;
    if (!ref.mounted || controller == null) return;
    state = KeyboardShortcutsState(
      platform: state.platform,
      bindings: state.bindings,
      global: controller.state,
      supportsGlobal: state.supportsGlobal,
    );
  }

  bool conflictsWithZoom(ShortcutBinding binding) =>
      isAppZoomBinding(binding, state.platform);

  bool conflictsWithApp(GlobalShortcutBinding candidate) => state
      .bindings
      .values
      .any((binding) => binding.displaySignature == candidate.displaySignature);

  bool conflictsWithGlobal(ShortcutBinding candidate) =>
      state.global.binding.displaySignature == candidate.displaySignature;

  Future<AppShortcutCommand?> setBinding(
    AppShortcutCommand command,
    ShortcutBinding binding,
  ) =>
      ref.read(keyboardShortcutsProvider.notifier).setBinding(command, binding);

  Future<void> setGlobalEnabled(bool enabled) async {
    await _global!.setGlobalQuickAddEnabled(enabled);
    _refreshGlobalState();
  }

  Future<void> setGlobalShortcut(GlobalShortcutBinding binding) async {
    await _global!.setGlobalShortcut(binding);
    _refreshGlobalState();
  }

  Future<GlobalShortcutBinding> captureGlobalShortcut() =>
      _global!.captureGlobalShortcut();

  Future<void> cancelGlobalShortcutCapture() =>
      _global!.cancelGlobalShortcutCapture();

  Future<void> resetAll() async {
    await ref.read(keyboardShortcutsProvider.notifier).resetAll();
    if (state.supportsGlobal) {
      await _global!.setGlobalShortcut(
        GlobalQuickAddBinding.defaultFor(state.platform),
      );
      _refreshGlobalState();
    }
  }

  GlobalShortcutBinding globalFromShortcut(ShortcutBinding binding) =>
      GlobalQuickAddBinding(
        keyCode: binding.physicalKeyId,
        keyLabel: binding.keyLabel,
        meta: binding.meta,
        control: binding.control,
        alt: binding.alt,
        shift: binding.shift,
      );
}
