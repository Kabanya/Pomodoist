import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/models/pomo/pomo_focus.dart';
import 'package:pomodoist/domain/models/pomo/pomo_models.dart';
import 'package:pomodoist/ui/pomo/widgets/pomo_geometry.dart';

FocusIntervalItem interval({
  String status = 'running',
  String type = 'work',
  int sequence = 1,
  int seconds = 3600,
  DateTime? started,
  DateTime? paused,
  DateTime? completed,
  int pauseSeconds = 0,
}) => FocusIntervalItem(
  id: '$sequence',
  runId: 'r',
  type: type,
  status: status,
  plannedSeconds: seconds,
  startedAt: started ?? DateTime(2026),
  pausedTotalSeconds: pauseSeconds,
  sequenceNumber: sequence,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  pausedAt: paused,
  completedAt: completed,
);
FocusPresetItem preset({bool strict = false, bool pause = true}) =>
    FocusPresetItem(
      id: 'p',
      userId: 'u',
      name: 'x',
      workSeconds: 3600,
      shortBreakSeconds: 300,
      longBreakSeconds: 900,
      intervalsBeforeLongBreak: 4,
      autoStartBreaks: false,
      autoStartWork: false,
      allowPause: pause,
      strictMode: strict,
      isDefault: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
void main() {
  test(
    'strict/ready/pause rules and remaining fraction come from shared state',
    () {
      final strict = PomoFocus(
        interval: interval(),
        preset: preset(strict: true),
        remaining: const Duration(minutes: 10),
      );
      expect(strict.canComplete, false);
      expect(strict.canToggle, false);
      expect(strict.fraction, closeTo(1 / 6, 0.001));
      expect(
        PomoFocus(
          interval: interval(),
          preset: preset(strict: true),
          remaining: Duration.zero,
        ).canComplete,
        true,
      );
      final ready = PomoFocus(
        interval: interval(status: 'ready'),
        preset: preset(strict: true),
      );
      expect(ready.canComplete, false);
      expect(ready.canToggle, true);
      expect(
        PomoFocus(interval: interval(), preset: preset(pause: false)).canToggle,
        false,
      );
      expect(
        PomoFocus(interval: interval(type: 'short_break')).background,
        PomoEmotion.rest,
      );
    },
  );
  test(
    'fatigue counts actual work, excludes paused time, resets on completed break',
    () {
      final now = DateTime(2026).add(const Duration(minutes: 60));
      final first = interval(
        paused: DateTime(2026).add(const Duration(minutes: 45)),
        pauseSeconds: 300,
      );
      expect(pomoWorkSinceBreak([first], now), const Duration(minutes: 40));
      expect(
        pomoWorkSinceBreak([interval(status: 'ready')], now),
        Duration.zero,
      );
      final doneBreak = interval(
        type: 'short_break',
        status: 'completed',
        sequence: 2,
        completed: now,
      );
      expect(pomoWorkSinceBreak([first, doneBreak], now), Duration.zero);
      expect(
        PomoFocus(
          interval: interval(),
          workSinceBreak: const Duration(minutes: 50),
        ).background,
        PomoEmotion.tired,
      );
    },
  );
  test(
    'position clamps negative and removed-monitor positions to work area',
    () {
      const area = Rect.fromLTWH(-1920, 24, 1920, 1056);
      expect(PomoLayout(1).position(area), const Offset(-352, 728));
      expect(
        PomoLayout(1).position(area, saved: const Offset(9000, -100)),
        const Offset(-328, 24),
      );
      expect(PomoLayout(1).regions(false).length, 2);
      expect(PomoLayout(1).regions(true).length, 7);
    },
  );
}
