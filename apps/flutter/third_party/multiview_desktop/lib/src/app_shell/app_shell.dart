/// Shared entry shell for secondary and dialog views.
///
/// Each OS `View` has its own widget subtree. Theme, locale, and other
/// app-wide `InheritedWidget` values from the main `MaterialApp` are not
/// visible in secondary windows. This module provides a single in-process
/// registry that mirrors those settings and wraps secondary content in a
/// matching entry shell (`MaterialApp`, `CupertinoApp`, or `WidgetsApp`
/// without navigation).
///
/// ## Typical setup
///
/// Main window (`homeBuilder`): full entry widget with navigation.
///
/// ```dart
/// runMultiApp(
///   home: (_, __) => MaterialApp(
///     theme: lightTheme,
///     darkTheme: darkTheme,
///     themeMode: themeMode,
///     home: HomePage(),
///   ),
/// );
/// ```
///
/// Secondary windows: content only. The library adds the shell.
///
/// ```dart
/// openWindow((_, __) => SettingsPage());
/// ```
///
/// Cross-window updates (works even if the main window is closed):
///
/// ```dart
/// MultiViewDesktop.appShell.patch(
///   AppShellPatch(themeMode: ThemeMode.dark),
/// );
/// ```
///
/// Per-view overrides (inherit global theme/locale, change only this window):
///
/// ```dart
/// openWindow(
///   (_, __) => PreviewPage(),
///   options: WindowOptions(
///     shellOverrides: ViewShellOverrides(
///       appearance: AppShellPatch(debugShowCheckedModeBanner: false),
///     ),
///   ),
/// );
///
/// Dedicated router on one secondary window:
///
/// ```dart
/// openWindow(
///   (_, __) => const SizedBox.shrink(),
///   options: WindowOptions(
///     shellOverrides: ViewShellOverrides(routerConfig: settingsRouter),
///   ),
/// );
/// ```
///
/// Do not wrap secondary content in a second full `MaterialApp`. Use
/// `ViewShellOverrides` on `WindowOptions.shellOverrides` or
/// `MultiViewDesktop.patchViewShell` so appearance stays inherited from the
/// global shell while navigation remains per-view.
///
/// See `AppShellController` for keeping the main window in sync without feedback loops.
library;

export 'app_entry_kind.dart';
export 'app_shell_controller.dart';
export 'app_shell_patch.dart';
export 'app_shell_snapshot.dart';
export 'view_shell_overrides.dart';
