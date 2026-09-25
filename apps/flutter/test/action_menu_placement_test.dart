import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/core/widgets/app_action_menu.dart';

void main() {
  test('menus choose the larger side and scroll within that space', () {
    const viewport = Rect.fromLTRB(0, 24, 1000, 780);
    for (final (trigger, below, left) in [
      (const Rect.fromLTWH(900, 60, 48, 48), true, true),
      (const Rect.fromLTWH(20, 650, 48, 48), false, false),
      (const Rect.fromLTWH(900, 420, 48, 48), false, true),
    ]) {
      final placement = actionMenuPlacement(trigger, viewport);
      final target = placement.anchor.targetAnchor.resolve(TextDirection.ltr);
      final follower = placement.anchor.followerAnchor.resolve(
        TextDirection.ltr,
      );
      expect(target.y, below ? 1 : -1);
      // ShadAnchorAuto subtracts menu height for a top follower.
      expect(follower.y, target.y);
      expect(follower.x, left ? -1 : 1);
      final available = below
          ? viewport.bottom - trigger.bottom
          : trigger.top - viewport.top;
      expect(placement.maxHeight, greaterThanOrEqualTo(0));
      expect(placement.maxHeight, lessThan(available));
    }
    const trigger = Rect.fromLTWH(450, 330, 48, 48);
    expect(
      actionMenuPlacement(
        trigger,
        viewport,
      ).anchor.targetAnchor.resolve(TextDirection.ltr).y,
      1,
    );
    expect(
      actionMenuPlacement(
        trigger,
        const Rect.fromLTRB(0, 24, 1000, 480),
      ).anchor.targetAnchor.resolve(TextDirection.ltr).y,
      -1,
    );
    expect(
      actionMenuPlacement(
        trigger,
        const Rect.fromLTRB(0, 330, 1000, 378),
      ).maxHeight,
      0,
    );
  });
}
