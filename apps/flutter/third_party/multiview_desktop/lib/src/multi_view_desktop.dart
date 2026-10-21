import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:multiview_desktop/src/view_scope.dart';
import 'package:multiview_desktop/src/views_manager.dart';

import 'view_root.dart' show globalRootState;

/// Per-window facade for native window operations.
///
/// Create an instance once per call site and invoke methods on it:
/// ```dart
/// final win = MultiViewDesktop.of(context);
/// await win.setTitle('Settings');
/// await win.setTitleBarStyle(TitleBarStyle.hidden);
///
/// // macOS-only:
/// await win.macos.setVisibleOnAllWorkspaces(true);
/// await win.macos.isOnActiveSpace();
///
/// // Or inline:
/// await MultiViewDesktop.of(context).closeWindow();
/// await MultiViewDesktop.fromId(id).setAlwaysOnTop(true);
/// ```
///
/// App-wide operations that do not target a specific window remain static:
/// ```dart
/// await MultiViewDesktop.closeApp();
/// MultiViewDesktop.addListenerForView(id, listener);
/// ```

/// Snapshot of window kind for a view: whether it is a dialog and whether it is modal.
typedef WindowInfo = ({bool isModal, bool isDialog});

class MultiViewDesktop {
  final int _realId;

  /// Flutter view identifier for per-window native host adapters.
  int get nativeViewId => _realId;

  /// The public view ID for this instance.
  int get id => _manager.realToShiftedId(_realId);

  /// macOS-only window APIs (Spaces, Mission Control, dock badge).
  MultiViewDesktopMacos get macos => MultiViewDesktopMacos(_realId, _manager);

  MultiViewDesktop._({required int realId}) : _realId = realId;

  /// Creates an instance bound to the window that owns `context`.
  factory MultiViewDesktop.of(BuildContext context) => MultiViewDesktop._(realId: _getRealId(context));

  /// Creates an instance bound to the window with the given public `viewId`.
  factory MultiViewDesktop.fromId(int viewId) => MultiViewDesktop._(realId: _manager.shiftedToRealId(viewId));

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  static ViewsManager get _manager => globalRootState.manager;

  static int _getRealId(BuildContext context) => ViewScope.of(context).viewId;

  // ---------------------------------------------------------------------------
  // App-wide: identity
  // ---------------------------------------------------------------------------

  /// In-process message bus shared by all views in this isolate.
  static WindowCommunicator get communicator => globalRootState.communicator;

  /// Returns the public view ID of the window that owns `context`.
  static int getIdByContext(BuildContext context) => _manager.realToShiftedId(_getRealId(context));

  /// Sets the preferred brightness for native chrome on all windows at once.
  /// Does not change Flutter `ThemeData`; use `appShell` for that.
  static Future<void> setGlobalBrightness(Brightness brightness) => _manager.setGlobalBrightness(brightness);

  /// Snapshot of public view IDs for all secondary windows currently open.
  static List<int> get allWindowViewIds => List.unmodifiable(globalRootState.allShiftedViewsId);

  /// Snapshot of public view IDs for all dialogs currently open.
  static List<int> get allDialogViewsIds => List.unmodifiable(globalRootState.dialogsIdsNotif.value);

  /// Live-updating notifier; fires whenever a window opens or closes.
  static ValueNotifier<List<int>> get allWindowIdsNotifier => globalRootState.windowsIdsNotif;

  /// Live-updating notifier; fires whenever a dialog opens or closes.
  static ValueNotifier<List<int>> get allDialogIdsNotifier => globalRootState.dialogsIdsNotif;

  /// Shared entry shell for secondary and dialog views (theme, locale, and similar).
  ///
  /// Update through `AppShellController.patch` from any window. This works after
  /// the main window was closed. While the main window is open, the registry is
  /// also synced from the main `MaterialApp` on each frame.
  static AppShellController get appShell => globalRootState.appShell;

  // ---------------------------------------------------------------------------
  // App-wide: lifecycle
  // ---------------------------------------------------------------------------

