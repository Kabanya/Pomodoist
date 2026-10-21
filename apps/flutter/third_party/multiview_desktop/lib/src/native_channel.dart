import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

import 'utils/calc_window_position.dart';

// MethodChannel method names (must match native MultiviewDesktopImpl).
const String kMethodCreateWindow = 'createWindow';
const String kMethodCreateModalDialog = 'createModalDialog';
const String kMethodSetSize = 'setSize';
const String kMethodSetMinimumSize = 'setMinimumSize';
const String kMethodSetMaximumSize = 'setMaximumSize';
const String kMethodGetBounds = 'getBounds';
const String kMethodSetPosition = 'setPosition';
const String kMethodSetBackgroundColor = 'setBackgroundColor';
const String kMethodSetTitle = 'setTitle';
const String kMethodGetTitle = 'getTitle';
const String kMethodSetTitleBarStyle = 'setTitleBarStyle';
const String kMethodGetTitleBarStyle = 'getTitleBarStyle';
const String kMethodSetAsFrameless = 'setAsFrameless';
const String kMethodSetAlwaysOnTop = 'setAlwaysOnTop';
const String kMethodSetFullScreen = 'setFullScreen';
const String kMethodHideAppFromTaskbar = 'hideAppFromTaskbar';
const String kMethodCloseWindow = 'closeWindow';
const String kMethodDestroyWindow = 'destroyWindow';
const String kMethodFocus = 'focus';
const String kMethodPreConfirmClose = 'preConfirmClose';
const String kMethodConfirmClose = 'confirmClose';
const String kMethodSetPreventClose = 'setPreventClose';
const String kMethodIsPreventClose = 'isPreventClose';
const String kMethodSetBrightness = 'setBrightness';
const String kMethodSetOpacity = 'setOpacity';
const String kMethodGetOpacity = 'getOpacity';
const String kMethodHasShadow = 'hasShadow';
const String kMethodSetHasShadow = 'setHasShadow';
const String kMethodSetAspectRatio = 'setAspectRatio';
const String kMethodShow = 'show';
const String kMethodHide = 'hide';
const String kMethodIsVisible = 'isVisible';
const String kMethodBlur = 'blur';
const String kMethodIsFocused = 'isFocused';
const String kMethodIsOnActiveSpace = 'isOnActiveSpace';
const String kMethodIsMaximized = 'isMaximized';
const String kMethodMaximize = 'maximize';
const String kMethodUnmaximize = 'unmaximize';
const String kMethodIsMinimized = 'isMinimized';
const String kMethodMinimize = 'minimize';
const String kMethodRestore = 'restore';
const String kMethodIsFullScreen = 'isFullScreen';
const String kMethodIsResizable = 'isResizable';
const String kMethodSetResizable = 'setResizable';
const String kMethodIsMovable = 'isMovable';
const String kMethodSetMovable = 'setMovable';
const String kMethodIsMinimizable = 'isMinimizable';
const String kMethodSetMinimizable = 'setMinimizable';
const String kMethodIsMaximizable = 'isMaximizable';
const String kMethodSetMaximizable = 'setMaximizable';
const String kMethodIsClosable = 'isClosable';
const String kMethodSetClosable = 'setClosable';
const String kMethodIsAlwaysOnTop = 'isAlwaysOnTop';
const String kMethodIsHideAppFromTaskbar = 'isHideAppFromTaskbar';
const String kMethodIsHideAppTabFromTaskbar = 'isHideAppTabFromTaskbar';
const String kMethodStartDragging = 'startDragging';
const String kMethodStartResizing = 'startResizing';
const String kMethodIsHideFromCollection = 'isHideFromCollection';
const String kMethodHideFromCollection = 'hideFromCollection';
const String kMethodIsVisibleOnAllWorkspaces = 'isVisibleOnAllWorkspaces';
const String kMethodSetVisibleOnAllWorkspaces = 'setVisibleOnAllWorkspaces';
const String kMethodSetBadgeLabel = 'setBadgeLabel';
const String kMethodSetProgressBar = 'setProgressBar';
const String kMethodSetTaskbarMenu = 'setTaskbarMenu';
const String kMethodSetIgnoreMouseEvents = 'setIgnoreMouseEvents';
const String kMethodIsIgnoreMouseEvents = 'isIgnoreMouseEvents';
const String kMethodPopUpWindowMenu = 'popUpWindowMenu';
const String kMethodSetTerminateAfterLastWindowClosed = 'setTerminateAfterLastWindowClosed';
const String kMethodSetAnchorViewId = 'setAnchorViewId';
const String kMethodCheckExist = 'checkExistViewId';
const String kMethodApplicationShouldTerminateResponse = 'applicationShouldTerminateResponse';
const String kMethodSetHasTaskbarCallback = 'setHasTaskbarCallback';

