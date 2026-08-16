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

  test('Apple defaults follow the desktop sidebar order', () {
    final bindings = defaultAppShortcutBindings(TargetPlatform.macOS);

    expect(
      bindings.values
          .map((binding) => binding.labelFor(TargetPlatform.macOS))
          .toList(),
      const [
        '⌘B',
        '⌘N',
        '⌘1',
        '⌘2',
        '⌘3',
        '⌘4',
        '⌘5',
        '⌘6',
        '⌘7',
        '⌘8',
        '⌘9',
        '⌘0',
        '⇧⌘1',
      ],
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
      'Ctrl+5',
    );
    expect(
      bindings.values.last.labelFor(TargetPlatform.windows),
      'Ctrl+Shift+1',
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

  test(
    'legacy defaults migrate and persist the complete numbered map',
    () async {
      SharedPreferences.setMockInitialValues({
        keyboardShortcutsPreferenceKey: jsonEncode({
          AppShortcutCommand.toggleSidebar.storageKey: _storedMacBinding(
            PhysicalKeyboardKey.keyB,
            'B',
          ),
          AppShortcutCommand.quickAdd.storageKey: _storedMacBinding(
            PhysicalKeyboardKey.keyN,
            'N',
          ),
          AppShortcutCommand.search.storageKey: _storedMacBinding(
            PhysicalKeyboardKey.keyK,
            'K',
          ),
          AppShortcutCommand.today.storageKey: _storedMacBinding(
            PhysicalKeyboardKey.digit1,
            '1',
          ),
          AppShortcutCommand.inbox.storageKey: _storedMacBinding(
            PhysicalKeyboardKey.digit2,
            '2',
          ),
          AppShortcutCommand.focus.storageKey: _storedMacBinding(
            PhysicalKeyboardKey.digit3,
            '3',
          ),
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

      expect(
        container
            .read(keyboardShortcutsProvider)
            .values
            .map((binding) => binding.labelFor(TargetPlatform.macOS))
            .toList(),
        const [
          '⌘B',
          '⌘N',
          '⌘1',
          '⌘2',
          '⌘3',
          '⌘4',
          '⌘5',
          '⌘6',
          '⌘7',
          '⌘8',
          '⌘9',
          '⌘0',
          '⇧⌘1',
        ],
      );
      final stored =
          jsonDecode(
                (await SharedPreferences.getInstance()).getString(
                  keyboardShortcutsPreferenceKey,
                )!,
              )
              as Map<String, dynamic>;
      expect(stored.keys.toSet(), {
        for (final command in AppShortcutCommand.values) command.storageKey,
      });
    },
  );

  test('legacy migration preserves non-conflicting custom shortcuts', () async {
    SharedPreferences.setMockInitialValues({
      keyboardShortcutsPreferenceKey: jsonEncode({
        AppShortcutCommand.toggleSidebar.storageKey: _storedMacBinding(
          PhysicalKeyboardKey.digit4,
          '4',
        ),
        AppShortcutCommand.quickAdd.storageKey: _storedMacBinding(
          PhysicalKeyboardKey.keyJ,
          'J',
        ),
        AppShortcutCommand.search.storageKey: _storedMacBinding(
          PhysicalKeyboardKey.keyK,
          'K',
        ),
        AppShortcutCommand.today.storageKey: _storedMacBinding(
          PhysicalKeyboardKey.digit1,
          '1',
        ),
        AppShortcutCommand.inbox.storageKey: _storedMacBinding(
          PhysicalKeyboardKey.digit2,
          '2',
        ),
        AppShortcutCommand.focus.storageKey: _storedMacBinding(
          PhysicalKeyboardKey.digit3,
          '3',
        ),
      }),
    });
    final container = ProviderContainer(
      overrides: [
        shortcutTargetPlatformProvider.overrideWithValue(TargetPlatform.macOS),
      ],
    );
    addTearDown(container.dispose);

    await container.read(keyboardShortcutsLoadedProvider.future);
    final bindings = container.read(keyboardShortcutsProvider);

    expect(
      bindings[AppShortcutCommand.quickAdd]!.labelFor(TargetPlatform.macOS),
      '⌘J',
    );
    expect(
      bindings[AppShortcutCommand.toggleSidebar]!.labelFor(
        TargetPlatform.macOS,
      ),
      '⌘B',
    );
    expect(
      bindings[AppShortcutCommand.upcoming]!.labelFor(TargetPlatform.macOS),
      '⌘4',
    );
  });

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

Map<String, Object> _storedMacBinding(PhysicalKeyboardKey key, String label) =>
    {
      'physicalKeyId': key.usbHidUsage,
      'keyLabel': label,
      'meta': true,
      'control': false,
      'alt': false,
      'shift': false,
    };