  /// Opens a new OS window showing `child`.
  @internal
  static Future<int> addWindow(
    Widget Function(BuildContext context, int publicId) child, {
    WindowOptions? options,
    BuildContext? parent,
  }) async {
    final parentId = parent == null ? null : _getRealId(parent);
    final realId = await _manager.createWindow(
      newOpts: options,
      onCreated: (int newRealId) async {
        globalRootState.addWindowView(
          newRealId,
          (context) => child(context, _manager.realToShiftedId(newRealId)),
          parentContext: parent,
          parentId: parentId,
          shellOverrides: options?.shellOverrides,
        );
      },
      parent: parentId,
    );

    return _manager.realToShiftedId(realId);
  }

  /// Opens a dialog window bound to `parentContext`.
  ///
  /// See `openDialog` for the full documentation.
  @internal
  static Future<T?> addDialog<T>(
    Widget Function(BuildContext context, int publicId) child, {
    required BuildContext parentContext,
    DialogOptions? options,
  }) async {
    final parentRealId = _getRealId(parentContext);
    final completer = Completer<T>();
    await _manager.createDialog(
      newOpts: options,
      parentRealId: parentRealId,
      onCreated: (int newRealId) async {
        globalRootState.addDialogView(
          newRealId,
          (context) => child(context, _manager.realToShiftedId(newRealId)),
          parentContext: parentContext,
          parentId: parentRealId,
          isModalDialog: options?.modal ?? false,
          closeCompleter: completer,
          shellOverrides: options?.shellOverrides,
        );
      },
    );

    return completer.future;
  }

  /// Return `enableDynamicAnchor` from runMultiApp->config->generalParams->enableDynamicAnchor
  static bool get isEnabledDynamicAnchor => _manager.isEnabledDynamicAnchor;

  /// Closes all windows using `closeMode` or the mode set in `MultiAppConfig`.
  /// If all views successfully closed by mode `mode` return `true` else `false`
  static Future<bool> closeApp({CloseMode? closeMode}) async {
    return await _manager.closeApp(closeMode: closeMode);
  }

  /// Changes the strategy used when the main window close button is pressed.
  static Future<void> setCloseMode(CloseMode closeMode) async {
    await _manager.setAppCloseMode(closeMode);
  }

  /// Returns the currently active close mode.
  static CloseMode getCloseMode() => _manager.getAppCloseMode();

  /// Sets the anchor view by public `viewId`. Only valid for root views.
  static Future<bool> setAnchorId(int viewId) async {
    return await _manager.setPublicAnchorId(viewId);
  }

  /// Returns the current anchor view ID, or `null` if none is set.
  static int? getAnchorId() => _manager.getPublicAnchorId();

  // ---------------------------------------------------------------------------
  // App-wide: listeners
  // ---------------------------------------------------------------------------

  /// Subscribes `listener` to events for the window with the given public `publicViewId`.
  static void addListenerForView(int publicViewId, WindowListenerCallbacks listener) {
    _manager.addListener(_manager.shiftedToRealId(publicViewId), listener);
  }

  /// Unsubscribes `listener` from events for the given public `publicViewId`.
  static void removeListenerForView(int publicViewId, WindowListenerCallbacks listener) {
    _manager.removeListener(_manager.shiftedToRealId(publicViewId), listener);
  }

  // ---------------------------------------------------------------------------
  // App-wide: taskbar / dock
  // ---------------------------------------------------------------------------

  /// Returns whether the application icon is hidden from the dock / taskbar app-wide.
  static Future<bool> isHideAppFromTaskbar() async {
    return await _manager.isHideAppFromTaskbar();
  }

  /// Hides or shows the application icon in the dock / taskbar app-wide.
  static Future<void> hideAppFromTaskbar(bool isHideAppFromTaskbar) async {
    await _manager.hideAppFromTaskbar(isHideAppFromTaskbar);
  }

  /// Replaces the entire app taskbar / dock context menu.
  ///
  /// Windows: taskbar jump list tasks (right-click the app icon).
  /// macOS: dock context menu.
  /// Linux: freedesktop `.desktop` Actions in the dock context menu.
  /// Optional [TaskbarMenuItem.iconAsset] on Windows and macOS; Linux uses [TaskbarMenuItem.title] only.
  ///
  /// Each call overwrites previous items. Item callbacks are matched by list index.
  static Future<void> setMenuItems(List<TaskbarMenuItem> items) async {
    await _manager.setTaskbarMenu(items: items);
  }

  // ---------------------------------------------------------------------------
  // App-wide: progress bar
  // ---------------------------------------------------------------------------

