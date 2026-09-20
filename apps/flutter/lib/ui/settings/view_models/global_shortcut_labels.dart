import 'package:flutter/foundation.dart';
import 'package:pomodoist/data/repositories/platform/global_quick_add_repository.dart';

extension GlobalShortcutLabels on GlobalQuickAddBinding {
  String labelFor(TargetPlatform platform) {
    if (platform == TargetPlatform.macOS) {
      return [
        if (control) '⌃',
        if (alt) '⌥',
        if (shift) '⇧',
        if (meta) '⌘',
        keyLabel,
      ].join();
    }
    return [
      if (control) 'Ctrl',
      if (alt) 'Alt',
      if (shift) 'Shift',
      if (meta) 'Meta',
      keyLabel,
    ].join('+');
  }

  String get label => labelFor(TargetPlatform.macOS);
}
