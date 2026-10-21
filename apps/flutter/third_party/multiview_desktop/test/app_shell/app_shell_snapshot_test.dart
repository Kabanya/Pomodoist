import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/app_shell/app_entry_kind.dart';
import 'package:multiview_desktop/src/app_shell/app_shell_snapshot.dart';

void main() {
  group('AppShellSnapshot', () {
    test('fromMaterialApp copies theme and locale', () {
      final app = MaterialApp(
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.red)),
        darkTheme: ThemeData.dark(),
        themeMode: ThemeMode.dark,
        locale: const Locale('de'),
        supportedLocales: const [Locale('de'), Locale('en')],
        home: const SizedBox(),
      );

      final snapshot = AppShellSnapshot.fromMaterialApp(app);

      expect(snapshot.kind, AppEntryKind.material);
      expect(snapshot.themeMode, ThemeMode.dark);
      expect(snapshot.locale, const Locale('de'));
      expect(snapshot.supportedLocales, const [Locale('de'), Locale('en')]);
    });

    test('fromCupertinoApp copies cupertino theme', () {
      final app = CupertinoApp(
        theme: const CupertinoThemeData(brightness: Brightness.dark),
        locale: const Locale('fr'),
        home: const SizedBox(),
      );

      final snapshot = AppShellSnapshot.fromCupertinoApp(app);

      expect(snapshot.kind, AppEntryKind.cupertino);
      expect(snapshot.cupertinoTheme?.brightness, Brightness.dark);
      expect(snapshot.locale, const Locale('fr'));
    });

    test('fromWidgetsApp copies color and textStyle', () {
      final app = WidgetsApp(
        color: Colors.green,
        textStyle: const TextStyle(fontSize: 14),
        onGenerateRoute: (_) => null,
        home: const SizedBox(),
      );

      final snapshot = AppShellSnapshot.fromWidgetsApp(app);

      expect(snapshot.kind, AppEntryKind.widgets);
      expect(snapshot.color, Colors.green);
      expect(snapshot.textStyle?.fontSize, 14);
    });

    test('resolveWindowBrightness follows themeMode for material', () {
      const light = AppShellSnapshot(kind: AppEntryKind.material, themeMode: ThemeMode.light);
      const dark = AppShellSnapshot(kind: AppEntryKind.material, themeMode: ThemeMode.dark);
      const system = AppShellSnapshot(kind: AppEntryKind.material, themeMode: ThemeMode.system);

      expect(light.resolveWindowBrightness(Brightness.light), Brightness.light);
      expect(dark.resolveWindowBrightness(Brightness.light), Brightness.dark);
      expect(system.resolveWindowBrightness(Brightness.dark), Brightness.dark);
    });

    test('resolveWindowBrightness uses cupertino theme brightness', () {
      const snapshot = AppShellSnapshot(
        kind: AppEntryKind.cupertino,
        cupertinoTheme: CupertinoThemeData(brightness: Brightness.dark),
      );

      expect(snapshot.resolveWindowBrightness(Brightness.light), Brightness.dark);
    });

    test('copyWith replaces only specified fields', () {
      const original = AppShellSnapshot(
        kind: AppEntryKind.material,
        themeMode: ThemeMode.light,
        locale: Locale('en'),
      );
      final copy = original.copyWith(themeMode: ThemeMode.dark);

      expect(copy.themeMode, ThemeMode.dark);
      expect(copy.locale, const Locale('en'));
    });

    test('equality compares all fields', () {
      const a = AppShellSnapshot(kind: AppEntryKind.material, themeMode: ThemeMode.light);
      const b = AppShellSnapshot(kind: AppEntryKind.material, themeMode: ThemeMode.light);
      const c = AppShellSnapshot(kind: AppEntryKind.material, themeMode: ThemeMode.dark);

      expect(a, b);
      expect(a == c, isFalse);
    });
  });
}
