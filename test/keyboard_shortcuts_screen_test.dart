// ignore_for_file: deprecated_member_use

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

  testWidgets('screen follows sidebar order and shows the global shortcut', (
    tester,
  ) async {
    await _pumpScreen(tester);

    const commandKeys = [
      'toggleSidebar',
      'quickAdd',
      'browse',
      'search',
      'today',
      'upcoming',
      'focus',
      'inbox',
      'priorityMatrix',
      'timeline',
      'kanban',
      'reports',
      'settings',
    ];
    for (final commandKey in commandKeys) {
      final row = find.byKey(Key('shortcut-row-$commandKey'));
      await tester.scrollUntilVisible(
        row,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(row, findsOneWidget);
    }
    final globalRow = find.byKey(const Key('shortcut-row-global'));
    expect(globalRow, kIsWeb ? findsNothing : findsOneWidget);
    if (!kIsWeb) {
      await tester.scrollUntilVisible(
        globalRow,
        240,
        scrollable: find.byType(Scrollable).first,
      );
    }
    expect(find.text('⌥Space'), kIsWeb ? findsNothing : findsOneWidget);
  });

  testWidgets('global quick add can be disabled from desktop settings', (
    tester,
  ) async {
    await _pumpScreen(tester);

    if (!kIsWeb) {
      await tester.scrollUntilVisible(
        find.byKey(const Key('shortcut-row-global')),
        240,
        scrollable: find.byType(Scrollable).first,
      );
    }
    final toggle = find.byKey(const Key('global-quick-add-enabled'));
    expect(toggle, kIsWeb ? findsNothing : findsOneWidget);
    if (kIsWeb) return;

    await tester.scrollUntilVisible(
      toggle,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool(globalQuickAddEnabledPreferenceKey), isFalse);
    expect(tester.widget<Switch>(toggle).value, isFalse);

    await tester.scrollUntilVisible(
      find.byKey(const Key('shortcuts-reset-all')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('shortcuts-reset-all')));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(toggle).value, isFalse);
    expect(preferences.getBool(globalQuickAddEnabledPreferenceKey), isFalse);
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

  testWidgets('recorder uses macOS modifier flags', (tester) async {
    await _pumpScreen(tester);

    await tester.tap(find.byKey(const Key('shortcut-binding-quickAdd')));
    await tester.pumpAndSettle();
    _sendRawMacShortcut(keyCode: 38, character: 'j');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shortcut-recorder-dialog')), findsNothing);
    expect(find.text('⌘J'), findsOneWidget);
  });

  testWidgets('Windows global shortcut uses the Flutter recorder', (
    tester,
  ) async {
    await _pumpScreen(tester, platform: TargetPlatform.windows);
    await tester.scrollUntilVisible(
      find.byKey(const Key('shortcut-row-global')),
      240,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(find.byKey(const Key('shortcut-binding-global')));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('Ctrl+Alt+J'), findsOneWidget);
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
        LogicalKeyboardKey.digit2,
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
      await tester.scrollUntilVisible(
        find.byKey(const Key('shortcut-binding-quickAdd')),
        -300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('⌘N'), findsOneWidget);
    },
  );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.macOS,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [shortcutTargetPlatformProvider.overrideWithValue(platform)],
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

void _sendRawMacShortcut({required int keyCode, required String character}) {
  final data = RawKeyEventDataMacOs(
    characters: character,
    charactersIgnoringModifiers: character,
    keyCode: keyCode,
    modifiers: RawKeyEventDataMacOs.modifierCommand,
  );
  RawKeyboard.instance.handleRawKeyEvent(RawKeyDownEvent(data: data));
  RawKeyboard.instance.handleRawKeyEvent(RawKeyUpEvent(data: data));
}
