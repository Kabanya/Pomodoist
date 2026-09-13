import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/widgets/keyboard_dismiss_region.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('touch down keeps editing focused; mouse outside still unfocuses', () {
    final focus = FocusNode();
    final manager = FocusManager.instance;
    addTearDown(() {
      focus.dispose();
      manager.applyFocusChangesIfNeeded();
    });

    manager.rootScope.requestFocus(focus);
    manager.applyFocusChangesIfNeeded();
    expect(focus.hasFocus, isTrue);

    handleTextTapOutside(
      EditableTextTapOutsideIntent(
        focusNode: focus,
        pointerDownEvent: const PointerDownEvent(kind: PointerDeviceKind.touch),
      ),
    );
    manager.applyFocusChangesIfNeeded();
    // Touch down may become a scroll, a swipe, or a tap on another control.
    expect(focus.hasFocus, isTrue);

    handleTextTapOutside(
      EditableTextTapOutsideIntent(
        focusNode: focus,
        pointerDownEvent: const PointerDownEvent(kind: PointerDeviceKind.mouse),
      ),
    );
    manager.applyFocusChangesIfNeeded();
    expect(focus.hasFocus, isFalse);
  });
}
