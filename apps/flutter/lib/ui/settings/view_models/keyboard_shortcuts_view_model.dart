export 'global_shortcut_labels.dart';
// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/keyboard_shortcuts.dart';
import 'package:pomodoist/config/platform/platform_quick_add.dart';
import 'package:pomodoist/data/repositories/platform/global_quick_add_repository.dart';

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
  GlobalQuickAddRepository? _global;

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
    final global = supportsGlobal
        ? ref.watch(globalQuickAddRepositoryProvider)
        : null;
    _global = global;
    final subscription = global?.watchState().listen((value) {
      if (ref.mounted) _applyGlobal(value);
    });
    ref.onDispose(() => unawaited(subscription?.cancel()));
    return KeyboardShortcutsState(
      platform: platform,
      bindings: bindings,
      global:
          global?.state ??
          GlobalQuickAddState(
            enabled: false,
            binding: GlobalQuickAddBinding.defaultFor(
              isMacOS: platform == TargetPlatform.macOS,
            ),
          ),
      supportsGlobal: supportsGlobal,
    );
  }

  Future<void> waitUntilReady() async {
    await _global?.ready;
    _refreshGlobalState();
  }

  void _applyGlobal(GlobalQuickAddState value) {
    state = KeyboardShortcutsState(
      platform: state.platform,
      bindings: state.bindings,
      global: value,
      supportsGlobal: state.supportsGlobal,
    );
  }

  void _refreshGlobalState() {
    final global = _global;
    if (!ref.mounted || global == null) return;
    _applyGlobal(global.state);
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
    await _global!.setEnabled(enabled);
    _refreshGlobalState();
  }

  Future<void> setGlobalShortcut(GlobalShortcutBinding binding) async {
    await _global!.setShortcut(binding);
    _refreshGlobalState();
  }

  Future<GlobalShortcutBinding> captureGlobalShortcut() =>
      _global!.captureShortcut();

  Future<void> cancelGlobalShortcutCapture() => _global!.cancelCapture();

  Future<void> resetAll() async {
    await ref.read(keyboardShortcutsProvider.notifier).resetAll();
    if (state.supportsGlobal) {
      await _global!.setShortcut(
        GlobalQuickAddBinding.defaultFor(
          isMacOS: state.platform == TargetPlatform.macOS,
        ),
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