/// MethodChannel wrapper for the `multiview_desktop` plugin.
/// Per-window calls include `viewId` in the arguments.
class NativeChannel {
  static const MethodChannel _staticChannel = MethodChannel('multiview_desktop');

  static Map<String, dynamic> _args(int viewId, [Map<String, dynamic>? extra]) {
    final map = <String, dynamic>{'viewId': viewId};
    if (extra != null) map.addAll(extra);
    return map;
  }

  /// Native -> Dart events (`onEvent`, etc.).
  void setMethodCallHandler(Future<dynamic> Function(MethodCall) handler) =>
      _staticChannel.setMethodCallHandler(handler);

  /// Creates a window; finished when native sends `viewCreated`.
  Future<void> createWindowRequest({
    required int token,
    bool focusOnShow = true,
    required String title,
    required String titleBarStyleStr,
    required bool windowButtonVisibility,
    required Size windowSize,
    required Offset? pos,
    int? parentId,
  }) async {
    await _staticChannel.invokeMethod<void>(kMethodCreateWindow, {
      'token': token,
      'focusOnShow': focusOnShow,
      'width': windowSize.width,
      'height': windowSize.height,
      'title': title,
      'position': pos == null ? null : {'x': pos.dx, 'y': pos.dy},
      'titleBarStyle': titleBarStyleStr,
      'windowButtonVisibility': windowButtonVisibility,
      'parentId': ?parentId,
    });
  }

  /// Creates a dialog attached to `parentId`.
  ///
  /// Modal behavior is platform-specific (macOS sheet, Windows owner chain,
  /// Linux transient window with parent input lock). The native side sends
  /// `viewCreated` when the dialog is ready, same as `createWindowRequest`.
  Future<void> createModalDialogRequest({
    required int token,
    required String title,
    required String titleBarStyleStr,
    required bool windowButtonVisibility,
    required Size windowSize,
    required Offset? pos,
    required int parentId,
    required bool isModal,
  }) async {
    await _staticChannel.invokeMethod<void>(kMethodCreateModalDialog, {
      'token': token,
      'width': windowSize.width,
      'height': windowSize.height,
      'title': title,
      'position': pos == null ? null : {'x': pos.dx, 'y': pos.dy},
      'modal': isModal,
      'titleBarStyle': titleBarStyleStr,
      'windowButtonVisibility': windowButtonVisibility,
      'parentId': parentId,
    });
  }

  Future<bool?> checkWindowExist(int viewId) async {
    return await _staticChannel.invokeMethod<bool>(kMethodCheckExist, _args(viewId));
  }

  Future<void> setAnchorViewId(int viewId) async {
    await _staticChannel.invokeMethod<void>(kMethodSetAnchorViewId, _args(viewId));
  }

  Future<void> setSize(int viewId, {required Size size}) async {
    await _staticChannel.invokeMethod<void>(
      kMethodSetSize,
      _args(viewId, {'width': size.width, 'height': size.height}),
    );
  }

  Future<void> setMinSize(int viewId, {required Size size}) async {
    await _staticChannel.invokeMethod<void>(
      kMethodSetMinimumSize,
      _args(viewId, {'width': size.width, 'height': size.height}),
    );
  }

  Future<void> setMaxSize(int viewId, {required Size size}) async {
    await _staticChannel.invokeMethod<void>(
      kMethodSetMaximumSize,
      _args(viewId, {'width': size.width, 'height': size.height}),
    );
  }

  Future<void> setAlignment(int viewId, {required Alignment alignment}) async {
    final pos = await _calculateOffFromAlign(viewId, alignment: alignment);
    if (pos != null) {
      await setPosition(viewId, pos: pos);
    }
  }