  /// Sets the taskbar / dock progress indicator (`0.0` to `1.0`), app-wide.
  static Future<void> setProgressBar(double progress) async {
    await _manager.setProgressBar(progress);
  }

  // ---------------------------------------------------------------------------
  // Per-window: lifecycle
  // ---------------------------------------------------------------------------

  /// Returns whether this view is a dialog and whether it is modal.
  WindowInfo getWindowInfo() {
    return _manager.windowType(_realId);
  }

  /// Soft-closes this window. If `setPreventClose(true)` was set, fires
  /// `WindowListener.onWindowClose` instead of destroying the window.
  Future<void> closeWindow() async {
    await _manager.closeView(_realId);
  }

  /// Closes this dialog and completes the `openDialog` future on the caller side.
  ///
  /// `res` is forwarded to the `await openDialog<T>()` expression. Has no effect
  /// on regular (non-dialog) windows; use `closeWindow` instead.
  Future<void> closeDialog<T>([T? res]) async {
    await _manager.closeView<T>(_realId, dialogRes: res);
  }

  /// Returns whether close is currently blocked for this window.
  Future<bool> isPreventClose() async {
    return await _manager.isPreventClose(_realId);
  }

  /// When `true`, any close attempt is blocked and `WindowListener.onWindowClose`
  /// fires instead. Set back to `false` to re-enable closing.
  Future<void> setPreventClose(bool isPreventClose) async {
    await _manager.setPreventClose(_realId, isPreventClose);
  }

  /// Aborts an in-progress `CloseMode.softCascade` that is waiting on this window.
  Future<void> cancelCascadeClose() async {
    await _manager.cancelCascadeClose(_realId);
  }

  /// Merges `overrides` into this view's entry shell (theme/locale and navigation).
  ///
  /// Appearance fields in `overrides.appearance` are merged on top of the
  /// global `appShell` snapshot. Navigation fields apply only to this view.
  void patchViewShell(ViewShellOverrides overrides) {
    _manager.patchViewShell(_realId, overrides);
  }

  /// Replaces this view's entry shell overrides, or clears them when null.
  void setViewShellOverrides(ViewShellOverrides? overrides) {
    _manager.setViewShellOverrides(_realId, overrides);
  }

  /// Current entry shell overrides for this view, if any.
  ViewShellOverrides? get viewShellOverrides => _manager.getViewShellOverrides(_realId);

  // ---------------------------------------------------------------------------
  // Per-window: title and appearance
  // ---------------------------------------------------------------------------

  /// Returns the native window title.
  Future<String> getTitle() async {
    return await _manager.getTitle(_realId);
  }

  /// Sets the native window title shown in the title bar and dock tooltip.
  Future<void> setTitle(String title) async {
    await _manager.setTitle(_realId, title);
  }

  /// Changes the title-bar style. Pass `TitleBarStyle.hidden` for a frameless window.
  Future<void> setTitleBarStyle(
    TitleBarStyle style, {
    bool closeVisibility = true,
    bool maximizeVisibility = true,
    bool minimizeVisibility = true,
  }) async {
    await _manager.setTitleBarStyle(
      _realId,
      style,
      closeVisibility: closeVisibility,
      maximizeVisibility: maximizeVisibility,
      minimizeVisibility: minimizeVisibility,
    );
  }

  /// Returns the current title-bar style and button visibility.
  Future<({TitleBarStyle? style, bool? closeVisibility, bool? maximizeVisibility, bool? minimizeVisibility})>
  getTitleBarStyle() async {
    return await _manager.getTitleBarStyle(_realId);
  }

  /// Removes the native title bar and border entirely.
  Future<void> setAsFrameless() async {
    await _manager.setAsFrameless(_realId);
  }

  /// Sets the native window background color behind the Flutter view.
  Future<void> setBackgroundColor(Color color) async {
    await _manager.setBackgroundColor(_realId, color);
  }

  /// Sets the preferred appearance for native chrome (light or dark).
  Future<void> setBrightness(Brightness brightness) async {
    await _manager.setBrightness(_realId, brightness);
  }

  /// Sets window opacity in the range `0.0` (transparent) to `1.0` (opaque).
  Future<void> setOpacity(double opacity) async {
    await _manager.setOpacity(_realId, opacity);
  }

