import 'package:audioplayers/audioplayers.dart';

import '../haptics/app_haptics.dart';

enum FocusSoundCue { start, complete, pause, resume }

abstract interface class FocusSoundPlayer {
  Future<void> play(FocusSoundCue cue);
  Future<void> dispose();
}

class AssetFocusSoundPlayer implements FocusSoundPlayer {
  AssetFocusSoundPlayer({AudioPlayer? player})
    : _player = player ?? AudioPlayer();

  static const _paths = {
    FocusSoundCue.start: 'sounds/focus_start.wav',
    FocusSoundCue.complete: 'sounds/focus_complete.wav',
    FocusSoundCue.pause: 'sounds/focus_pause.wav',
    FocusSoundCue.resume: 'sounds/focus_resume.wav',
  };

  static const _haptics = {
    FocusSoundCue.start: AppHapticCue.light,
    FocusSoundCue.complete: AppHapticCue.success,
    FocusSoundCue.pause: AppHapticCue.selection,
    FocusSoundCue.resume: AppHapticCue.light,
  };

  final AudioPlayer _player;

  @override
  Future<void> play(FocusSoundCue cue) async {
    await playHaptic(_haptics[cue]!);
    try {
      await _player.play(
        AssetSource(_paths[cue]!),
        mode: PlayerMode.lowLatency,
        volume: 0.55,
      );
    } catch (_) {
      // Audio feedback is best-effort across platforms and tests.
    }
  }

  @override
  Future<void> dispose() => _player.dispose();
}
