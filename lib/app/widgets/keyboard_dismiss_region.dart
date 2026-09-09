import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/widgets.dart';

/// Dismisses the keyboard on unhandled touch taps, including inside overlays.
class KeyboardDismissRegion extends StatelessWidget {
  const KeyboardDismissRegion({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    supportedDevices: const {PointerDeviceKind.touch},
    excludeFromSemantics: true,
    onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
    child: Actions(
      actions: {
        EditableTextTapOutsideIntent:
            CallbackAction<EditableTextTapOutsideIntent>(
              onInvoke: handleTextTapOutside,
            ),
      },
      child: child,
    ),
  );
}

/// Touch down may become a scroll or a control tap; defer to the tap recognizer.
@visibleForTesting
Object? handleTextTapOutside(EditableTextTapOutsideIntent intent) {
  if (intent.pointerDownEvent.kind != PointerDeviceKind.touch) {
    intent.focusNode.unfocus();
  }
  return null;
}