  /// Returns the current window opacity.
  Future<double> getOpacity() async {
    return await _manager.getOpacity(_realId);
  }

  /// Returns whether the window draws a native drop shadow.
  Future<bool> hasShadow() async {
    return await _manager.hasShadow(_realId);
  }

  /// Enables or disables the native drop shadow. No-op on Linux.
  Future<void> setHasShadow(bool value) async {
    await _manager.setHasShadow(_realId, value);
  }

  // ---------------------------------------------------------------------------
  // Per-window: size and position
  // ---------------------------------------------------------------------------

  /// Returns the window frame in Flutter logical coordinates (position + size).
  Future<Rect> getBounds() async {
    return await _manager.getBounds(_realId);
  }

  /// Returns the content size in logical pixels.
  Future<Size> getSize() async => (await getBounds()).size;

  /// Returns the top-left position of the window.
  Future<Offset> getPosition() async => (await getBounds()).topLeft;

  /// Resizes the window to `size` in logical pixels.
  Future<void> setSize(Size size) async {
    await _manager.setSize(_realId, size);
  }

  /// Moves the window so its top-left corner is at `position`.
  Future<void> setPosition(Offset position) async {
    await _manager.setPosition(_realId, position);
  }

  /// Centers the window on the screen that contains the largest portion of it.
  Future<void> center() async {
    await _manager.center(_realId);
  }

  /// Positions the window using `alignment` on the display under the cursor.
  Future<void> setAlignment(Alignment alignment) async {
    await _manager.setAlignment(_realId, alignment);
  }

  /// Repositions this dialog within its parent window bounds using `alignment`.
  ///
  /// Only meaningful for dialog views. Regular windows should use `setAlignment`.
  Future<void> setDialogAlignment(Alignment alignment) async {
    await _manager.setAlignment(_realId, alignment, insideParent: true);
  }

  /// Sets the minimum size the user can resize the window to.
  Future<void> setMinimumSize(Size size) async {
    await _manager.setMinimumSize(_realId, size);
  }

  /// Sets the maximum size the user can resize the window to.
  Future<void> setMaximumSize(Size size) async {
    await _manager.setMaximumSize(_realId, size);
  }

  /// Locks the content aspect ratio (width / height). Pass `0` to clear.
  Future<void> setAspectRatio(double ratio) async {
    await _manager.setAspectRatio(_realId, ratio);
  }

  // ---------------------------------------------------------------------------
  // Per-window: visibility and focus
  // ---------------------------------------------------------------------------

  /// Shows the window if it was hidden.
  Future<void> show() async {
    await _manager.show(_realId);
  }

  /// Hides the window without closing it.
  Future<void> hide() async {
    await _manager.hide(_realId);
  }

  /// Returns whether the window is currently visible.
  Future<bool> isVisible() async {
    return await _manager.isVisible(_realId);
  }

  /// Brings the window to the front and gives it keyboard focus.
  Future<void> focus() async {
    await _manager.focus(_realId);
  }

  /// Removes keyboard focus from the window.
  Future<void> blur() async {
    await _manager.blur(_realId);
  }

  /// Returns whether this window is the current focused window.
  Future<bool> isFocused() async {
    return await _manager.isFocused(_realId);
  }

  // ---------------------------------------------------------------------------
  // Per-window: maximize / minimize / full screen
  // ---------------------------------------------------------------------------

  /// Returns whether the window is in the maximized state.
  Future<bool> isMaximized() async {
    return await _manager.isMaximized(_realId);
  }

  /// Maximizes the window.
  ///
  /// When `vertically` is true (Windows only), maximizes to half the screen height.
  Future<void> maximize({bool vertically = false}) async {
    await _manager.maximize(_realId, vertically: vertically);
  }

  /// Restores the window from the maximized state.
  Future<void> unmaximize() async {
    await _manager.unmaximize(_realId);
  }

  /// Returns whether the window is minimized to the dock or taskbar.
  Future<bool> isMinimized() async {
    return await _manager.isMinimized(_realId);
  }

  /// Minimizes the window.
  Future<void> minimize() async {
    await _manager.minimize(_realId);
  }

  /// Restores the window from the minimized state.
  Future<void> restore() async {
    await _manager.restore(_realId);
  }

  /// Returns whether the window is in native full-screen mode.
  Future<bool> isFullScreen() async {
    return await _manager.isFullScreen(_realId);
  }

