import 'package:flutter/services.dart';
import 'package:pomodoist/domain/models/feedback/haptic_cue.dart';

export 'package:pomodoist/domain/models/feedback/haptic_cue.dart';

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
