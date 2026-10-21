import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/app_shell/app_entry_kind.dart';
import 'package:multiview_desktop/src/app_shell/app_shell_patch.dart';
import 'package:multiview_desktop/src/app_shell/app_shell_registry.dart';
import 'package:multiview_desktop/src/app_shell/app_shell_snapshot.dart';
import 'package:multiview_desktop/src/app_shell/view_shell_overrides.dart';
import 'package:multiview_desktop/src/shared_entry_app.dart';

void main() {
  group('SharedEntryApp', () {
    late AppShellRegistry registry;
    late ValueNotifier<ViewShellOverrides?> overrides;

    setUp(() {
      registry = AppShellRegistry();
      overrides = ValueNotifier<ViewShellOverrides?>(null);
      registry.replace(
        const AppShellSnapshot(
          kind: AppEntryKind.material,
          themeMode: ThemeMode.dark,
          locale: Locale('de'),
        ),
      );
    });

    tearDown(() {
      registry.dispose();
      overrides.dispose();
    });

    testWidgets('wraps child in MaterialApp with global theme and locale', (tester) async {
      await tester.pumpWidget(
        SharedEntryApp(
          registry: registry,
          viewShellOverrides: overrides,
          child: const Text('content'),
        ),
      );
      await tester.pump();

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.themeMode, ThemeMode.dark);
      expect(materialApp.locale, const Locale('de'));
      expect(find.text('content'), findsOneWidget);
    });

    testWidgets('applies per-view appearance overrides on top of global shell', (tester) async {
      overrides.value = ViewShellOverrides.appearance(const AppShellPatch(locale: Locale('ja')));

      await tester.pumpWidget(
        SharedEntryApp(
          registry: registry,
          viewShellOverrides: overrides,
          child: const Text('content'),
        ),
      );
      await tester.pump();

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.locale, const Locale('ja'));
      expect(materialApp.themeMode, ThemeMode.dark);
    });

    testWidgets('rebuilds when registry snapshot changes', (tester) async {
      await tester.pumpWidget(
        SharedEntryApp(
          registry: registry,
          viewShellOverrides: overrides,
          child: const Text('content'),
        ),
      );
      await tester.pump();

      registry.replace(
        const AppShellSnapshot(
          kind: AppEntryKind.material,
          themeMode: ThemeMode.light,
          locale: Locale('fr'),
        ),
      );
      await tester.pump();

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.themeMode, ThemeMode.light);
      expect(materialApp.locale, const Locale('fr'));
    });
  });
}