  /// Enters or exits native full-screen mode.
  Future<void> setFullScreen(bool isFullScreen) async {
    await _manager.setFullScreen(_realId, isFullScreen);
  }

  // ---------------------------------------------------------------------------
  // Per-window: resizability and movability
  // ---------------------------------------------------------------------------

  /// Returns whether the user can resize the window by dragging its edges.
  Future<bool> isResizable() async {
    return await _manager.isResizable(_realId);
  }

  /// Enables or disables user resizing.
  Future<void> setResizable(bool isResizable) async {
    await _manager.setResizable(_realId, isResizable);
  }

  /// Returns whether the window can be moved by dragging the title bar.
  Future<bool> isMovable() async {
    return await _manager.isMovable(_realId);
  }

  /// Enables or disables moving the window by dragging. On Linux maps to `setResizable`.
  Future<void> setMovable(bool isMovable) async {
    await _manager.setMovable(_realId, isMovable);
  }

  /// Returns whether the minimize button is enabled.
  Future<bool> isMinimizable() async {
    return await _manager.isMinimizable(_realId);
  }

  /// Enables or disables the minimize button and action.
  Future<void> setMinimizable(bool isMinimizable) async {
    await _manager.setMinimizable(_realId, isMinimizable);
  }

  /// Returns whether the maximize / zoom button is enabled.
  Future<bool> isMaximizable() async {
    return await _manager.isMaximizable(_realId);
  }

  /// Enables or disables the maximize button and action.
  Future<void> setMaximizable(bool isMaximizable) async {
    await _manager.setMaximizable(_realId, isMaximizable);
  }

  /// Returns whether the close button is enabled.
  Future<bool> isClosable() async {
    return await _manager.isClosable(_realId);
  }

  /// Enables or disables the close button and native close action.
  Future<void> setClosable(bool isClosable) async {
    await _manager.setClosable(_realId, isClosable);
  }

  // ---------------------------------------------------------------------------
  // Per-window: always on top / taskbar
  // ---------------------------------------------------------------------------

  /// Returns whether the window floats above normal application windows.
  Future<bool> isAlwaysOnTop() async {
    return await _manager.isAlwaysOnTop(_realId);
  }

  /// Keeps the window above other windows. On Linux depends on compositor support.
  Future<void> setAlwaysOnTop(bool isAlwaysOnTop) async {
    await _manager.setAlwaysOnTop(_realId, isAlwaysOnTop);
  }

  /// Returns whether this window is hidden from the taskbar (Windows / Linux).
  Future<bool> isHideAppTabFromTaskbar() async {
    return await _manager.isHideAppTabFromTaskbar(_realId);
  }

  /// Hides or shows this window in the taskbar (Windows / Linux).
  Future<void> hideCurrentAppTabFromTaskbar(bool isHide) async {
    await _manager.hideAppFromTaskbar(isHide, viewId: _realId);
  }

  // ---------------------------------------------------------------------------
  // Per-window: drag and resize (used by widgets)
  // ---------------------------------------------------------------------------

  /// Starts a native window-move drag session. Called by `DragToMoveArea`.
  Future<void> startDragging() async {
    await _manager.startDragging(_realId);
  }

  /// Starts a native window-resize drag session from `edge`. Called by `DragToResizeArea`.
  Future<void> startResizing(ResizeEdge edge) async {
    await _manager.startResizing(_realId, edge);
  }

  // ---------------------------------------------------------------------------
  // Per-window: mouse events
  // ---------------------------------------------------------------------------

  /// When `ignore` is `true`, all mouse events pass through the window.
  /// If `mouseMoveEvents` is `true`, mouse move events still arrive.
  Future<void> setIgnoreMouseEvents(bool ignore, {bool mouseMoveEvents = false}) async {
    await _manager.setIgnoreMouseEvents(_realId, ignore, forward: mouseMoveEvents);
  }

  /// Returns the current mouse pass-through state.
  Future<({bool mouseMoveEvents, bool ignore})> isIgnoreMouseEvents() async {
    return await _manager.isIgnoreMouseEvents(_realId);
  }

  /// Shows the native window context menu at the current cursor position.
  Future<void> popUpWindowMenu() async {
    await _manager.popUpWindowMenu(_realId);
  }
}
