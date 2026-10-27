import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/core/widgets/shortcut_hints.dart';

void main() {
  test(
    'full shortcut label uses viewport space instead of 48px button bounds',
    () {
      const viewport = Size(360, 280);
      const label = Size(200, 40);
      const anchor = Rect.fromLTWH(280, 4, 48, 48);
      const layout = ShortcutHintPopupLayout(anchor);
      expect(
        layout
            .getConstraintsForChild(BoxConstraints.tight(viewport))
            .constrain(label),
        label,
      );
      final position = layout.getPositionForChild(viewport, label);
      final rect = position & label;
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(viewport.width));
      expect(rect.top, greaterThan(anchor.bottom));
      expect(rect.bottom, lessThanOrEqualTo(viewport.height));
    },
  );

  test('scaled label flips above a low button and follows a moved anchor', () {
    const viewport = Size(360, 280);
    const label = Size(300, 80);
    const anchor = Rect.fromLTWH(290, 228, 48, 48);
    const layout = ShortcutHintPopupLayout(anchor);
    expect(
      layout
          .getConstraintsForChild(BoxConstraints.tight(viewport))
          .constrain(label),
      label,
    );
    final rect = layout.getPositionForChild(viewport, label) & label;
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(viewport.width));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThan(anchor.top));
    expect(
      layout.shouldRelayout(const ShortcutHintPopupLayout(Rect.zero)),
      isTrue,
    );
    expect(
      layout.shouldRelayout(const ShortcutHintPopupLayout(anchor)),
      isFalse,
    );
  });
}
