import 'package:flutter/widgets.dart';

import '../multi_view_desktop.dart';
import '../resize_edge.dart';

/// Starts a native window resize when the user drags this area.
///
/// Used on edges and corners of frameless windows:
///
/// ```dart
/// DragToResizeArea(
///   resizeEdge: ResizeEdge.bottomRight,
///   child: const SizedBox(width: 8, height: 8),
/// )
/// ```
class DragToResizeArea extends StatelessWidget {
  const DragToResizeArea({
    super.key,
    required this.resizeEdge,
    required this.child,
    this.enableResizeEdge,
  });

  /// Which edge or corner initiates the native resize drag.
  final ResizeEdge resizeEdge;

  /// Hit target shown to the user (often a thin `SizedBox` on the window edge).
  final Widget child;

  /// When false, dragging this area does not start a resize. Defaults to enabled.
  final bool? enableResizeEdge;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) {
        if (enableResizeEdge == false) return;
        MultiViewDesktop.of(context).startResizing(resizeEdge);
      },
      child: child,
    );
  }
}
