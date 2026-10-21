import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import 'multi_view_desktop.dart';
import 'title_bar_style.dart';
import 'view_root.dart' show createMultiViewRoot;
import 'window_observer.dart';
import 'taskbar_menu_item.dart';
import 'window_options.dart';
import 'app_shell/view_shell_overrides.dart';

/// Entry point for a multiview_desktop application.
///
/// Replaces `runApp`. Internally calls `runWidget` with a `ViewCollection` root
/// that manages every OS window in a single Flutter engine and isolate.
///
/// Returns nothing; the call does not complete until the process exits.
///
/// ```dart
/// void main() {
///   runMultiApp(
///     home: (context, id) => MyHomeScreen(),
///   );
/// }
/// ```
///
/// `home` is rendered in the initial (main) OS window. Additional windows are
/// opened via `openWindow`.
void runMultiApp({
  required Widget Function(BuildContext globalScopeContext, int publicId) home,
  Widget Function(Widget child)? globalScope,
  MultiAppConfig? config,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  runWidget(await createMultiViewRoot(home, globalScope, config ?? MultiAppConfig._defaultConfig()));
}

/// Application-wide settings passed to `runMultiApp`.
class MultiAppConfig {
  /// Cross-platform behavior (anchor, close mode). See `MultiPlatformParams`.
  final MultiPlatformParams generalParams;

  /// macOS-specific lifecycle options. See `MacosPlatformParams`.
  final MacosPlatformParams macosParams;

  /// Default `WindowOptions` merged into every new window. Per-window options
  /// passed to `openWindow` override these fields.
  final WindowOptions globalOptions;

  /// Default `DialogOptions` merged into every `openDialog` call.
  final DialogOptions globalDialogOptions;

  /// Observers notified when windows or dialogs open, close, or when the
  /// anchor changes. See `WindowObserver`.
  ///
  /// ```dart
  /// config: MultiAppConfig(
  ///   observers: [MyWindowObserver()],
  /// )
  /// ```
  final List<WindowObserver> observers;

  MultiAppConfig._({
    required this.generalParams,
    required this.macosParams,
    this.globalOptions = const WindowOptions(),
    this.globalDialogOptions = const DialogOptions(),
    this.observers = const [],
  });

  /// Creates configuration for `runMultiApp`.
  ///
  /// `generalParams` controls anchor promotion and `CloseMode`.
  /// `macosParams` controls macOS dock and last-window behavior.
  /// `globalWindowOptions` apply to the main window at startup and merge into
  /// each `openWindow` call.
  /// `globalDialogOptions` merge into each `openDialog` call.
  /// `observers` receive passive lifecycle callbacks.
  factory MultiAppConfig({
    MultiPlatformParams? generalParams,
    MacosPlatformParams? macosParams,
    WindowOptions? globalWindowOptions,
    DialogOptions? globalDialogOptions,
    List<WindowObserver>? observers,
  }) => MultiAppConfig._(
    globalOptions: globalWindowOptions ?? WindowOptions(),
    globalDialogOptions: globalDialogOptions ?? DialogOptions(),
    generalParams: generalParams ?? MultiPlatformParams.defaultParams(),
    macosParams: macosParams ?? MacosPlatformParams.defaultParams(),
    observers: observers ?? const [],
  );

  factory MultiAppConfig._defaultConfig() => MultiAppConfig._(
    generalParams: MultiPlatformParams.defaultParams(),
    macosParams: MacosPlatformParams.defaultParams(),
  );
}

/// Cross-platform parameters for `MultiAppConfig.generalParams`.
class MultiPlatformParams {
  /// When true, the library promotes another root window to anchor when the
  /// current anchor closes. When false, anchor must be set manually.
  final bool enableDynamicAnchor;

  /// Default strategy when the main window close button is pressed.
  /// Can be changed at runtime via `MultiViewDesktop.setCloseMode`.
  final CloseMode closeMode;

  /// Initial taskbar / dock / jump list menu items.
  /// Replaced entirely by `MultiViewDesktop.setMenuItems`.
  final List<TaskbarMenuItem> menuItems;

  const MultiPlatformParams({
    this.enableDynamicAnchor = true,
    this.closeMode = CloseMode.softCascade,
    this.menuItems = const [],
  });

  /// Default: dynamic anchor enabled, `CloseMode.softCascade`.
  factory MultiPlatformParams.defaultParams() =>
      MultiPlatformParams(enableDynamicAnchor: true, closeMode: CloseMode.softCascade);
}

/// macOS-specific parameters for `MultiAppConfig.macosParams`.
class MacosPlatformParams {
  /// When true, quitting after the last window closes terminates the process.
  ///
  /// Is not included if:
  /// - `saveLastWindowToReopen` is true
  final bool closeAppAfterLastWindowClosed;

  /// When true, the last closed window with `closeWindow` or native cross will be hide instead of close and may be restored by tap on app icon
  ///
  /// Is not included if:
  /// - call `closeApp`
  /// - onTerminate
  /// - window close mode is `destroy`
  final bool saveLastWindowToReopen;

  /// Callback on `cmd+q` shortcut. Return true to close, false to skip
  final Future<bool> Function()? onTerminate;

  /// Called when the user clicks the dock icon.
  final Function? onTaskbarTap;

  const MacosPlatformParams({
    this.closeAppAfterLastWindowClosed = true,
    this.saveLastWindowToReopen = true,
    this.onTaskbarTap,
    this.onTerminate,
  });

  factory MacosPlatformParams.defaultParams() => MacosPlatformParams(saveLastWindowToReopen: true, onTaskbarTap: null);
}

/// How closing the main window affects other open windows.
enum CloseMode {
  /// Only the main window goes through the soft-close cycle (prevent-close,
  /// confirm dialog, destroy). Secondary windows stay open.
  ///
  /// Experimental, does not guarantee proper operation.
  @experimental
  none,

  /// Soft-closes secondary windows one by one (newest first), then the main
  /// window. Each window runs the full close cycle. Abort from a confirmation
  /// dialog with `MultiViewDesktop.cancelCascadeClose`.
  softCascade,

  /// Force-closes all secondary windows immediately, then soft-closes the main
  /// window.
  forceSecondary,

  /// Force-closes every window without the soft-close cycle.
  destroy,

  /// macOS only: hide the last root window instead of destroying it so the app
  /// stays in the dock. Requires the corresponding hook in AppDelegate.
  // macos,
}

/// Opens a new OS window showing `childBuilder`.
///
/// Returns the public view id of the new window when creation finishes.
///
/// Convenience wrapper around `MultiViewDesktop.addWindow`. Can be called from
/// anywhere (timers, isolates callbacks, services) without a `BuildContext`.
///
/// ```dart
/// ElevatedButton(
///   onPressed: () => openWindow(
///     (context, viewId) => const SettingsPage(),
///     options: WindowOptions(title: 'Settings'),
///   ),
///   child: const Text('Open settings'),
/// )
/// ```
Future<int> openWindow(
  Widget Function(BuildContext context, int publicId) childBuilder, {
  WindowOptions? options,
  BuildContext? parentContext,
}) => MultiViewDesktop.addWindow(childBuilder, options: options, parent: parentContext);

/// Configuration for a dialog opened via `openDialog`.
///
/// Dialogs differ from regular windows:
/// - They always require a parent (`openDialog` needs `parentContext`).
/// - They close automatically when the parent closes, regardless of `CloseMode`.
/// - Full-screen mode is not available.
/// - They are hidden from the taskbar and Mission Control on creation.
/// - They are centered over the parent at creation time.
///
/// Set `modal` to true to block the parent at the OS level while the dialog is
/// open. Add `DialogModalLayer` in the parent for a visual scrim in Flutter.
class DialogOptions {
  const DialogOptions({
    this.size,
    this.minimumSize,
    this.maximumSize,
    this.isResizable,
    this.title,
    this.modal,
    this.titleBarStyle,
    this.windowButtonVisibility,
    this.backgroundColor,
    this.alwaysOnTop,
    this.showOnInit,
    this.shellOverrides,
  });

  /// Initial content size in logical pixels.
  final Size? size;

  /// Minimum size enforced by the native window.
  final Size? minimumSize;

  /// Maximum size enforced by the native window.
  final Size? maximumSize;

  /// Whether the user can resize the dialog by dragging edges.
  final bool? isResizable;

  /// Native window title string.
  final String? title;

  /// When true, the parent window is blocked at the OS level while this dialog
  /// is open (macOS sheet, Windows owner chain, Linux transient and input lock).
  /// `DialogModalLayer` in the parent adds a Flutter scrim; the scrim alone does
  /// not block OS input.
  final bool? modal;

  /// Title bar appearance. `TitleBarStyle.hidden` removes native chrome.
  final TitleBarStyle? titleBarStyle;

  /// Visibility of caption buttons when the title bar is hidden.
  final bool? windowButtonVisibility;

  /// Background color behind the Flutter view.
  final Color? backgroundColor;

  /// Whether the window stays above other application windows.
  final bool? alwaysOnTop;

  /// Whether the window is shown right after creation. Defaults to true.
  final bool? showOnInit;

  /// Per-view shell overrides. See `WindowOptions.shellOverrides`.
  final ViewShellOverrides? shellOverrides;
}

/// Opens a dialog window tied to `parentContext`.
///
/// Returns a `Future` that completes when the dialog is closed via `closeDialog`
/// or `MvdContext.closeDialog`. The optional result value comes from that close
/// call.
///
/// Unlike `openWindow`, `parentContext` is required. Dialogs cannot enter
/// full-screen mode.
///
/// ```dart
/// runMultiApp(
///   home: (context, id) => DialogModalLayer(child: MyHomeScreen()),
/// );
/// ```
///
/// ```dart
/// final result = await openDialog<String>(
///   (context, id) => const SettingsDialog(),
///   parentContext: context,
///   options: DialogOptions(title: 'Settings', modal: true),
/// );
/// // later, inside the dialog:
/// await MultiViewDesktop.of(context).closeDialog('saved');
/// ```
Future<T?> openDialog<T>(
  Widget Function(BuildContext context, int publicId) childBuilder, {
  required BuildContext parentContext,
  DialogOptions? options,
}) => MultiViewDesktop.addDialog(childBuilder, parentContext: parentContext, options: options);
