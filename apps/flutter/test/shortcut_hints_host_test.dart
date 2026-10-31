import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/core/widgets/shortcut_hints.dart';

void main() {
  for (final useShortcut in [false, true]) {
    testWidgets(
      'tab change resets and rearms Command hints: shortcut=$useShortcut',
      (tester) async {
        var location = '/today';
        await tester.pumpWidget(
          MaterialApp(
            builder: (_, child) => ShortcutHintsHost(child: child!),
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: ShortcutHintsScope(
                  fallback: true,
                  identity: location,
                  hints: const [ShortcutHint('Add task', '⌘N', release: false)],
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(
                        LogicalKeyboardKey.digit2,
                        meta: true,
                      ): () =>
                          setState(() => location = '/upcoming'),
                    },
                    child: Focus(
                      autofocus: true,
                      child: Column(
                        children: [
                          TextButton(
                            onPressed: () =>
                                setState(() => location = '/upcoming'),
                            child: const Text('Upcoming'),
                          ),
                          const ShortcutHintsBar(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump(const Duration(seconds: 1));
        expect(
          tester.widget<Visibility>(find.byType(Visibility)).visible,
          isTrue,
        );

        if (useShortcut) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.digit2);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.digit2);
        } else {
          await tester.tap(find.text('Upcoming'));
        }
        await tester.pump();
        final navigationException = tester.takeException();
        expect(location, '/upcoming');
        final visibleAfterNavigation = tester
            .widget<Visibility>(find.byType(Visibility))
            .visible;
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();
        final visibleAfterRelease = tester
            .widget<Visibility>(find.byType(Visibility))
            .visible;
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump(const Duration(seconds: 1));
        expect(
          tester.widget<Visibility>(find.byType(Visibility)).visible,
          isTrue,
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();
        expect(navigationException, isNull);
        expect(visibleAfterNavigation, isFalse);
        expect(visibleAfterRelease, isFalse);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
}
