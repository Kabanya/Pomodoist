import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/app_shell/app_entry_kind.dart';
import 'package:multiview_desktop/src/app_shell/app_shell_patch.dart';
import 'package:multiview_desktop/src/app_shell/app_shell_snapshot.dart';

void main() {
  group('AppShellPatch', () {
    test('applyTo creates default snapshot when current is null', () {
      const patch = AppShellPatch(themeMode: ThemeMode.dark, locale: Locale('de'));
      final result = patch.applyTo(null);

      expect(result.kind, AppEntryKind.material);
      expect(result.themeMode, ThemeMode.dark);
      expect(result.locale, const Locale('de'));
      expect(result.supportedLocales, const [Locale('en', 'US')]);
    });

    test('applyTo merges into existing snapshot', () {
      const base = AppShellSnapshot(
        kind: AppEntryKind.material,
        themeMode: ThemeMode.light,
        locale: Locale('en'),
      );
      const patch = AppShellPatch(themeMode: ThemeMode.dark);
      final result = patch.applyTo(base);

      expect(result.themeMode, ThemeMode.dark);
      expect(result.locale, const Locale('en'));
    });

    test('merge prefers delta fields', () {
      const base = AppShellPatch(themeMode: ThemeMode.light, locale: Locale('en'));
      const delta = AppShellPatch(themeMode: ThemeMode.dark);
      final merged = AppShellPatch.merge(base, delta);

      expect(merged.themeMode, ThemeMode.dark);
      expect(merged.locale, const Locale('en'));
    });

    test('merge returns delta when base is null', () {
      const delta = AppShellPatch(locale: Locale('fr'));
      expect(AppShellPatch.merge(null, delta).locale, const Locale('fr'));
    });

    test('composeAppearance applies local patch on global snapshot', () {
      const global = AppShellSnapshot(
        kind: AppEntryKind.material,
        themeMode: ThemeMode.light,
        locale: Locale('en'),
      );
      const local = AppShellPatch(locale: Locale('ja'));
      final composed = AppShellPatch.composeAppearance(global, local);

      expect(composed?.themeMode, ThemeMode.light);
      expect(composed?.locale, const Locale('ja'));
    });

    test('composeAppearance returns global when local is null', () {
      const global = AppShellSnapshot(kind: AppEntryKind.material, themeMode: ThemeMode.dark);
      expect(AppShellPatch.composeAppearance(global, null), global);
    });
  });
}
