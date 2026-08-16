// ignore_for_file: deprecated_member_use

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const keyboardShortcutsPreferenceKey = 'keyboard.shortcuts.v1';

enum AppShortcutCommand {
  toggleSidebar,
  quickAdd,
  browse,
  search,
  today,
  upcoming,
  focus,
  inbox,
  priorityMatrix,
  timeline,
  kanban,
  reports,
  settings;

  String get storageKey => name;
}

const _legacyAppShortcutCommands = [
  AppShortcutCommand.toggleSidebar,
  AppShortcutCommand.quickAdd,
  AppShortcutCommand.search,
  AppShortcutCommand.today,
  AppShortcutCommand.inbox,
  AppShortcutCommand.focus,
];

const _newAppShortcutCommands = [
  AppShortcutCommand.browse,
  AppShortcutCommand.upcoming,
  AppShortcutCommand.priorityMatrix,
  AppShortcutCommand.timeline,
  AppShortcutCommand.kanban,
  AppShortcutCommand.reports,
  AppShortcutCommand.settings,
];

@immutable
class AppShortcutBinding {
  const AppShortcutBinding({
    required this.physicalKeyId,
    required this.keyLabel,
    this.meta = false,
    this.control = false,
    this.alt = false,
    this.shift = false,
  });

  factory AppShortcutBinding.fromEvent(
    KeyEvent event,
    HardwareKeyboard keyboard,
  ) {
    final logicalLabel = event.logicalKey.keyLabel.trim();
    return AppShortcutBinding(
      physicalKeyId: event.physicalKey.usbHidUsage,
      keyLabel: logicalLabel.isEmpty
          ? event.physicalKey.debugName ?? 'Key'
          : logicalLabel.toUpperCase(),
      meta: keyboard.isMetaPressed,
      control: keyboard.isControlPressed,
      alt: keyboard.isAltPressed,
      shift: keyboard.isShiftPressed,
    );
  }

  factory AppShortcutBinding.fromRawEvent(RawKeyEvent event) {
    final logicalLabel = event.logicalKey.keyLabel.trim();
    return AppShortcutBinding(
      physicalKeyId: event.physicalKey.usbHidUsage,
      keyLabel: logicalLabel.isEmpty
          ? event.physicalKey.debugName ?? 'Key'
          : logicalLabel.toUpperCase(),
      meta: event.data.isModifierPressed(ModifierKey.metaModifier),
      control: event.data.isModifierPressed(ModifierKey.controlModifier),
      alt: event.data.isModifierPressed(ModifierKey.altModifier),
      shift: event.data.isModifierPressed(ModifierKey.shiftModifier),
    );
  }

  final int physicalKeyId;
  final String keyLabel;
  final bool meta;
  final bool control;
  final bool alt;
  final bool shift;

  bool get isValid =>
      physicalKeyId > 0 &&
      keyLabel.trim().isNotEmpty &&
      (meta || control || alt);

  String get signature =>
      '$physicalKeyId:${meta ? 1 : 0}:${control ? 1 : 0}:${alt ? 1 : 0}:${shift ? 1 : 0}';

  String get displaySignature =>
      '${keyLabel.trim().toUpperCase()}:${meta ? 1 : 0}:${control ? 1 : 0}:${alt ? 1 : 0}:${shift ? 1 : 0}';

  bool matches(KeyEvent event, HardwareKeyboard keyboard) {
    return physicalKeyId == event.physicalKey.usbHidUsage &&
        meta == keyboard.isMetaPressed &&
        control == keyboard.isControlPressed &&
        alt == keyboard.isAltPressed &&
        shift == keyboard.isShiftPressed;
  }

  bool matchesRawEvent(RawKeyEvent event) {
    return physicalKeyId == event.physicalKey.usbHidUsage &&
        meta == event.data.isModifierPressed(ModifierKey.metaModifier) &&
        control == event.data.isModifierPressed(ModifierKey.controlModifier) &&
        alt == event.data.isModifierPressed(ModifierKey.altModifier) &&
        shift == event.data.isModifierPressed(ModifierKey.shiftModifier);
  }

