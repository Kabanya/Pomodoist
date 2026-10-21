import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/app_shell/app_shell_registry.dart';
import 'package:multiview_desktop/src/shared_entry_app.dart';

void main() {
  group('AppEntryPointFinder', () {
    testWidgets('findOutermostUpstream reads MaterialApp theme and locale', (tester) async {
      final registry = AppShellRegistry();
      addTearDown(registry.dispose);

      late BuildContext innerContext;

      await tester.pumpWidget(
        MainAppShellCapture(
          registry: registry,
          child: MaterialApp(
            themeMode: ThemeMode.dark,
            locale: const Locale('es'),
            home: Builder(
              builder: (context) {
                innerContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final upstream = AppEntryPointFinder.findOutermostUpstream(innerContext);
      expect(upstream?.themeMode, ThemeMode.dark);
      expect(upstream?.locale, const Locale('es'));
    });

    testWidgets('findShallowestInSubtree finds nested MaterialApp', (tester) async {
      final registry = AppShellRegistry();
      addTearDown(registry.dispose);

      late Element rootElement;

      await tester.pumpWidget(
        MainAppShellCapture(
          registry: registry,
          child: Builder(
            builder: (context) {
              rootElement = context as Element;
              return MaterialApp(
                themeMode: ThemeMode.light,
                home: const SizedBox(),
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final snapshot = AppEntryPointFinder.findShallowestInSubtree(rootElement);
      expect(snapshot?.themeMode, ThemeMode.light);
    });

    testWidgets('MainAppShellCapture syncs registry when themeMode changes', (tester) async {
      final registry = AppShellRegistry();
      addTearDown(registry.dispose);

      await tester.pumpWidget(
        _ThemeToggleHost(
          registry: registry,
          initialMode: ThemeMode.light,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(registry.snapshot?.themeMode, ThemeMode.light);

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      await tester.pump();

      expect(registry.snapshot?.themeMode, ThemeMode.dark);
    });
  });
}

class _ThemeToggleHost extends StatefulWidget {
  const _ThemeToggleHost({required this.registry, required this.initialMode});

  final AppShellRegistry registry;
  final ThemeMode initialMode;

  @override
  State<_ThemeToggleHost> createState() => _ThemeToggleHostState();
}

class _ThemeToggleHostState extends State<_ThemeToggleHost> {
  late ThemeMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  @override
  Widget build(BuildContext context) {
    return MainAppShellCapture(
      registry: widget.registry,
      child: MaterialApp(
        themeMode: _mode,
        home: Scaffold(
          body: ElevatedButton(
            onPressed: () => setState(() => _mode = ThemeMode.dark),
            child: const Text('toggle'),
          ),
        ),
      ),
    );
  }
}
