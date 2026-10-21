import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/app_shell/app_entry_kind.dart';
import 'package:multiview_desktop/src/app_shell/app_shell_patch.dart';
import 'package:multiview_desktop/src/app_shell/app_shell_registry.dart';
import 'package:multiview_desktop/src/app_shell/app_shell_snapshot.dart';
import 'package:multiview_desktop/src/app_shell/view_shell_overrides.dart';
import 'package:multiview_desktop/src/view_shell_brightness_sync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveViewShellBrightness', () {
    late AppShellRegistry registry;

    setUp(() {
      registry = AppShellRegistry();
      registry.replace(
        const AppShellSnapshot(
          kind: AppEntryKind.material,
          themeMode: ThemeMode.dark,
        ),
      );
    });

    tearDown(() => registry.dispose());

    test('returns brightness from global shell', () {
      expect(resolveViewShellBrightness(registry, null), Brightness.dark);
    });

    test('per view appearance override changes resolved brightness', () {
      const overrides = ViewShellOverrides(
        appearance: AppShellPatch(themeMode: ThemeMode.light),
      );

      expect(resolveViewShellBrightness(registry, overrides), Brightness.light);
    });

    test('returns null when no shell snapshot exists', () {
      registry.replace(null);
      expect(resolveViewShellBrightness(registry, null), isNull);
    });
  });
}