  Future<Offset?> _calculateOffFromAlign(int viewId, {required Alignment alignment}) async {
    final sizeResult = await _staticChannel.invokeMethod<Map>(kMethodGetBounds, _args(viewId));
    if (sizeResult != null) {
      final windowSize = Size((sizeResult['width'] as num).toDouble(), (sizeResult['height'] as num).toDouble());
      return calcWindowPosition(windowSize, alignment);
    }
    return null;
  }

  Future<void> setPosition(int viewId, {required Offset pos}) async =>
      await _staticChannel.invokeMethod<void>(kMethodSetPosition, _args(viewId, {'x': pos.dx, 'y': pos.dy}));

  Future<Rect> getBounds(int viewId) async {
    final Map<dynamic, dynamic> r = await _staticChannel.invokeMethod(kMethodGetBounds, _args(viewId));
    return Rect.fromLTWH(
      (r['x'] as num).toDouble(),
      (r['y'] as num).toDouble(),
      (r['width'] as num).toDouble(),
      (r['height'] as num).toDouble(),
    );
  }

  Future<void> setBackgroundColor(int viewId, {required Color color}) async {
    await _staticChannel.invokeMethod<void>(
      kMethodSetBackgroundColor,
      _args(viewId, {
        'backgroundColorA': (color.a * 255).round(),
        'backgroundColorR': (color.r * 255).round(),
        'backgroundColorG': (color.g * 255).round(),
        'backgroundColorB': (color.b * 255).round(),
      }),
    );
  }

  Future<void> setTitle(int viewId, {required String title}) async {
    await _staticChannel.invokeMethod<void>(kMethodSetTitle, _args(viewId, {'title': title}));
  }

  Future<String> getTitle(int viewId) async {
    return await _staticChannel.invokeMethod<String>(kMethodGetTitle, _args(viewId)) ?? '';
  }

  Future<void> setTitleBarStyle(
    int viewId, {
    required TitleBarStyle style,
    required bool closeVisibility,
    required bool maximizeVisibility,
    required bool minimizeVisibility,
  }) async {
    await _staticChannel.invokeMethod<void>(
      kMethodSetTitleBarStyle,
      _args(viewId, {
        'titleBarStyle': style.name,
        'closeVisibility': closeVisibility,
        'maximizeVisibility': maximizeVisibility,
        'minimizeVisibility': minimizeVisibility,
      }),
    );
  }

  Future<({TitleBarStyle? style, bool? closeVisibility, bool? maximizeVisibility, bool? minimizeVisibility})>
  getTitleBarStyle(int viewId) async {
    final mapResult = await _staticChannel.invokeMethod<Map<Object?, Object?>>(kMethodGetTitleBarStyle, _args(viewId));

    return (
      style: _barStyleFromJson(mapResult?['style'] as String?),
      closeVisibility: mapResult?['closeVisibility'] as bool?,
      maximizeVisibility: mapResult?['maximizeVisibility'] as bool?,
      minimizeVisibility: mapResult?['minimizeVisibility'] as bool?,
    );
  }

  Future<void> setAsFrameless(int viewId) async {
    await _staticChannel.invokeMethod<void>(kMethodSetAsFrameless, _args(viewId));
  }

  TitleBarStyle _barStyleFromJson(String? styleStr) {
    if (styleStr == 'hidden') return TitleBarStyle.hidden;
    return TitleBarStyle.normal;
  }

  Future<void> setAlwaysOnTop(int viewId, {required bool isAlwaysOnTop}) async {
    await _staticChannel.invokeMethod<void>(kMethodSetAlwaysOnTop, _args(viewId, {'isAlwaysOnTop': isAlwaysOnTop}));
  }

  Future<void> setFullScreen(int viewId, {required bool isFullScreen}) async {
    await _staticChannel.invokeMethod<void>(kMethodSetFullScreen, _args(viewId, {'isFullScreen': isFullScreen}));
  }

  Future<void> hideAppFromTaskbar(int viewId, {required bool isHideAppFromTaskbar}) async {
    await _staticChannel.invokeMethod<void>(
      kMethodHideAppFromTaskbar,
      _args(viewId, {'isHideAppFromTaskbar': isHideAppFromTaskbar}),
    );
  }

  /// Soft-close (prevent / confirm flow).
  Future<void> softCloseWindow(int viewId) async {
    await _staticChannel.invokeMethod<void>(kMethodCloseWindow, _args(viewId));
  }

