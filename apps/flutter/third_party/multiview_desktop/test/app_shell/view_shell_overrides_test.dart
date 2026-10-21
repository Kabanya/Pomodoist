import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/app_shell/app_shell_patch.dart';
import 'package:multiview_desktop/src/app_shell/view_shell_overrides.dart';

void main() {
  group('ViewShellOverrides', () {
    test('usesRouter is true when routerDelegate is set', () {
      final overrides = ViewShellOverrides(routerDelegate: _FakeRouterDelegate());
      expect(overrides.usesRouter, isTrue);
    });

    test('usesRouter is false for appearance-only overrides', () {
      const overrides = ViewShellOverrides(appearance: AppShellPatch(locale: Locale('de')));
      expect(overrides.usesRouter, isFalse);
    });

    test('merge combines appearance patches', () {
      const base = ViewShellOverrides(
        appearance: AppShellPatch(themeMode: ThemeMode.light, locale: Locale('en')),
        title: 'Base',
      );
      const delta = ViewShellOverrides(
        appearance: AppShellPatch(themeMode: ThemeMode.dark),
        home: SizedBox(),
      );

      final merged = ViewShellOverrides.merge(base, delta);

      expect(merged.appearance?.themeMode, ThemeMode.dark);
      expect(merged.appearance?.locale, const Locale('en'));
      expect(merged.title, 'Base');
      expect(merged.home, isNotNull);
    });

    test('merge returns delta when base is null', () {
      const delta = ViewShellOverrides(title: 'Only');
      expect(ViewShellOverrides.merge(null, delta).title, 'Only');
    });

    test('appearance factory sets appearance patch', () {
      final overrides = ViewShellOverrides.appearance(const AppShellPatch(locale: Locale('ja')));
      expect(overrides.appearance?.locale, const Locale('ja'));
    });
  });
}

class _FakeRouterDelegate extends RouterDelegate<Object> with ChangeNotifier {
  @override
  Object? get currentConfiguration => null;

  @override
  Future<bool> popRoute() async => false;

  @override
  Future<void> setNewRoutePath(Object configuration) async {}

  @override
  Widget build(BuildContext context) => const SizedBox();
}
