import 'package:flutter/widgets.dart';

/// Keeps GNOME stage geometry aligned with an independently scaled GTK viewport.
/// The native input region uses the inverse mapping of this same stage canvas.
class PomoStageCanvas extends StatelessWidget {
  const PomoStageCanvas({
    required this.enabled,
    required this.stageSize,
    required this.child,
    this.canvasKey,
    super.key,
  });

  final bool enabled;
  final Size stageSize;
  final Widget child;
  final GlobalKey? canvasKey;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return KeyedSubtree(key: canvasKey, child: child);
    return FittedBox(
      fit: BoxFit.fill,
      alignment: Alignment.topLeft,
      child: SizedBox.fromSize(
        key: canvasKey,
        size: stageSize,
        child: MediaQuery(
          data: (MediaQuery.maybeOf(context) ?? const MediaQueryData())
              .copyWith(size: stageSize),
          child: child,
        ),
      ),
    );
  }
}

/// Converts menu rows from the fitted Navigator overlay to native stage regions.
/// Menu padding and entrance movement use the same stage units as the body.
Rect? pomoMenuBoundsInCanvas(
  RenderBox canvas,
  Iterable<RenderBox> items, {
  Rect? clip,
}) {
  Rect? overlayBounds;
  for (final item in items) {
    if (!item.hasSize) continue;
    final bounds = MatrixUtils.transformRect(
      item.getTransformTo(null),
      Offset.zero & item.size,
    );
    overlayBounds = overlayBounds?.expandToInclude(bounds) ?? bounds;
  }
  if (overlayBounds == null) return null;
  final bounds = Rect.fromPoints(
    canvas.globalToLocal(overlayBounds.topLeft),
    canvas.globalToLocal(overlayBounds.bottomRight),
  ).inflate(8).intersect(clip ?? Offset.zero & canvas.size);
  return bounds.isEmpty ? null : bounds;
}