  /// Clears close flags, then `softCloseWindow`.
  Future<void> forceCloseView(int viewId) async {
    // await setPreConfirmClose(viewId, true);
    await setPreventClose(viewId, isPreventClose: false);
    await softCloseWindow(viewId);
  }

  /// Force-destroys the window, skipping the soft-close cycle.
  /// On macOS, modal sheets call `endSheet` before the window is destroyed.
  Future<void> destroyModalDialog(int viewId) async {
    await _staticChannel.invokeMethod<void>(kMethodDestroyWindow, _args(viewId));
  }

  Future<void> focus(int viewId) async {
    await _staticChannel.invokeMethod<void>(kMethodFocus, _args(viewId));
  }

  Future<void> setPreConfirmClose(int viewId, bool isPreConfirm) async {
    return _staticChannel.invokeMethod<void>(kMethodPreConfirmClose, _args(viewId, {'preConfirmClose': isPreConfirm}));
  }

  Future<void> setConfirmClose(int viewId, {required bool isConfirm}) async =>
      await _staticChannel.invokeMethod<void>(kMethodConfirmClose, _args(viewId, {'confirmClose': isConfirm}));

  Future<void> setPreventClose(int viewId, {required bool isPreventClose}) async => await _staticChannel
      .invokeMethod<void>(kMethodSetPreventClose, _args(viewId, {'isPreventClose': isPreventClose}));

  Future<bool> isPreventClose(int viewId) async {
    return await _staticChannel.invokeMethod<bool>(kMethodIsPreventClose, _args(viewId)) ?? false;
  }

  Future<void> setBrightness(int viewId, Brightness brightness) async {
    await _staticChannel.invokeMethod<void>(kMethodSetBrightness, _args(viewId, {'brightness': brightness.name}));
  }

  Future<void> setOpacity(int viewId, double opacity) async {
    await _staticChannel.invokeMethod<void>(kMethodSetOpacity, _args(viewId, {'opacity': opacity}));
  }

  Future<double> getOpacity(int viewId) async {
    return await _staticChannel.invokeMethod<double>(kMethodGetOpacity, _args(viewId)) ?? 1.0;
  }

  Future<bool> hasShadow(int viewId) async {
    return await _staticChannel.invokeMethod<bool>(kMethodHasShadow, _args(viewId)) ?? true;
  }

  Future<void> setHasShadow(int viewId, bool value) async {
    await _staticChannel.invokeMethod<void>(kMethodSetHasShadow, _args(viewId, {'hasShadow': value}));
  }

  Future<Size> getSize(int viewId) async => (await getBounds(viewId)).size;

  Future<Offset> getPosition(int viewId) async => (await getBounds(viewId)).topLeft;

  Future<void> setAspectRatio(int viewId, double ratio) async {
    await _staticChannel.invokeMethod<void>(kMethodSetAspectRatio, _args(viewId, {'aspectRatio': ratio}));
  }

  Future<void> show(int viewId) async {
    await _staticChannel.invokeMethod<void>(kMethodShow, _args(viewId));
  }

  Future<void> hide(int viewId) async {
    await _staticChannel.invokeMethod<void>(kMethodHide, _args(viewId));
  }

  Future<bool> isVisible(int viewId) async {
    return await _staticChannel.invokeMethod<bool>(kMethodIsVisible, _args(viewId)) ?? true;
  }

  Future<void> blur(int viewId) async {
    await _staticChannel.invokeMethod<void>(kMethodBlur, _args(viewId));
  }

  Future<bool> isFocused(int viewId) async {
    return await _staticChannel.invokeMethod<bool>(kMethodIsFocused, _args(viewId)) ?? false;
  }

  /// macOS Spaces: whether the window is on the currently active desktop.
  /// Other platforms always return `true`.
  Future<bool> isOnActiveSpace(int viewId) async {
    return await _staticChannel.invokeMethod<bool>(kMethodIsOnActiveSpace, _args(viewId)) ?? true;
  }

  Future<bool> isMaximized(int viewId) async {
    return await _staticChannel.invokeMethod<bool>(kMethodIsMaximized, _args(viewId)) ?? false;
  }

  Future<void> maximize(int viewId, {bool vertically = false}) async {
    await _staticChannel.invokeMethod<void>(kMethodMaximize, _args(viewId, {'vertically': vertically}));
  }

  Future<void> unmaximize(int viewId) async {
    await _staticChannel.invokeMethod<void>(kMethodUnmaximize, _args(viewId));
  }

