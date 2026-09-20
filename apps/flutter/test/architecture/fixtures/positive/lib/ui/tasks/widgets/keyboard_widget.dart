import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Widgets may use Flutter keyboard and focus services directly.
class KeyboardWidget {
  const KeyboardWidget(this.focusNode);

  final FocusNode focusNode;

  bool handle(KeyEvent event) =>
      event.logicalKey == LogicalKeyboardKey.enter ||
      event.logicalKey == LogicalKeyboardKey.escape;
}
