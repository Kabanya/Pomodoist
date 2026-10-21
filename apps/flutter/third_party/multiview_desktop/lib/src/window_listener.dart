import 'package:flutter/widgets.dart';

import 'multi_view_desktop.dart';

/// Callback surface used by the library to deliver native window events.
///
/// Implement this interface directly or use the `WindowListener` mixin on a
/// `State` under `ViewScope`. All methods have empty default implementations
/// in the mixin.
abstract interface class WindowListenerCallbacks {
  /// Called when the user requests close (title bar button or OS shortcut).
  ///
  /// Fires instead of destroying the window when `MultiViewDesktop.setPreventClose`
  /// is true. Call `MultiViewDesktop.closeWindow` after your confirmation logic.
  void onWindowClose();

  /// Called when this window gains keyboard focus.
  void onWindowFocus();

  /// Called when this window loses keyboard focus.
  void onWindowBlur();

  /// Called when the window enters the maximized state.
  void onWindowMaximize();

  /// Called when the window leaves the maximized state.
  void onWindowUnmaximize();

  /// Called when the window enters the minimized state.
  void onWindowMinimize();

  /// Called when the window is restored from minimized or maximized state.
  void onWindowRestore();

  /// Called continuously while the user is resizing the window.
  void onWindowResize();

  /// Called once when a resize gesture finishes.
  void onWindowResized();

  /// Called continuously while the user is moving the window.
  void onWindowMove();

  /// Called once when a move gesture finishes.
  void onWindowMoved();

  /// Called when the window enters native full-screen mode.
  void onWindowEnterFullScreen();

  /// Called when the window leaves native full-screen mode.
  void onWindowLeaveFullScreen();

  /// Called for every native event, including those with dedicated callbacks above.
  ///
  /// `eventName` is the raw name from the native layer, for example `focus`,
  /// `blur`, `maximize`, `close`, `resize`, `move`.
  void onWindowEvent(String eventName);
}

/// `State` mixin that registers `WindowListenerCallbacks` for the current window.
///
/// Registration runs from `didChangeDependencies` and uses the public view id
/// from `MultiViewDesktop.getIdByContext`. Cleanup runs from `dispose` without
/// needing `BuildContext`.
///
/// ```dart
/// class _HomePageState extends State<HomePage> with WindowListener {
///   @override
///   void onWindowClose() {
///     // show confirm dialog, then closeWindow()
///   }
/// }
/// ```
mixin WindowListener<T extends StatefulWidget> on State<T> implements WindowListenerCallbacks {
  int? _mvdRegisteredViewId;

  /// Public view id this listener is registered for, or null before registration.
  int? get currentId => _mvdRegisteredViewId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mvdSyncWindowListenerRegistration();
  }

  @override
  void dispose() {
    _mvdUnregisterWindowListener();
    super.dispose();
  }

  void _mvdSyncWindowListenerRegistration() {
    final int shiftedViewId = MultiViewDesktop.getIdByContext(context);
    if (_mvdRegisteredViewId == shiftedViewId) return;

    _mvdUnregisterWindowListener();
    _mvdRegisteredViewId = shiftedViewId;
    MultiViewDesktop.addListenerForView(shiftedViewId, this);
  }

  void _mvdUnregisterWindowListener() {
    if(_mvdRegisteredViewId == null) return;

    MultiViewDesktop.removeListenerForView(_mvdRegisteredViewId!, this);
    _mvdRegisteredViewId = null;
  }

  @override
  void onWindowClose() {}

  @override
  void onWindowFocus() {}

  @override
  void onWindowBlur() {}

  @override
  void onWindowMaximize() {}

  @override
  void onWindowUnmaximize() {}

  @override
  void onWindowMinimize() {}

  @override
  void onWindowRestore() {}

  @override
  void onWindowResize() {}

  @override
  void onWindowResized() {}

  @override
  void onWindowMove() {}

  @override
  void onWindowMoved() {}

  @override
  void onWindowEnterFullScreen() {}

  @override
  void onWindowLeaveFullScreen() {}

  @override
  void onWindowEvent(String eventName) {}
}