  Future<bool> isMinimized(int viewId) async {
    return await _staticChannel.invokeMethod<bool>(kMethodIsMinimized, _args(viewId)) ?? false;
  }

  Future<void> minimize(int viewId) async {
    await _staticChannel.invokeMethod<void>(kMethodMinimize, _args(viewId));
  }

  Future<void> restore(int viewId) async {
    await _staticChannel.invokeMethod<void>(kMethodRestore, _args(viewId));
  }

  Future<bool> isFullScreen(int viewId) async {
    return await _staticChannel.invokeMethod<bool>(kMethodIsFullScreen, _args(viewId)) ?? false;
  }

  Future<bool> isResizable(int viewId) async {
    return await _staticChannel.invokeMethod<bool>(kMethodIsResizable, _args(viewId)) ?? true;
  }

  Future<void> setResizable(int viewId, bool isResizable) async {
    await _staticChannel.invokeMethod<void>(kMethodSetResizable, _args(viewId, {'isResizable': isResizable}));
  }

  Future<bool> isMovable(int viewId) async {
    return await _staticChannel.invokeMethod<bool>(kMethodIsMovable, _args(viewId)) ?? true;
  }

  Future<void> setMovable(int viewId, bool isMovable) async {
    await _staticChannel.invokeMethod<void>(kMethodSetMovable, _args(viewId, {'isMovable': isMovable}));
  }

  Future<bool> isMinimizable(int viewId) async {
    return await _staticChannel.invokeMethod<bool>(kMethodIsMinimizable, _args(viewId)) ?? true;
  }

  Future<void> setMinimizable(int viewId, bool isMinimizable) async {
    await _staticChannel.invokeMethod<void>(kMethodSetMinimizable, _args(viewId, {'isMinimizable': isMinimizable}));
  }

  Future<bool> isMaximizable(int viewId) async {
    return await _staticChannel.invokeMethod<bool>(kMethodIsMaximizable, _args(viewId)) ?? true;
  }

  Future<void> setMaximizable(int viewId, bool isMaximizable) async {
    await _staticChannel.invokeMethod<void>(kMethodSetMaximizable, _args(viewId, {'isMaximizable': isMaximizable}));
  }

  Future<bool> isClosable(int viewId) async {
    return await _staticChannel.invokeMethod<bool>(kMethodIsClosable, _args(viewId)) ?? true;
  }

  Future<void> setClosable(int viewId, bool isClosable) async {
    await _staticChannel.invokeMethod<void>(kMethodSetClosable, _args(viewId, {'isClosable': isClosable}));
  }

  Future<bool> isAlwaysOnTop(int viewId) async {
    return await _staticChannel.invokeMethod<bool>(kMethodIsAlwaysOnTop, _args(viewId)) ?? false;
  }

  /// macOS: activation policy. Windows: all windows taskbar-hidden.
  Future<bool> isHideAppFromTaskbar() async {
    final res = await _staticChannel.invokeMethod(kMethodIsHideAppFromTaskbar);
    return res ?? false;
  }

  /// Per-window taskbar visibility (Windows/Linux).
  Future<bool> isHideAppTabFromTaskbar(int viewId) async {
    final res = await _staticChannel.invokeMethod<bool>(kMethodIsHideAppTabFromTaskbar, _args(viewId));
    return res ?? false;
  }

  Future<void> startDragging(int viewId) async {
    await _staticChannel.invokeMethod<void>(kMethodStartDragging, _args(viewId));
  }

  Future<void> startResizing(int viewId, ResizeEdge edge) async {
    await _staticChannel.invokeMethod<void>(
      kMethodStartResizing,
      _args(viewId, {
        'resizeEdge': edge.name,
        'top': edge == ResizeEdge.top || edge == ResizeEdge.topLeft || edge == ResizeEdge.topRight,
        'bottom': edge == ResizeEdge.bottom || edge == ResizeEdge.bottomLeft || edge == ResizeEdge.bottomRight,
        'right': edge == ResizeEdge.right || edge == ResizeEdge.topRight || edge == ResizeEdge.bottomRight,
        'left': edge == ResizeEdge.left || edge == ResizeEdge.topLeft || edge == ResizeEdge.bottomLeft,
      }),
    );
  }

