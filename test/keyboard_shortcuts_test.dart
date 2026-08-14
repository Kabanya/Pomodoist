import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/keyboard_shortcuts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  test('Apple defaults expose the six requested command chords', () {
    final bindings = defaultAppShortcutBindings(TargetPlatform.macOS);

    expect(
      {
        for (final entry in bindings.entries)
          entry.key: entry.value.labelFor(TargetPlatform.macOS),
      },
      {
        AppShortcutCommand.toggleSidebar: '⌘B',
        AppShortcutCommand.quickAdd: '⌘N',
        AppShortcutCommand.search: '⌘K',
        AppShortcutCommand.today: '⌘1',
        AppShortcutCommand.inbox: '⌘2',
        AppShortcutCommand.focus: '⌘3',
      },
    );
  });

  test('non-Apple defaults use Control instead of Command', () {
    final bindings = defaultAppShortcutBindings(TargetPlatform.windows);

    expect(
      bindings[AppShortcutCommand.quickAdd]!.labelFor(TargetPlatform.windows),
      'Ctrl+N',
    );
    expect(
      bindings[AppShortcutCommand.focus]!.labelFor(TargetPlatform.windows),
      'Ctrl+3',
    );
  });

  test('binding round-trips and malformed JSON is rejected', () {
    const binding = AppShortcutBinding(
      physicalKeyId: 0x0007000e,
      keyLabel: 'K',
      meta: true,
      shift: true,
    );

    expect(AppShortcutBinding.tryFromJson(binding.toJson()), binding);
    expect(AppShortcutBinding.tryFromJson({'physicalKeyId': 'bad'}), isNull);
    expect(AppShortcutBinding.tryFromJson(null), isNull);
  });

  test('binding requires a non-shift command modifier', () {
    const shiftOnly = AppShortcutBinding(
      physicalKeyId: 0x00070005,
      keyLabel: 'B',
      shift: true,
    );
    const alt = AppShortcutBinding(
      physicalKeyId: 0x00070005,
      keyLabel: 'B',
      alt: true,
    );

    expect(shiftOnly.isValid, isFalse);
    expect(alt.isValid, isTrue);
  });

  test('binding requires an exact modifier set when matching', () {
    const binding = AppShortcutBinding(
      physicalKeyId: 0x00070005,
      keyLabel: 'B',
      meta: true,
    );
    final event = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyB,
      logicalKey: LogicalKeyboardKey.keyB,
      timeStamp: Duration.zero,
    );

    expect(binding.matches(event, _KeyboardState(meta: true)), isTrue);
    expect(
      binding.matches(event, _KeyboardState(meta: true, shift: true)),
      isFalse,
    );
  });

  test(
    'controller rejects duplicates and persists accepted replacements',
    () async {
      final container = ProviderContainer(
        overrides: [
          shortcutTargetPlatformProvider.overrideWithValue(
            TargetPlatform.macOS,
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(keyboardShortcutsLoadedProvider.future);
      final controller = container.read(keyboardShortcutsProvider.notifier);
      final searchBinding = container.read(
        keyboardShortcutsProvider,
      )[AppShortcutCommand.search]!;

      expect(
        await controller.setBinding(AppShortcutCommand.quickAdd, searchBinding),
        AppShortcutCommand.search,
      );

      const replacement = AppShortcutBinding(
        physicalKeyId: 0x0007000d,
        keyLabel: 'J',
        meta: true,
      );
      expect(
        await controller.setBinding(AppShortcutCommand.quickAdd, replacement),
        isNull,
      );

      final stored =
          jsonDecode(
                (await SharedPreferences.getInstance()).getString(
                  keyboardShortcutsPreferenceKey,
                )!,
              )
              as Map<String, dynamic>;
      expect(
        stored[AppShortcutCommand.quickAdd.storageKey],
        replacement.toJson(),
      );
    },
  );

  test(
    'controller loads valid values and falls back per malformed command',
    () async {
      SharedPreferences.setMockInitialValues({
        keyboardShortcutsPreferenceKey: jsonEncode({
          AppShortcutCommand.toggleSidebar.storageKey: {
            'physicalKeyId': PhysicalKeyboardKey.keyJ.usbHidUsage,
            'keyLabel': 'J',
            'meta': true,
            'control': false,
            'alt': false,
            'shift': false,
          },
          AppShortcutCommand.quickAdd.storageKey: {'physicalKeyId': 'bad'},
        }),
      });
      final container = ProviderContainer(
        overrides: [
          shortcutTargetPlatformProvider.overrideWithValue(
            TargetPlatform.macOS,
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(keyboardShortcutsLoadedProvider.future);
      final bindings = container.read(keyboardShortcutsProvider);

      expect(
        bindings[AppShortcutCommand.toggleSidebar]!.labelFor(
          TargetPlatform.macOS,
        ),
        '⌘J',
      );
      expect(
        bindings[AppShortcutCommand.quickAdd]!.labelFor(TargetPlatform.macOS),
        '⌘N',
      );
    },
  );

  test('reset restores every platform default', () async {
    final container = ProviderContainer(
      overrides: [
        shortcutTargetPlatformProvider.overrideWithValue(TargetPlatform.linux),
      ],
    );
    addTearDown(container.dispose);
    await container.read(keyboardShortcutsLoadedProvider.future);
    final controller = container.read(keyboardShortcutsProvider.notifier);
    await controller.setBinding(
      AppShortcutCommand.toggleSidebar,
      const AppShortcutBinding(
        physicalKeyId: 0x0007000d,
        keyLabel: 'J',
        control: true,
      ),
    );

    await controller.resetAll();

    expect(
      container
          .read(keyboardShortcutsProvider)[AppShortcutCommand.toggleSidebar]!
          .labelFor(TargetPlatform.linux),
      'Ctrl+B',
    );
  });

  test(
    'accepted replacements load in a recreated provider container',
    () async {
      final overrides = [
        shortcutTargetPlatformProvider.overrideWithValue(TargetPlatform.macOS),
      ];
      final first = ProviderContainer(overrides: overrides);
      await first.read(keyboardShortcutsLoadedProvider.future);
      await first
          .read(keyboardShortcutsProvider.notifier)
          .setBinding(
            AppShortcutCommand.quickAdd,
            const AppShortcutBinding(
              physicalKeyId: 0x0007000d,
              keyLabel: 'J',
              meta: true,
            ),
          );
      first.dispose();

      final second = ProviderContainer(overrides: overrides);
      addTearDown(second.dispose);
      await second.read(keyboardShortcutsLoadedProvider.future);

      expect(
        second
            .read(keyboardShortcutsProvider)[AppShortcutCommand.quickAdd]!
            .labelFor(TargetPlatform.macOS),
        '⌘J',
      );
    },
  );
}

class _KeyboardState implements HardwareKeyboard {
  const _KeyboardState({this.meta = false, this.shift = false});

  final bool meta;
  final bool shift;

  @override
  bool get isMetaPressed => meta;

  @override
  bool get isShiftPressed => shift;

  @override
  bool get isAltPressed => false;

  @override
  bool get isControlPressed => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