  String labelFor(TargetPlatform platform) {
    if (_isApplePlatform(platform)) {
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

  Map<String, Object> toJson() => {
    'physicalKeyId': physicalKeyId,
    'keyLabel': keyLabel,
    'meta': meta,
    'control': control,
    'alt': alt,
    'shift': shift,
  };

  static AppShortcutBinding? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final physicalKeyId = value['physicalKeyId'];
    final keyLabel = value['keyLabel'];
    final meta = value['meta'];
    final control = value['control'];
    final alt = value['alt'];
    final shift = value['shift'];
    if (physicalKeyId is! int ||
        keyLabel is! String ||
        meta is! bool ||
        control is! bool ||
        alt is! bool ||
        shift is! bool) {
      return null;
    }
    final binding = AppShortcutBinding(
      physicalKeyId: physicalKeyId,
      keyLabel: keyLabel,
      meta: meta,
      control: control,
      alt: alt,
      shift: shift,
    );
    return binding.isValid ? binding : null;
  }

  @override
  bool operator ==(Object other) =>
      other is AppShortcutBinding &&
      physicalKeyId == other.physicalKeyId &&
      keyLabel == other.keyLabel &&
      meta == other.meta &&
      control == other.control &&
      alt == other.alt &&
      shift == other.shift;

  @override
  int get hashCode =>
      Object.hash(physicalKeyId, keyLabel, meta, control, alt, shift);
}

Map<AppShortcutCommand, AppShortcutBinding> defaultAppShortcutBindings(
  TargetPlatform platform,
) {
  AppShortcutBinding binding(
    PhysicalKeyboardKey key,
    String label, {
    bool shift = false,
  }) => _platformBinding(platform, key, label, shift: shift);

  return {
    AppShortcutCommand.toggleSidebar: binding(PhysicalKeyboardKey.keyB, 'B'),
    AppShortcutCommand.quickAdd: binding(PhysicalKeyboardKey.keyN, 'N'),
    AppShortcutCommand.browse: binding(PhysicalKeyboardKey.digit1, '1'),
    AppShortcutCommand.search: binding(PhysicalKeyboardKey.digit2, '2'),
    AppShortcutCommand.today: binding(PhysicalKeyboardKey.digit3, '3'),
    AppShortcutCommand.upcoming: binding(PhysicalKeyboardKey.digit4, '4'),
    AppShortcutCommand.focus: binding(PhysicalKeyboardKey.digit5, '5'),
    AppShortcutCommand.inbox: binding(PhysicalKeyboardKey.digit6, '6'),
    AppShortcutCommand.priorityMatrix: binding(PhysicalKeyboardKey.digit7, '7'),
    AppShortcutCommand.timeline: binding(PhysicalKeyboardKey.digit8, '8'),
    AppShortcutCommand.kanban: binding(PhysicalKeyboardKey.digit9, '9'),
    AppShortcutCommand.reports: binding(PhysicalKeyboardKey.digit0, '0'),
    AppShortcutCommand.settings: binding(
      PhysicalKeyboardKey.digit1,
      '1',
      shift: true,
    ),
  };
}

Map<AppShortcutCommand, AppShortcutBinding> _legacyDefaultBindings(
  TargetPlatform platform,
) => {
  AppShortcutCommand.toggleSidebar: _platformBinding(
    platform,
    PhysicalKeyboardKey.keyB,
    'B',
  ),
  AppShortcutCommand.quickAdd: _platformBinding(
    platform,
    PhysicalKeyboardKey.keyN,
    'N',
  ),
  AppShortcutCommand.search: _platformBinding(
    platform,
    PhysicalKeyboardKey.keyK,
    'K',
  ),
  AppShortcutCommand.today: _platformBinding(
    platform,
    PhysicalKeyboardKey.digit1,
    '1',
  ),
  AppShortcutCommand.inbox: _platformBinding(
    platform,
    PhysicalKeyboardKey.digit2,
    '2',
  ),
  AppShortcutCommand.focus: _platformBinding(
    platform,
    PhysicalKeyboardKey.digit3,
    '3',
  ),
};

AppShortcutBinding _platformBinding(
  TargetPlatform platform,
  PhysicalKeyboardKey key,
  String label, {
  bool shift = false,
}) {
  final apple = _isApplePlatform(platform);
  return AppShortcutBinding(
    physicalKeyId: key.usbHidUsage,
    keyLabel: label,
    meta: apple,
    control: !apple,
    shift: shift,
  );
}

bool _isApplePlatform(TargetPlatform platform) =>
    platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;

final shortcutTargetPlatformProvider = Provider<TargetPlatform>(
  (ref) => defaultTargetPlatform,
);

final keyboardShortcutsProvider =
    NotifierProvider<
      KeyboardShortcutsController,
      Map<AppShortcutCommand, AppShortcutBinding>
    >(KeyboardShortcutsController.new);

final keyboardShortcutsLoadedProvider = FutureProvider<void>((ref) {
  return ref.read(keyboardShortcutsProvider.notifier).load();
});

class KeyboardShortcutsController
    extends Notifier<Map<AppShortcutCommand, AppShortcutBinding>> {
  Future<void>? _loadFuture;

  TargetPlatform get _platform => ref.read(shortcutTargetPlatformProvider);

  @override
  Map<AppShortcutCommand, AppShortcutBinding> build() =>
      Map.unmodifiable(defaultAppShortcutBindings(_platform));

  Future<void> load() => _loadFuture ??= _load();

  Future<AppShortcutCommand?> setBinding(
    AppShortcutCommand command,
    AppShortcutBinding binding,
  ) async {
    if (!binding.isValid) {
      throw ArgumentError.value(binding, 'binding', 'Invalid shortcut');
    }
    for (final entry in state.entries) {
      if (entry.key != command && entry.value.signature == binding.signature) {
        return entry.key;
      }
    }
    state = Map.unmodifiable({...state, command: binding});
    await _persist();
    return null;
  }

  Future<void> resetAll() async {
    state = Map.unmodifiable(defaultAppShortcutBindings(_platform));
    await _persist();
  }

  Future<void> _load() async {
    final defaults = defaultAppShortcutBindings(_platform);
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(keyboardShortcutsPreferenceKey);
    if (raw == null) return;

    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (decoded is! Map) return;
    final decodedMap = decoded;

    if (_newAppShortcutCommands.every(
      (command) => !decodedMap.containsKey(command.storageKey),
    )) {
      await _loadLegacy(decodedMap, defaults);
      return;
    }

    final loaded = <AppShortcutCommand, AppShortcutBinding>{};
    for (final command in AppShortcutCommand.values) {
      loaded[command] =
          AppShortcutBinding.tryFromJson(decodedMap[command.storageKey]) ??
          defaults[command]!;
    }
    if (loaded.values.map((value) => value.signature).toSet().length !=
        AppShortcutCommand.values.length) {
      return;
    }
    if (ref.mounted) state = Map.unmodifiable(loaded);
  }

  Future<void> _loadLegacy(
    Map decoded,
    Map<AppShortcutCommand, AppShortcutBinding> defaults,
  ) async {
    final loaded = {...defaults};
    final legacyDefaults = _legacyDefaultBindings(_platform);
    for (final command in _legacyAppShortcutCommands) {
      final candidate = AppShortcutBinding.tryFromJson(
        decoded[command.storageKey],
      );
      if (candidate == null ||
          candidate.signature == legacyDefaults[command]!.signature) {
        continue;
      }
      final conflictsWithNumberedLayout = loaded.entries.any(
        (entry) =>
            entry.key != command &&
            entry.value.signature == candidate.signature,
      );
      if (!conflictsWithNumberedLayout) loaded[command] = candidate;
    }
    if (!ref.mounted) return;
    state = Map.unmodifiable(loaded);
    await _persist();
  }

  Future<void> _persist() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      keyboardShortcutsPreferenceKey,
      jsonEncode({
        for (final entry in state.entries)
          entry.key.storageKey: entry.value.toJson(),
      }),
    );
  }
}
