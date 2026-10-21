import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Provides the numeric OS-view identifier for the current window.
///
/// Automatically injected by `runMultiApp` around every view in the
/// `ViewCollection`.  Read it with `MultiViewDesktop._getCurrentId` or
/// directly:
///
/// ```dart
/// final id = ViewScope.of(context).viewId;
/// ```
@internal
class ViewScope extends InheritedWidget {
  const ViewScope({
    super.key,
    required this.viewId,
    required super.child,
  });

  final int viewId;

  /// Returns the `ViewScope` above `context`, or `null` if the tree was not
  /// created with `runMultiApp`.
  @internal
  static ViewScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ViewScope>();
  }

  /// Returns the `ViewScope` above `context`.
  ///
  /// Throws in debug mode if `runMultiApp` was not used as the entry point.
  @internal
  static ViewScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(
      scope != null,
      'No ViewScope found in context. '
      'Make sure runMultiApp() is used as the app entry point.',
    );
    return scope!;
  }

  @override
  bool updateShouldNotify(ViewScope oldWidget) => viewId != oldWidget.viewId;
}
