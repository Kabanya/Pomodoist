/// Observer for native window lifecycle events in a multiview_desktop application.
///
/// Extend this class and override only the callbacks you need.
/// All methods have empty default implementations so unused events are
/// silently ignored.
///
/// Register one or more observers via `MultiAppConfig.observers` passed to
/// `runMultiApp`.
///
/// The design mirrors Flutter's `NavigatorObserver`: observers are passive
/// sinks - they receive notifications but cannot influence the outcome.
///
/// ```dart
/// class AppWindowObserver extends WindowObserver {
///   @override
///   void onWindowOpened(int viewId, {int? parentViewId}) {
///     print('window $viewId opened (parent: $parentViewId)');
///   }
///
///   @override
///   void onWindowClosed(int viewId) {
///     print('window $viewId closed');
///   }
/// }
///
/// void main() {
///   runMultiApp(
///     home: ...,
///     config: MultiAppConfig(
///       observers: [AppWindowObserver()],
///     ),
///   );
/// }
/// ```
///
/// All `viewId` values are the public (shifted) IDs, consistent with
/// `MultiViewDesktop.getIdByContext` and `MultiViewDesktop.allWindowViewIds`.
abstract class WindowObserver {
  /// Called after a new OS window has been opened and its widget tree
  /// registered.
  ///
  /// `viewId` is the public view ID of the new window.
  /// `parentViewId` is the public view ID of the window that called
  /// `openWindow`, or `null` when no parent context was passed.
  void onWindowOpened(int viewId, {int? parentViewId}) {}


  /// Called after a new OS dialog has been opened and its widget tree
  /// registered.
  ///
  /// `viewId` is the public view ID of the new dialog.
  /// `parentViewId` is the public view ID of the window that called
  /// `openWindow`
  void onDialogOpened(int dialogId, {required int parentViewId}) {}

  /// Called after an OS window has been closed and its widget tree disposed.
  ///
  /// `viewId` is the public view ID of the closed window.
  void onWindowClosed(int viewId) {}

  /// Called after an OS dialog has been closed and its widget tree disposed.
  ///
  /// `viewId` is the public view ID of the closed window.
  void onDialogClose(int dialogId) {}

  /// Called when the anchor window changes.
  ///
  /// The anchor is the root window that receives app-level close events
  /// from the native close button or dock icon. It is promoted automatically
  /// when the current anchor closes, or changed manually via
  /// `MultiViewDesktop.setAnchorId`.
  ///
  /// `previousViewId` and `newViewId` are public view IDs, or `null`
  /// when no anchor exists (e.g. during shutdown).
  void onAnchorChanged(int? previousViewId, int? newViewId) {}

  /// Called for every native window event received by this view.
  ///
  /// `eventName` is the raw event name from the native layer:
  /// `focus`, `blur`, `maximize`, `unmaximize`, `minimize`, `restore`,
  /// `resize`, `resized`, `move`, `moved`, `enter-full-screen`,
  /// `leave-full-screen`, `close`.
  ///
  /// Fires alongside the individual `WindowListener` callbacks. Useful for
  /// cross-window logging or analytics without needing a `WindowListener`
  /// mixin in every widget.
  void onWindowEvent(int viewId, String eventName) {}


  /// Called for every native dialog event received by this view.
  ///
  /// `eventName` is the raw event name from the native layer:
  /// `focus`, `blur`, `maximize`, `unmaximize`,
  /// `resize`, `resized`, `move`, `moved`, `close`.
  ///
  ///
  /// Fires alongside the individual `WindowListener` callbacks. Useful for
  /// cross-window logging or analytics without needing a `WindowListener`
  /// mixin in every widget.
  void onDialogEvent(int viewId, String eventName) {}
}
