import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/core/view_models/shortcut_hints_controller.dart';

void main() {
  test('one-second threshold, repeat, modifiers, release and rearm', () {
    fakeAsync((time) {
      final hints = ShortcutHintsController();
      hints.key(primary: true, primaryDown: true);
      time.elapse(const Duration(milliseconds: 700));
      hints.key(primary: true, primaryDown: true, repeat: true);
      time.elapse(const Duration(milliseconds: 299));
      expect(hints.visible, isFalse);
      time.elapse(const Duration(milliseconds: 1));
      expect(hints.visible, isTrue);
      hints.key(primary: true, otherModifier: true);
      expect(hints.visible, isTrue);
      hints.key(primary: false);
      expect(hints.visible, isFalse);
      hints.key(primary: true, primaryDown: true);
      time.elapse(const Duration(seconds: 1));
      expect(hints.visible, isTrue);
      hints.dispose();
    });
  });

  test('ordinary keys cancel pending and visible hints until release', () {
    fakeAsync((time) {
      final hints = ShortcutHintsController();
      hints.key(primary: true, primaryDown: true);
      time.elapse(const Duration(milliseconds: 500));
      hints.key(primary: true, ordinaryDown: true);
      hints.key(primary: true, primaryDown: true, repeat: true);
      time.elapse(const Duration(seconds: 2));
      expect(hints.visible, isFalse);
      hints.key(primary: false);
      hints.key(primary: true, primaryDown: true);
      time.elapse(const Duration(seconds: 1));
      hints.key(primary: true, ordinaryDown: true);
      expect(hints.visible, isFalse);
      hints.dispose();
    });
  });

  test('reset cancels timer, disarms held modifier, and isolates windows', () {
    fakeAsync((time) {
      final first = ShortcutHintsController();
      final second = ShortcutHintsController();
      first.key(primary: true, primaryDown: true);
      first.reset();
      time.elapse(const Duration(seconds: 2));
      expect(first.visible, isFalse);
      first.key(primary: true, primaryDown: true);
      time.elapse(const Duration(seconds: 1));
      expect(first.visible, isFalse);
      first.key(primary: false);
      first.key(primary: true, primaryDown: true);
      time.elapse(const Duration(seconds: 1));
      expect(first.visible, isTrue);
      expect(second.visible, isFalse);
      first.reset();
      expect(first.visible, isFalse);
      first.dispose();
      second.dispose();
    });
  });

  test('primary starts alone; extra modifier before threshold cancels', () {
    fakeAsync((time) {
      final hints = ShortcutHintsController();
      hints.key(primary: true, primaryDown: true, otherModifier: true);
      time.elapse(const Duration(seconds: 1));
      expect(hints.visible, isFalse);
      hints.key(primary: false);
      hints.key(primary: true, primaryDown: true);
      hints.key(primary: true, otherModifier: true);
      time.elapse(const Duration(seconds: 1));
      expect(hints.visible, isFalse);
      hints.dispose();
    });
  });
  test(
    'context changes, window blur and recording suppression require a new hold',
    () {
      fakeAsync((time) {
        final hints = ShortcutHintsController();
        hints.setContext('shell', enabled: true);
        hints.key(primary: true, primaryDown: true);
        time.elapse(const Duration(milliseconds: 600));
        hints.setContext('editor', enabled: true);
        time.elapse(const Duration(seconds: 1));
        expect(hints.visible, isFalse);
        hints.key(primary: false);
        hints.key(primary: true, primaryDown: true);
        time.elapse(const Duration(seconds: 1));
        expect(hints.visible, isTrue);
        hints.setFocused(false);
        expect(hints.visible, isFalse);
        hints.setFocused(true);
        hints.key(primary: true, primaryDown: true);
        time.elapse(const Duration(seconds: 1));
        expect(hints.visible, isFalse);
        hints.key(primary: false);
        hints.setContext('recorder', enabled: false);
        hints.key(primary: true, primaryDown: true);
        time.elapse(const Duration(seconds: 1));
        expect(hints.visible, isFalse);
        hints.key(primary: false);
        hints.setContext('shell', enabled: true);
        hints.key(primary: true, primaryDown: true);
        time.elapse(const Duration(seconds: 1));
        expect(hints.visible, isTrue);
        hints.setContext('shell', enabled: true);
        expect(hints.visible, isTrue);
        hints.setContext('unknown dialog', enabled: false);
        expect(hints.visible, isFalse);
        hints.dispose();
      });
    },
  );
}
