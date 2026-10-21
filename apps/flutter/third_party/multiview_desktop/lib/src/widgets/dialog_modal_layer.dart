import 'package:flutter/widgets.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

/// Tracks open child dialogs for one OS window.
///
/// Injected automatically by the library. Read the notifier via `DialogScope.of`
/// or use `DialogModalLayer` instead of constructing this widget directly.
typedef DialogInfo = ({int id, bool isModal});

class DialogScope extends InheritedWidget {
  const DialogScope({super.key, required this.notifier, required super.child});

  /// Live list of child dialogs currently open over this window.
  ///
  /// Each entry contains the dialog public view id and whether it is modal.
  /// An empty list means no child dialogs.
  final ValueNotifier<List<DialogInfo>> notifier;

  /// Returns the notifier from the nearest `DialogScope`, or null when the tree
  /// was not created with `runMultiApp`.
  static ValueNotifier<List<DialogInfo>>? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<DialogScope>()?.notifier;
  }

  /// Returns the notifier from the nearest `DialogScope`.
  ///
  /// Throws in debug mode when `runMultiApp` was not used as the entry point.
  static ValueNotifier<List<DialogInfo>> of(BuildContext context) {
    final scope = maybeOf(context);
    assert(
      scope != null,
      'No DialogModalScope found in context. '
      'Make sure runMultiApp() is used as the app entry point.',
    );
    return scope!;
  }

  @override
  bool updateShouldNotify(DialogScope oldWidget) => notifier != oldWidget.notifier;
}

/// Semi-transparent overlay over a parent window while a modal dialog is open.
///
/// Place at the root of each window that can host modal dialogs so the scrim
/// covers the full window surface:
///
/// ```dart
/// runMultiApp(
///   home: (context, id) => DialogModalLayer(
///     child: MyHomeScreen(),
///   ),
/// );
/// ```
///
/// When `openDialog` is called with `modal: true`, the scrim fades in over the
/// parent content. Native modal dialogs also block input on the parent at the
/// OS level on supported platforms; this widget adds visual dimming only.
///
/// The Flutter scrim blocks pointer events to widgets below it while visible.
/// OS-level blocking is handled separately by the native layer when `modal: true`.
class DialogModalLayer extends StatelessWidget {
  const DialogModalLayer({
    super.key,
    required this.child,
    this.showBarrierForNotModalDialog = false,
    this.barrierColor = const Color(0x80000000),
    this.animationDuration = const Duration(milliseconds: 150),
  });

  /// Content shown beneath the scrim.
  final Widget child;

  /// When true, a scrim is also shown for non-modal (modeless) child dialogs.
  /// Tapping the scrim focuses the topmost modeless dialog.
  final bool showBarrierForNotModalDialog;

  /// Scrim color. Defaults to semi-transparent black.
  final Color barrierColor;

  /// Fade duration when the scrim appears or disappears.
  final Duration animationDuration;

  @override
  Widget build(BuildContext context) {
    final notifier = DialogScope.of(context);

    return ValueListenableBuilder<List<DialogInfo>>(
      valueListenable: notifier,
      builder: (context, modalList, _) {
        bool showBarrier = showBarrierForNotModalDialog && modalList.isNotEmpty;
        final bool anyIsModal = modalList.any((e) => e.isModal);
        if (anyIsModal) {
          showBarrier = true;
        }
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () async {
            if (showBarrier && !anyIsModal) {
              final dialogsList = modalList.map((e)=> e.id).toList()..sort();
              for (final id in dialogsList){
                await MultiViewDesktop.fromId(id).focus();
              }
            }
          },
          child: Stack(
            children: [
              child,
              AnimatedOpacity(
                opacity: showBarrier ? 1.0 : 0.0,
                duration: animationDuration,
                child: IgnorePointer(
                  ignoring: !showBarrier,
                  child: ColoredBox(color: barrierColor, child: const SizedBox.expand()),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
