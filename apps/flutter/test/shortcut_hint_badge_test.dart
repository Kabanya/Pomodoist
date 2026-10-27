import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/keyboard_shortcuts.dart';
import 'package:pomodoist/ui/core/widgets/shortcut_hints.dart';

void main() {
  for (final outside in [false, true]) {
    testWidgets(
      'badge without a host keeps its action usable outside=$outside',
      (tester) async {
        var activations = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ShortcutHintBadge(
                command: AppShortcutCommand.focus,
                outside: outside,
                child: TextButton(
                  onPressed: () => activations++,
                  child: const Text('Focus'),
                ),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Focus'));
        expect(activations, 1);
      },
    );
  }
}
