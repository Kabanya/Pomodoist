import 'package:flutter/material.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

/// Internal window manager contract. Public API: `MultiViewDesktop`.
abstract class ViewsManager {
  int realToShiftedId(int viewId);

  int shiftedToRealId(int viewId);

  /// Creates a native window and calls `onCreated` with its real view id.
  Future<int> createWindow({WindowOptions? newOpts, required Future<void> Function(int) onCreated, int? parent});

  /// Creates a dialog for `parentRealId`. See `DialogOptions` and `openDialog`.
  Future<int> createDialog({
    DialogOptions? newOpts,
    required int parentRealId,
    required Future<void> Function(int) onCreated,
  });

  WindowInfo windowType(int viewId);

  Future<void> closeView<T>(int viewId, {T? dialogRes});

  Future<bool> closeApp({CloseMode? closeMode});

  Future<bool> isPreventClose(int viewId);

  Future<void> setPreventClose(int viewId, bool isPreventClose);

  /// Aborts an in-progress `CloseMode.softCascade` waiting on `viewId`.
  Future<void> cancelCascadeClose(int viewId);

  /// Updates the strategy used when the main window close button is pressed.
  Future<void> setAppCloseMode(CloseMode closeMode);

  CloseMode getAppCloseMode();

  bool get isEnabledDynamicAnchor;

  Future<String> getTitle(int viewId);

  Future<void> setTitle(int viewId, String title);

  Future<void> setTitleBarStyle(
    int viewId,
    TitleBarStyle style, {
    bool closeVisibility = true,
    bool maximizeVisibility = true,
    bool minimizeVisibility = true,
  });

  Future<({TitleBarStyle? style, bool? closeVisibility, bool? maximizeVisibility, bool? minimizeVisibility})>
  getTitleBarStyle(int viewId);

  Future<void> setAsFrameless(int viewId);

  /// Sets anchor id. Only for views without parents (root view). Returns `true` if id was set successfully
  Future<bool> setPublicAnchorId(int viewId);

  int? getPublicAnchorId();

  Future<void> setBackgroundColor(int viewId, Color color);

  Future<void> setBrightness(int viewId, Brightness brightness);

  Future<void> setGlobalBrightness(Brightness brightness);

  Future<void> setOpacity(int viewId, double opacity);

  Future<double> getOpacity(int viewId);

  Future<bool> hasShadow(int viewId);

  Future<void> setHasShadow(int viewId, bool value);

  Future<Rect> getBounds(int viewId);

  Future<Size> getSize(int viewId);

  Future<Offset> getPosition(int viewId);

  Future<void> setSize(int viewId, Size size);

  Future<void> setPosition(int viewId, Offset position);

  Future<void> center(int viewId);

  Future<void> setAlignment(int viewId, Alignment alignment, {bool insideParent = false});

  Future<void> setMinimumSize(int viewId, Size size);

  Future<void> setMaximumSize(int viewId, Size size);

  Future<void> setAspectRatio(int viewId, double ratio);

  Future<void> show(int viewId);

  Future<void> hide(int viewId);

  Future<bool> isVisible(int viewId);

  Future<void> focus(int viewId);

  Future<void> blur(int viewId);

  Future<bool> isFocused(int viewId);

  /// macOS: whether the window is on the active Mission Control Space.
  Future<bool> isOnActiveSpace(int viewId);

  Future<bool> isMaximized(int viewId);

  Future<void> maximize(int viewId, {bool vertically = false});

  Future<void> unmaximize(int viewId);

  Future<bool> isMinimized(int viewId);

  Future<void> minimize(int viewId);

  Future<void> restore(int viewId);

  Future<bool> isFullScreen(int viewId);

  Future<void> setFullScreen(int viewId, bool isFullScreen);

  Future<bool> isResizable(int viewId);

  Future<void> setResizable(int viewId, bool isResizable);

  Future<bool> isMovable(int viewId);

  Future<void> setMovable(int viewId, bool isMovable);

  Future<bool> isMinimizable(int viewId);

  Future<void> setMinimizable(int viewId, bool isMinimizable);

  Future<bool> isMaximizable(int viewId);

  Future<void> setMaximizable(int viewId, bool isMaximizable);

  Future<bool> isClosable(int viewId);

  Future<void> setClosable(int viewId, bool isClosable);

  Future<bool> isAlwaysOnTop(int viewId);

  Future<void> setAlwaysOnTop(int viewId, bool isAlwaysOnTop);

  Future<void> setTaskbarMenu({required List<TaskbarMenuItem> items});

  /// App-wide state (macOS activation policy; Windows: all tabs hidden from taskbar).
  Future<bool> isHideAppFromTaskbar();

  /// Per-window taskbar visibility (Windows/Linux).
  Future<bool> isHideAppTabFromTaskbar(int viewId);

  Future<void> hideAppFromTaskbar(bool isHideAppFromTaskbar, {int? viewId});

  Future<void> startDragging(int viewId);

  Future<void> startResizing(int viewId, ResizeEdge edge);

  Future<bool> isHideFromCollection(int viewId);

  Future<void> hideFromCollection(int viewId, bool isHideFromCollection);

  Future<bool> isVisibleOnAllWorkspaces(int viewId);

  Future<void> setVisibleOnAllWorkspaces(int viewId, bool visible, {bool visibleOnFullScreen = false});

  Future<void> setBadgeLabel(int viewId, String? label);

  Future<void> setProgressBar(double progress);

  Future<void> setIgnoreMouseEvents(int viewId, bool ignore, {bool forward = false});

  Future<void> popUpWindowMenu(int viewId);

  Future<({bool mouseMoveEvents, bool ignore})> isIgnoreMouseEvents(int viewId);

  void addListener(int viewId, WindowListenerCallbacks listener);

  void removeListener(int viewId, WindowListenerCallbacks listener);

  void patchViewShell(int viewId, ViewShellOverrides overrides);

  /// Replaces the entry shell overrides for `viewId`, or clears them when null.
  void setViewShellOverrides(int viewId, ViewShellOverrides? overrides);

  /// Returns the current entry shell overrides for `viewId`, if any.
  ViewShellOverrides? getViewShellOverrides(int viewId);
}