  Future<bool> isHideFromCollection(int viewId) async {
    return await _staticChannel.invokeMethod<bool>(kMethodIsHideFromCollection, _args(viewId)) ?? false;
  }

  Future<void> hideFromCollection(int viewId, bool isHideFromCollection) async {
    await _staticChannel.invokeMethod<void>(
      kMethodHideFromCollection,
      _args(viewId, {'isHideFromCollection': isHideFromCollection}),
    );
  }

  Future<bool> isVisibleOnAllWorkspaces(int viewId) async {
    return await _staticChannel.invokeMethod<bool>(kMethodIsVisibleOnAllWorkspaces, _args(viewId)) ?? false;
  }

  Future<void> setVisibleOnAllWorkspaces(int viewId, bool visible, {bool visibleOnFullScreen = false}) async {
    await _staticChannel.invokeMethod<void>(
      kMethodSetVisibleOnAllWorkspaces,
      _args(viewId, {'visible': visible, 'visibleOnFullScreen': visibleOnFullScreen}),
    );
  }

  Future<void> setBadgeLabel(int viewId, {required String? label}) async {
    await _staticChannel.invokeMethod<void>(kMethodSetBadgeLabel, _args(viewId, {'label': label ?? ''}));
  }

  Future<void> setProgressBar(double progress) async {
    await _staticChannel.invokeMethod<void>(kMethodSetProgressBar, {'progress': progress});
  }

  Future<void> setTaskbarMenu(List<Map<String, dynamic>> items) async {
    await _staticChannel.invokeMethod<void>(kMethodSetTaskbarMenu, {'items': items});
  }

  Future<void> setIgnoreMouseEvents(int viewId, bool ignore, {bool forward = false}) async {
    await _staticChannel.invokeMethod<void>(
      kMethodSetIgnoreMouseEvents,
      _args(viewId, {'ignore': ignore, 'forward': forward}),
    );
  }

  Future<({bool mouseMoveEvents, bool ignore})> isIgnoreMouseEvents(int viewId) async {
    final resMap = await _staticChannel.invokeMethod<Map>(kMethodIsIgnoreMouseEvents, _args(viewId));

    return (mouseMoveEvents: resMap?['forward'] as bool? ?? false, ignore: resMap?['ignore'] as bool? ?? false);
  }

  Future<void> popUpWindowMenu(int viewId) async {
    await _staticChannel.invokeMethod<void>(kMethodPopUpWindowMenu, _args(viewId));
  }

  /// macOS quit-after-last-window policy.
  Future<void> setTerminateAfterLastWindowClosed(bool terminate) async {
    await _staticChannel.invokeMethod<void>(kMethodSetTerminateAfterLastWindowClosed, {
      'terminateAfterLastWindowClosed': terminate,
    });
  }

  Future<void> replyToApplicationShouldTerminate(bool terminate) async {
    await _staticChannel.invokeMethod<void>(kMethodApplicationShouldTerminateResponse, {'terminate': terminate});
  }

  Future<void> setHasTaskbarCallback(bool hasCallback) async {
    await _staticChannel.invokeMethod<void>(kMethodSetHasTaskbarCallback, {'hasTaskbarCallback': hasCallback});
  }

  /// Resets close flags and related state after hot restart when the OS window
  /// survived. Title, size, and position are left unchanged.
  Future<void> resetWindowToDefaults(int viewId, MultiAppConfig config) async {
    await Future.wait([
      setPreventClose(viewId, isPreventClose: false),
      setPreConfirmClose(viewId, false),
      setConfirmClose(viewId, isConfirm: false),
      setResizable(viewId, true),
      setMovable(viewId, true),
      setMinimizable(viewId, true),
      setMaximizable(viewId, true),
      setClosable(viewId, true),
      setAlwaysOnTop(viewId, isAlwaysOnTop: config.globalOptions.alwaysOnTop ?? false),
      setOpacity(viewId, 1.0),
      setAspectRatio(viewId, 0),
      setIgnoreMouseEvents(viewId, false),
      setTitleBarStyle(
        viewId,
        style: config.globalOptions.titleBarStyle ?? TitleBarStyle.normal,
        closeVisibility: config.globalOptions.windowButtonVisibility ?? false,
        minimizeVisibility: config.globalOptions.windowButtonVisibility ?? false,
        maximizeVisibility: config.globalOptions.windowButtonVisibility ?? false,
      ),
    ]);
  }
}
