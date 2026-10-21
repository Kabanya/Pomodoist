import 'package:flutter/widgets.dart';

import '../multi_view_desktop.dart';

/// Makes its child area draggable to move the current window.
///
/// Typically used on a custom title bar or another drag handle:
///
/// ```dart
/// DragToMoveArea(
///   child: SizedBox(
///     height: 32,
///     child: Text('My App'),
///   ),
/// )
/// ```
class DragToMoveArea extends StatelessWidget {
  const DragToMoveArea({
    super.key,
    required this.child,
  });

  /// Child widget that receives drag gestures to move the window.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => MultiViewDesktop.of(context).startDragging(),
      // Absorb double-tap to avoid accidental maximize on the drag area.
      onDoubleTap: () {},
      child: child,
    );
  }
}
