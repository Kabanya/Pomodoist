import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/keyboard_shortcuts.dart';
import 'package:pomodoist/ui/core/localization/app_localizations_en.dart';
import 'package:pomodoist/ui/core/localization/app_localizations_ru.dart';
import 'package:pomodoist/ui/core/view_models/shell_view_model.dart';
import 'package:pomodoist/ui/core/widgets/shortcut_hints.dart';

void main() {
  test('hints leave touch platforms disabled', () {
    for (final platform in TargetPlatform.values) {
      expect(
        shortcutHintsSupported(platform),
        ![
          TargetPlatform.android,
          TargetPlatform.iOS,
          TargetPlatform.fuchsia,
        ].contains(platform),
      );
    }
  });

  test(
    'shell hints use actual platform bindings and localized command names',
    () {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        final bindings = defaultAppShortcutBindings(platform);
        final state = ShellKeyboardState(
          platform: platform,
          shortcuts: bindings,
        );
        final l10n = AppLocalizationsEn();
        final hints = shellShortcutHints(l10n, state, focusLocation: false);
        expect(hints.map((hint) => hint.keys), [
          for (final command in [
            AppShortcutCommand.quickAdd,
            AppShortcutCommand.toggleSidebar,
            AppShortcutCommand.search,
          ])
            bindings[command]!.labelFor(platform),
          '${bindings[AppShortcutCommand.focus]!.labelFor(platform)} / ${bindings[AppShortcutCommand.focusAlternate]!.labelFor(platform)}',
        ]);
        expect(hints[0].label, l10n.addTask);
        expect(hints[2].navigation, isTrue);
        expect(hints.every((hint) => !hint.release), isTrue);
        expect(
          hints.first.keys,
          platform == TargetPlatform.macOS ? '⌘N' : 'Ctrl+N',
        );
      }
    },
  );

  test(
    'remaps retain every modifier, missing commands are omitted, Focus is contextual',
    () {
      final custom = ShellKeyboardState(
        platform: TargetPlatform.macOS,
        shortcuts: {
          AppShortcutCommand.quickAdd: const AppShortcutBinding(
            physicalKeyId: 0x7000e,
            keyLabel: 'K',
            meta: true,
            shift: true,
            alt: true,
          ),
          AppShortcutCommand.focus: defaultAppShortcutBindings(
            TargetPlatform.macOS,
          )[AppShortcutCommand.focus]!,
        },
      );
      final l10n = AppLocalizationsRu();
      final main = shellShortcutHints(l10n, custom, focusLocation: false);
      final focus = shellShortcutHints(l10n, custom, focusLocation: true);
      expect(main, hasLength(2));
      expect(main.first.keys, '⌥⇧⌘K');
      expect(focus.last.label, l10n.shortcutHintsSwitchFocusView);
      expect(main.last.label, isNot(focus.last.label));
      expect(commandHint(l10n, custom, AppShortcutCommand.calendar), isNull);
    },
  );
  test(
    'Focus includes its remapped alternate and falls back when primary is absent',
    () {
      final l10n = AppLocalizationsEn();
      const alternate = AppShortcutBinding(
        physicalKeyId: 0x7000e,
        keyLabel: 'K',
        meta: true,
        shift: true,
      );
      final bindings = {
        AppShortcutCommand.focus: defaultAppShortcutBindings(
          TargetPlatform.macOS,
        )[AppShortcutCommand.focus]!,
        AppShortcutCommand.focusAlternate: alternate,
      };
      ShellKeyboardState state() => ShellKeyboardState(
        platform: TargetPlatform.macOS,
        shortcuts: bindings,
      );
      expect(
        commandHint(l10n, state(), AppShortcutCommand.focus)!.keys,
        '⌘5 / ⇧⌘K',
      );
      bindings.remove(AppShortcutCommand.focus);
      expect(commandHint(l10n, state(), AppShortcutCommand.focus)!.keys, '⇧⌘K');
      bindings.clear();
      expect(commandHint(l10n, state(), AppShortcutCommand.focus), isNull);
    },
  );
}
