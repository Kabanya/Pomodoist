import 'package:flutter/widgets.dart';


/// Exposes the parent `BuildContext` for a dialog or secondary window.
///
/// Set automatically when a window is opened with a parent context. Useful
/// inside dialog builders when you need to refer to the parent window.
class ParentWindowScope extends InheritedWidget {
  const ParentWindowScope({
    super.key,
    required this.parentContext,
    required super.child,
  });

  /// `BuildContext` of the parent window, or null when no parent was specified.
  final BuildContext? parentContext;

  /// Returns the nearest `ParentWindowScope`, or null outside `runMultiApp`.
  static ParentWindowScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ParentWindowScope>();
  }

  /// Returns the nearest `ParentWindowScope`.
  ///
  /// Throws in debug mode when `runMultiApp` was not used as the entry point.
  static ParentWindowScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(
    scope != null,
    'No ParentWindowScope found in context. '
        'Make sure runMultiApp() is used as the app entry point.',
    );
    return scope!;
  }

  @override
  bool updateShouldNotify(ParentWindowScope oldWidget) => parentContext != oldWidget.parentContext;
}
