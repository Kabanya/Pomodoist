import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/pomo/widgets/pomo_geometry.dart';

void main() {
  test(
    'GTK geometry settles in integer logical pixels at fractional scales',
    () {
      final layout = PomoLayout(1.1);
      final snapped = PomoLayout.gtkBounds(
        const Offset(10.4, 20.6) & layout.size,
        const Rect.fromLTWH(0, 0, 1920, 1080),
      );
      expect(snapped.topLeft, const Offset(10, 21));
      expect(snapped.width, layout.size.width.ceilToDouble());
      expect(snapped.height, layout.size.height.ceilToDouble());
      expect(
        PomoLayout.matchesWindowBounds(snapped, snapped, pixelRatio: 2),
        true,
      );
      expect(
        PomoLayout.gtkBounds(snapped, const Rect.fromLTWH(0, 0, 1920, 1080)),
        snapped,
      );
    },
  );
  test(
    'rounding keeps the entire native window within a reserved work area',
    () {
      const area = Rect.fromLTWH(-1920, 32, 1920, 1048);
      final snapped = PomoLayout.gtkBounds(
        const Rect.fromLTWH(-360.8, 880.6, 360.8, 199.4),
        area,
      );
      expect(snapped.right, lessThanOrEqualTo(area.right));
      expect(snapped.bottom, lessThanOrEqualTo(area.bottom));
      expect(snapped.width, 361);
      expect(snapped.height, 200);
    },
  );
}
