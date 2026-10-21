import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/app_shell/app_entry_kind.dart';
import 'package:multiview_desktop/src/app_shell/app_shell_controller.dart';
import 'package:multiview_desktop/src/app_shell/app_shell_patch.dart';
import 'package:multiview_desktop/src/app_shell/app_shell_registry.dart';
import 'package:multiview_desktop/src/app_shell/app_shell_snapshot.dart';

void main() {
  group('AppShellRegistry', () {
    late AppShellRegistry registry;
    late AppShellController controller;
    var notifyCount = 0;

    setUp(() {
      registry = AppShellRegistry();
      controller = AppShellController(registry);
      notifyCount = 0;
      registry.addListener(() => notifyCount++);
    });

    tearDown(() => registry.dispose());

    test('replace stores snapshot and notifies listeners', () {
      const snapshot = AppShellSnapshot(kind: AppEntryKind.material, themeMode: ThemeMode.dark);
      registry.replace(snapshot);

      expect(registry.snapshot, snapshot);
      expect(notifyCount, 1);
    });

    test('replace skips notify when snapshot unchanged', () {
      const snapshot = AppShellSnapshot(kind: AppEntryKind.material);
      registry.replace(snapshot);
      registry.replace(snapshot);

      expect(notifyCount, 1);
    });

    test('patch merges into current snapshot', () {
      controller.apply(const AppShellSnapshot(kind: AppEntryKind.material, themeMode: ThemeMode.light));
      controller.patch(const AppShellPatch(themeMode: ThemeMode.dark));

      expect(registry.snapshot?.themeMode, ThemeMode.dark);
      expect(notifyCount, 2);
    });

    test('applyFromMaterialApp copies from MaterialApp', () {
      final app = MaterialApp(
        themeMode: ThemeMode.dark,
        home: const SizedBox(),
      );
      controller.applyFromMaterialApp(app);

      expect(registry.snapshot?.kind, AppEntryKind.material);
      expect(registry.snapshot?.themeMode, ThemeMode.dark);
    });
  });
}
