import 'package:flutter/material.dart';

import 'app_shell/view_shell_overrides.dart';
import 'title_bar_style.dart';

/// Pass to `openWindow` to control initial appearance and position.
class WindowOptions {
  const WindowOptions({
    this.size,
    this.focusOnShow,
    this.isUtility = false,
    this.linuxDesktopOverlay = false,
    this.linuxDesktopOverlayRole = 'companion',
    this.minimumSize,
    this.maximumSize,
    this.alignment = Alignment.center,
    this.backgroundColor,
    this.hideAppFromTaskbar,
    this.titleBarStyle,
    this.windowButtonVisibility,
    this.title,
    this.fullScreen,
    this.alwaysOnTop,
    this.shellOverrides,
  });

  /// Initial content size in logical pixels. Defaults to 800x600 when omitted.
  final Size? size;

  /// False creates a hidden window and shows it without activation on show().
  final bool? focusOnShow;

  /// Utility windows never replace the main app anchor.
  final bool isUtility;

  /// Configures a Linux companion before realization: an X11 utility window
  /// or a Wayland layer surface. Requires [isUtility]; defaults to disabled.
  final bool linuxDesktopOverlay;

  /// Immutable overlay identity, independent of title and activation policy.
  /// Supported roles are `companion` and `settings`.
  final String linuxDesktopOverlayRole;

  /// Minimum resizable size enforced by the OS window.
  final Size? minimumSize;

  /// Maximum resizable size enforced by the OS window.
  final Size? maximumSize;

  /// Where to place the window on the display under the cursor (or primary).
  final Alignment? alignment;

  /// Native window background color shown behind Flutter content.
  final Color? backgroundColor;

  /// When `true`, hides the entire application icon from the dock / taskbar.
  final bool? hideAppFromTaskbar;

  /// Initial title-bar style; use `TitleBarStyle.hidden` for frameless chrome.
  final TitleBarStyle? titleBarStyle;

  /// Whether traffic-light / caption buttons are visible when the bar is hidden.
  final bool? windowButtonVisibility;

  /// Native window title string.
  final String? title;

  /// Whether the window starts in full-screen mode.
  final bool? fullScreen;

  /// Whether the window stays above other application windows.
  final bool? alwaysOnTop;

  /// Per-view overrides merged on top of `MultiViewDesktop.appShell`.
  ///
  /// Set `ViewShellOverrides.appearance` for theme or locale on this window only.
  /// Set `ViewShellOverrides.routerConfig`, `ViewShellOverrides.home`, or `routes`
  /// for a dedicated navigator or router stack on this view.
  final ViewShellOverrides? shellOverrides;
}
