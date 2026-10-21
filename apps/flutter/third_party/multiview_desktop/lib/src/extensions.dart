import 'package:flutter/cupertino.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'run_multi_app.dart' as run_app;

extension MvdContext on BuildContext {
  /// Opens a dialog with this context as the parent window.
  ///
  /// Same as `openDialog` from `run_multi_app.dart`. See that function for
  /// dialog behavior and `DialogOptions`.
  ///
  /// ```dart
  /// OutlinedButton(
  ///   onPressed: () => context.openDialog(
  ///     (context, id) => const SettingsDialog(),
  ///     options: DialogOptions(title: 'Settings', modal: true),
  ///   ),
  ///   child: const Text('Open dialog'),
  /// )
  /// ```
  Future<T?> openDialog<T>(
    Widget Function(BuildContext context, int publicId) childBuilder, {
    DialogOptions? options,
  }) => run_app.openDialog<T>(childBuilder, parentContext: this, options: options);

  /// Closes the dialog for this context.
  ///
  /// `res` completes the `await openDialog<T>()` future on the caller side.
  ///
  /// ```dart
  /// ElevatedButton(
  ///   onPressed: () => context.closeDialog('ok'),
  ///   child: const Text('Save'),
  /// )
  /// ```
  Future<void> closeDialog<T>([T? res]) => MultiViewDesktop.of(this).closeDialog(res);

  /// `MultiViewDesktop` instance for the window that owns this context.
  ///
  /// Same as `MultiViewDesktop.of`(this).
  MultiViewDesktop get viewController => MultiViewDesktop.of(this);
}
