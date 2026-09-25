import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';

/// Slides to a corner without Material's default shrink/rotate transition.
class CompactTaskButtonAnimator extends FloatingActionButtonAnimator {
  const CompactTaskButtonAnimator({this.from, this.immediate = false});

  final Offset? from;
  final bool immediate;

  @override
  Offset getOffset({
    required Offset begin,
    required Offset end,
    required double progress,
  }) {
    if (immediate) return end;
    // Scaffold's movement controller lasts twice its standard FAB segue.
    final elapsed = progress * kFloatingActionButtonSegue.inMicroseconds * 2;
    final t = (elapsed / AppMotion.panel.inMicroseconds).clamp(0.0, 1.0);
    return Offset.lerp(from ?? begin, end, AppMotion.curve.transform(t))!;
  }

  @override
  Animation<double> getScaleAnimation({required Animation<double> parent}) =>
      const AlwaysStoppedAnimation(1);

  @override
  Animation<double> getRotationAnimation({required Animation<double> parent}) =>
      const AlwaysStoppedAnimation(0);
}

/// Keeps a movable Add button inside safe bounds and above contextual panels.
class CompactTaskButtonLocation extends FloatingActionButtonLocation {
  CompactTaskButtonLocation({
    this.corner = Alignment.bottomRight,
    this.dragPosition,
    this.bottomClearance = 0,
  });

  final Alignment corner;
  final Offset? dragPosition;
  final double bottomClearance;
  Rect bounds = Rect.zero;
  Offset position = Offset.zero;

  Offset clamp(Offset value) => Offset(
    value.dx.clamp(bounds.left, bounds.right),
    value.dy.clamp(bounds.top, bounds.bottom),
  );

  Alignment nearestCorner(Offset velocity) {
    final projected = position + velocity * .18;
    return Alignment(
      projected.dx < bounds.center.dx ? -1 : 1,
      projected.dy < bounds.center.dy ? -1 : 1,
    );
  }

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry geometry) {
    final size = geometry.floatingActionButtonSize;
    final left = geometry.minInsets.left + 16;
    // The compact shell and task details both have a 52 px header.
    final top = math.max(geometry.contentTop, geometry.minInsets.top + 52) + 16;
    final right =
        geometry.scaffoldSize.width -
        geometry.minInsets.right -
        16 -
        size.width;
    final bottom = math.min(
      FloatingActionButtonLocation.endFloat.getOffset(geometry).dy,
      geometry.scaffoldSize.height - bottomClearance - 16 - size.height,
    );
    bounds = Rect.fromLTRB(
      left,
      top,
      math.max(left, right),
      math.max(top, bottom),
    );
    position = clamp(
      dragPosition ??
          Offset(
            corner.x < 0 ? bounds.left : bounds.right,
            corner.y < 0 ? bounds.top : bounds.bottom,
          ),
    );
    return position;
  }
}
