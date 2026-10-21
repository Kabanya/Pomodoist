import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_shell_patch.dart';
import 'app_shell_registry.dart';
import 'app_shell_snapshot.dart';

/// Controls the shared entry shell used on secondary and dialog views.
///
/// Access the process-wide instance through `MultiViewDesktop.appShell`.
///
/// ## What this updates
///
/// `patch` and `apply` rebuild secondary and dialog views wrapped by the
/// library shell. They do not rebuild the main window `MaterialApp` automatically.
/// Keep the main window in sync through your own state (for example a shared
/// `ChangeNotifier`) or by reading `snapshot` inside a `ListenableBuilder`
/// on the main window.
///
/// ## Where the snapshot comes from
///
/// 1. While the main window is open, the library mirrors app-wide fields from
///    the entry widget in `homeBuilder` into the same registry each frame.
/// 2. Any window can call `patch` or `apply` at any time, including after the
///    main window was closed.
///
/// ## Avoiding feedback loops
///
/// Do not call `patch` from the main window `build` method in response to
/// `ListenableBuilder` rebuilds driven by this controller. Update `patch` from
/// user actions or from a dedicated app-level notifier instead.
///
/// Example (theme toggle shared across windows):
///
/// ```dart
/// void setThemeMode(ThemeMode mode) {
///   _themeMode = mode;
///   MultiViewDesktop.appShell.patch(AppShellPatch(themeMode: mode));
///   notifyListeners(); // rebuild main MaterialApp from the same notifier
/// }
/// ```
class AppShellController {
  /// Creates a controller backed by `registry`.
  AppShellController(this._registry);

  final AppShellRegistry _registry;

  /// Latest snapshot applied to secondary and dialog entry shells.
  AppShellSnapshot? get snapshot => _registry.snapshot;

  /// `Listenable` that fires when `snapshot` changes. Use in `ListenableBuilder`.
  Listenable get listenable => _registry;

  /// Replaces the entire shell snapshot. Rebuilds all secondary and dialog views.
  void apply(AppShellSnapshot snapshot) => _registry.replace(snapshot);

  /// Merges `patch` into the current snapshot. Rebuilds secondary and dialog views.
  void patch(AppShellPatch patch) => _registry.patch(patch);

  /// Replaces `snapshot` with app-wide fields copied from `app`.
  ///
  /// Useful when the main window uses `MaterialApp` and you want to push its
  /// settings to secondary windows manually.
  void applyFromMaterialApp(MaterialApp app) =>
      _registry.replace(AppShellSnapshot.fromMaterialApp(app));

  /// Replaces `snapshot` with app-wide fields copied from `app`.
  void applyFromCupertinoApp(CupertinoApp app) =>
      _registry.replace(AppShellSnapshot.fromCupertinoApp(app));

  /// Replaces `snapshot` with app-wide fields copied from `app`.
  void applyFromWidgetsApp(WidgetsApp app) =>
      _registry.replace(AppShellSnapshot.fromWidgetsApp(app));
}
