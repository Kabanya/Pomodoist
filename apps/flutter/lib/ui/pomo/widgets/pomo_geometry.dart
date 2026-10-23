import 'dart:math' as math;
import 'dart:ui';
import 'package:pomodoist/domain/models/pomo/pomo_models.dart';

/// The single logical-pixel layout used by Flutter and native input regions.
class PomoLayout {
  PomoLayout(this.scale);
  final double scale;

  /// GTK windows use integer logical sizes even on a HiDPI output. Keep the
  /// full fractional Flutter layout inside the native canvas and compare the
  /// snapped frame on later transactions rather than repeatedly resizing it.
  static Rect gtkBounds(Rect requested, Rect workArea) {
    final width = math.min(
      requested.width.ceilToDouble(),
      workArea.width.floorToDouble(),
    );
    final height = math.min(
      requested.height.ceilToDouble(),
      workArea.height.floorToDouble(),
    );
    final left = requested.left
        .roundToDouble()
        .clamp(
          workArea.left.ceilToDouble(),
          (workArea.right - width).floorToDouble(),
        )
        .toDouble();
    final top = requested.top
        .roundToDouble()
        .clamp(
          workArea.top.ceilToDouble(),
          (workArea.bottom - height).floorToDouble(),
        )
        .toDouble();
    return Rect.fromLTWH(left, top, width, height);
  }

  double get button => math.max(48, 48 * scale);
  double get gap => math.max(8, 8 * scale);
  double get padding => math.max(4, 4 * scale);
  double get timerFontSize => math.max(12, 16 * scale);
  double get iconSize => math.max(20, 20 * scale);
  double get _diameter => 208 * scale;
  double get _width =>
      math.max(_diameter + 2 * (button + gap), 3 * button + 2 * gap) +
      2 * padding;
  Rect get pet => Rect.fromLTWH(
    (_width - _diameter) / 2,
    padding + button + gap,
    _diameter,
    _diameter,
  );
  Rect get capsule => Rect.fromLTWH(
    (_width - math.max(112, 148 * scale)) / 2,
    math.max(pet.bottom, add.bottom) + gap,
    math.max(112, 148 * scale),
    button,
  );
  Rect get add => Rect.fromLTWH(
    pet.left - gap - button,
    pet.center.dy - button / 2,
    button,
    button,
  );
  Rect get toggle => Rect.fromLTWH(pet.right + gap, add.top, button, button);
  Rect get complete =>
      Rect.fromLTWH((_width - button) / 2, padding, button, button);
  Rect get settings => complete.shift(Offset(-button - gap, 0));
  Rect get hide => complete.shift(Offset(button + gap, 0));
  Size get size => Size(_width, capsule.bottom + padding);
  bool matchesWindowSize(Size actual, {double pixelRatio = 1}) =>
      (actual.width - size.width).abs() <= .5 / pixelRatio &&
      (actual.height - size.height).abs() <= .5 / pixelRatio;

  /// Native frames are rounded to physical pixels. Treat that rounding as settled.
  static bool matchesWindowBounds(
    Rect expected,
    Rect actual, {
    double pixelRatio = 1,
  }) {
    final tolerance = .5 / pixelRatio + 1e-7;
    return (expected.left - actual.left).abs() <= tolerance &&
        (expected.top - actual.top).abs() <= tolerance &&
        (expected.width - actual.width).abs() <= tolerance &&
        (expected.height - actual.height).abs() <= tolerance;
  }

  List<Rect> regions(
    bool expanded, {
    bool capsuleVisible = true,
    Rect? contextMenu,
  }) => [
    pet,
    if (capsuleVisible) capsule,
    if (expanded) ...[add, toggle, complete, settings, hide],
    ?contextMenu,
  ];

  /// Retains the chosen preference; only the applied layout is reduced.
  static PomoLayout fitting(double preferred, Size available) {
    var low = .25, high = PomoPreferences.normalizeScale(preferred);
    bool fits(double s) {
      final size = PomoLayout(s).size;
      return size.width <= available.width && size.height <= available.height;
    }

    if (fits(high)) return PomoLayout(high);
    for (var i = 0; i < 40; i++) {
      final mid = (low + high) / 2;
      if (fits(mid)) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return PomoLayout(low);
  }

  Offset position(Rect area, {Offset? saved, Offset? center}) => clampPosition(
    area,
    size,
    saved ??
        (center == null
            ? Offset(
                area.right - size.width - 24,
                area.bottom - size.height - 24,
              )
            : center - Offset(size.width / 2, size.height / 2)),
  );
  static Offset clampPosition(Rect area, Size size, Offset point) => Offset(
    point.dx.clamp(area.left, math.max(area.left, area.right - size.width)),
    point.dy.clamp(area.top, math.max(area.top, area.bottom - size.height)),
  );
  static Offset panelPosition(
    Rect area,
    Rect pomo,
    Size panel, {
    Offset? saved,
  }) => clampPosition(
    area,
    panel,
    saved ??
        Offset(
          pomo.left - panel.width - 12 >= area.left
              ? pomo.left - panel.width - 12
              : pomo.right + 12,
          pomo.center.dy - panel.height / 2,
        ),
  );
}
