import 'package:audioplayers/audioplayers.dart';

import 'package:pomodoist/data/services/haptics/app_haptics.dart';
import 'package:pomodoist/domain/models/focus/focus_sound_set.dart';

enum FocusSoundCue { start, complete, pause, resume }

abstract interface class FocusSoundPlayer {
  Future<void> play(FocusSoundCue cue);
  Future<void> dispose();
}

class AssetFocusSoundPlayer implements FocusSoundPlayer {
  AssetFocusSoundPlayer({
    AudioPlayer? player,
    Future<FocusSoundSet> Function()? readSoundSet,
  }) : _player = player ?? AudioPlayer(),
       _readSoundSet = readSoundSet ?? (() async => FocusSoundSet.softKalimba);

  static const _haptics = {
    FocusSoundCue.start: AppHapticCue.light,
    FocusSoundCue.complete: AppHapticCue.success,
    FocusSoundCue.pause: AppHapticCue.selection,
    FocusSoundCue.resume: AppHapticCue.light,
  };

  final AudioPlayer _player;
  final Future<FocusSoundSet> Function() _readSoundSet;
  bool _disposed = false;

  @override
  Future<void> play(FocusSoundCue cue) async {
    if (_disposed) return;
    await playHaptic(_haptics[cue]!);
    try {
      final soundSet = await _readSoundSet();
      if (_disposed) return;
      await _player.play(
        AssetSource('sounds/${soundSet.storageValue}/focus_${cue.name}.wav'),
        mode: PlayerMode.lowLatency,
        volume: 0.55,
      );
    } catch (_) {
      // Audio feedback is best-effort across platforms and tests.
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _player.dispose();
  }
}
