import '../focus/focus_models.dart';
import 'pomo_models.dart';

/// Projection only: the companion never owns a focus clock or completes timers.
class PomoFocus {
  const PomoFocus({this.run, this.interval, this.preset, this.remaining});
  final FocusRunItem? run;
  final FocusIntervalItem? interval;
  final FocusPresetItem? preset;
  final Duration? remaining;
  bool get hasRun => run != null;
  bool get ready => interval?.status == 'ready';
  bool get paused => interval?.status == 'paused';
  bool get canToggle =>
      interval != null &&
      (ready ||
          paused ||
          (preset != null && preset!.allowPause && !preset!.strictMode));
  bool get canComplete =>
      interval != null &&
      !ready &&
      preset != null &&
      (!preset!.strictMode ||
          (remaining != null && remaining! <= Duration.zero));
  double get fraction =>
      interval == null || remaining == null || interval!.plannedSeconds <= 0
      ? 0
      : (remaining!.inMilliseconds / (interval!.plannedSeconds * 1000)).clamp(
          0,
          1,
        );
  PomoEmotion get background => interval == null || paused || ready
      ? PomoEmotion.calm
      : interval!.type != 'work'
      ? PomoEmotion.rest
      : PomoEmotion.focus;
}
