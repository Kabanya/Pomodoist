/// Multi-window support for Flutter desktop.
///
/// All OS windows share one Flutter engine and one Dart isolate.
///
/// Entry point: `runMultiApp` instead of `runApp`:
/// ```dart
/// void main() {
///   runMultiApp(home: (context, id) => MyApp());
/// }
/// ```
///
/// Open another window from anywhere:
/// ```dart
/// openWindow((context, id) => const SettingsPage(), options: WindowOptions(title: 'Settings'));
/// ```
///
/// Control the current window via `MultiViewDesktop.of` or `MultiViewDesktop.fromId`:
/// ```dart
/// final win = MultiViewDesktop.of(context);
/// await win.setTitle('Settings');
/// await win.setTitleBarStyle(TitleBarStyle.hidden);
/// ```
///
/// See also `WindowListener`, `WindowCommunicator`, and `WindowOptions`.
library;

export 'src/multi_view_desktop.dart';
export 'src/multi_view_desktop_macos.dart';
export 'src/resize_edge.dart';
export 'src/run_multi_app.dart';
export 'src/app_shell/app_shell.dart';
export 'src/taskbar_menu_item.dart';
export 'src/title_bar_style.dart';
export 'src/parent_window_scope.dart';
export 'src/window_communicator.dart';
export 'src/window_listener.dart';
export 'src/window_observer.dart';
export 'src/window_options.dart';
export 'src/widgets/dialog_modal_layer.dart';
export 'src/widgets/drag_to_move_area.dart';
export 'src/widgets/drag_to_resize_area.dart';
export 'src/widgets/window_caption.dart';
export 'src/extensions.dart';

export 'src/screen_retriever/screen_retriever.dart';
