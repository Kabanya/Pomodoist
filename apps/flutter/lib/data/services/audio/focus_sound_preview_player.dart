import 'package:audioplayers/audioplayers.dart';
import 'package:pomodoist/domain/models/focus/focus_sound_set.dart';

abstract interface class FocusSoundPreviewPlayer {
  Future<void> preview(FocusSoundSet soundSet);
  Future<void> stop();
  Future<void> dispose();
}

/// A Settings-owned player; auditioning never triggers timer events or haptics.
class AssetFocusSoundPreviewPlayer implements FocusSoundPreviewPlayer {
  AssetFocusSoundPreviewPlayer({AudioPlayer? player})
    : _player = player ?? AudioPlayer();

  final AudioPlayer _player;
  Future<void> _pending = Future.value();
  bool _disposed = false;
  int _generation = 0;

  Future<void> _enqueue(Future<void> Function() action) {
    final operation = _pending.then((_) => action());
    _pending = operation.catchError((Object _) {});
    return operation;
  }

  @override
  Future<void> preview(FocusSoundSet soundSet) {
    final generation = ++_generation;
    return _enqueue(() async {
      if (_disposed || generation != _generation) return;
      await _player.stop();
      if (_disposed || generation != _generation) return;
      await _player.play(
        AssetSource('sounds/${soundSet.storageValue}/focus_complete.wav'),
        mode: PlayerMode.lowLatency,
        volume: 0.55,
      );
      if (_disposed || generation != _generation) await _player.stop();
    });
  }

  @override
  Future<void> stop() {
    ++_generation;
    return _enqueue(() async {
      if (!_disposed) await _player.stop();
    });
  }

  @override
  Future<void> dispose() {
    if (_disposed) return _pending;
    _disposed = true;
    ++_generation;
    return _enqueue(_player.dispose);
  }
}
