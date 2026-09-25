import 'dart:ui' show lerpDouble;
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:pomodoist/domain/models/settings/bottom_navigation_preferences.dart';

({bool expands, bool labelsBelow}) bottomNavigationLayout(
  BottomNavigationStyle style,
  int count,
) => (
  expands: count > 0 && (style == BottomNavigationStyle.labels || count >= 4),
  labelsBelow: style == BottomNavigationStyle.labels && count >= 3,
);

/// One animation drives the surface, every button and both changing labels.
class BottomNavigationFrame {
  BottomNavigationFrame({
    required List<double> widths,
    required List<double> labels,
  }) : widths = List.unmodifiable(widths),
       labels = List.unmodifiable(labels);

  final List<double> widths;
  final List<double> labels;
  double get contentWidth => widths.fold(0, (sum, width) => sum + width);

  @override
  bool operator ==(Object other) =>
      other is BottomNavigationFrame &&
      listEquals(widths, other.widths) &&
      listEquals(labels, other.labels);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(widths), Object.hashAll(labels));
}

class BottomNavigationTween extends Tween<BottomNavigationFrame> {
  BottomNavigationTween({super.begin, required BottomNavigationFrame end})
    : super(end: end);

  @override
  BottomNavigationFrame lerp(double t) {
    final from = begin ?? end!;
    final to = end!;
    return BottomNavigationFrame(
      widths: List.generate(
        to.widths.length,
        (i) => lerpDouble(from.widths[i], to.widths[i], t)!,
      ),
      labels: List.generate(
        to.labels.length,
        (i) => lerpDouble(from.labels[i], to.labels[i], t)!,
      ),
    );
  }
}
