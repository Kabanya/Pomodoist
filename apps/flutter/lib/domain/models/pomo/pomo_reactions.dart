import 'dart:async';
import 'pomo_models.dart';

/// Finite, non-queued reactions. Commands never wait for decorative playback.
class PomoReactions {
  PomoReactions({DateTime Function()? now}) : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  final _changes = StreamController<void>.broadcast(sync: true);
  final _seen = <String>{};
  Stream<void> get changes => _changes.stream;
  PomoEmotion? emotion;
  DateTime? _until, _lastTap, _lastHappy;
  Timer? _timer;
  bool _quiet = false, _reduce = false, _disposed = false;
  bool get animated => !_quiet && !_reduce;
  Duration get remaining {
    final value = _until?.difference(_now()) ?? Duration.zero;
    return value.isNegative ? Duration.zero : value;
  }

  static int _priority(PomoEmotion? emotion) => switch (emotion) {
    PomoEmotion.sad => 4,
    PomoEmotion.happy => 3,
    PomoEmotion.greeting => 2,
    PomoEmotion.surprised => 1,
    _ => 0,
  };
  bool request(PomoEmotion next, {String? eventId}) {
    if (_disposed) return false;
    if (eventId != null) {
      if (!_seen.add(eventId)) return false;
      if (_seen.length > 256) _seen.remove(_seen.first);
    }
    final now = _now();
    if (next == PomoEmotion.surprised &&
        _lastTap != null &&
        now.difference(_lastTap!) < const Duration(seconds: 2)) {
      return false;
    }
    if (next == PomoEmotion.happy &&
        _lastHappy != null &&
        now.difference(_lastHappy!) < const Duration(seconds: 1)) {
      return false;
    }
    if (_priority(next) < _priority(emotion)) return false;
    if (next == PomoEmotion.surprised) _lastTap = now;
    if (next == PomoEmotion.happy) {
      _lastHappy = now;
      if (emotion == PomoEmotion.happy) return false; // no celebration queue
    }
    emotion = next;
    _schedule(
      next == PomoEmotion.sad
          ? (animated ? const Duration(milliseconds: 900) : Duration.zero)
          : (animated
                ? const Duration(seconds: 3)
                : const Duration(milliseconds: 600)),
    );
    _changes.add(null);
    return true;
  }

  void setMotion({required bool quiet, required bool reduceMotion}) {
    if (_quiet == quiet && _reduce == reduceMotion) return;
    _quiet = quiet;
    _reduce = reduceMotion;
    if (!animated && emotion != null) {
      _schedule(
        emotion == PomoEmotion.sad
            ? Duration.zero
            : const Duration(milliseconds: 600),
      );
    }
    if (!_disposed) _changes.add(null);
  }

  void _schedule(Duration duration) {
    _timer?.cancel();
    _until = _now().add(duration);
    _timer = Timer(duration, clear);
  }

  void clear() {
    _timer?.cancel();
    _until = null;
    emotion = null;
    if (!_disposed) _changes.add(null);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_changes.close());
  }
}
