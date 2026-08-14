import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/keyboard_shortcuts.dart';
import 'package:pomodoist/app/platform_quick_add.dart';
import 'package:pomodoist/features/settings/presentation/keyboard_shortcuts_screen.dart';
import 'package:pomodoist/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(quickAddChannelName);

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return switch (call.method) {
            quickAddGetGlobalShortcutMethod => {
              'keyCode': 49,
              'keyLabel': 'Space',
              'meta': false,
              'control': false,
              'alt': true,
              'shift': false,
            },
            quickAddCaptureGlobalShortcutMethod => {
              'keyCode': 38,
              'keyLabel': 'J',
              'meta': true,
              'control': false,
              'alt': false,
              'shift': false,
            },
            quickAddSetGlobalShortcutMethod ||
            quickAddCancelGlobalShortcutCaptureMethod => null,
            _ => null,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('screen shows six app shortcuts and the macOS global shortcut', (
    tester,
  ) async {
    await _pumpScreen(tester);

    for (final command in AppShortcutCommand.values) {
      expect(
        find.byKey(Key('shortcut-row-${command.storageKey}')),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(const Key('shortcut-row-global')),
      kIsWeb ? findsNothing : findsOneWidget,
    );
    expect(find.text('⌥Space'), kIsWeb ? findsNothing : findsOneWidget);
  });

  testWidgets('recorder saves a valid shortcut and Escape cancels', (
    tester,
  ) async {
    await _pumpScreen(tester);

    await tester.tap(find.byKey(const Key('shortcut-binding-quickAdd')));
    await tester.pumpAndSettle();
    await _pressShortcut(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.keyJ,
    );
    await tester.pumpAndSettle();
    expect(find.text('⌘J'), findsOneWidget);

    await tester.tap(find.byKey(const Key('shortcut-binding-quickAdd')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shortcut-recorder-dialog')), findsNothing);
    expect(find.text('⌘J'), findsOneWidget);
  });

  testWidgets(
    'duplicate shortcut remains in the recorder and reset restores defaults',
    (tester) async {
      await _pumpScreen(tester);

      await tester.tap(find.byKey(const Key('shortcut-binding-quickAdd')));
      await tester.pumpAndSettle();
      await _pressShortcut(
        tester,
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.keyK,
      );
      await tester.pumpAndSettle();

      expect(find.text('This shortcut is already in use.'), findsOneWidget);
      expect(find.byKey(const Key('shortcut-recorder-dialog')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shortcut-binding-quickAdd')));
      await tester.pumpAndSettle();
      await _pressShortcut(
        tester,
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.keyJ,
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('shortcuts-reset-all')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('shortcuts-reset-all')));
      await tester.pumpAndSettle();

      expect(find.text('⌘N'), findsOneWidget);
    },
  );
}

Future<void> _pumpScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        shortcutTargetPlatformProvider.overrideWithValue(TargetPlatform.macOS),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: KeyboardShortcutsScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pressShortcut(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(modifier);
}
