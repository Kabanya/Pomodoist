import 'package:flutter/services.dart';

enum AppHapticCue { none, selection, light, success }

Future<void> playHaptic(AppHapticCue cue) async {
  try {
    switch (cue) {
      case AppHapticCue.none:
        return;
      case AppHapticCue.selection:
        await HapticFeedback.selectionClick();
      case AppHapticCue.light:
        await HapticFeedback.lightImpact();
      case AppHapticCue.success:
        await HapticFeedback.mediumImpact();
    }
  } catch (_) {
    // Haptics are best-effort across platforms and tests.
  }
}
