import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/features/focus/domain/focus_models.dart';

void main() {
  test('Today replaces the mini player only for a coherent ready session', () {
    final now = DateTime(2026, 9, 9);
    final run = FocusRunItem(
      id: 'current',
      userId: 'local',
      presetId: 'preset',
      status: 'active',
      startedAt: now,
      targetWorkIntervals: 4,
      completedWorkIntervals: 0,
      createdAt: now,
      updatedAt: now,
    );
    FocusIntervalItem interval(String runId) => FocusIntervalItem(
      id: 'interval',
      runId: runId,
      type: 'work',
      status: 'ready',
      plannedSeconds: 1500,
      startedAt: now,
      pausedTotalSeconds: 0,
      sequenceNumber: 1,
      createdAt: now,
      updatedAt: now,
    );
    for (final entry in [
      (
        run: run,
        interval: interval('current'),
        remaining: const Duration(minutes: 25),
        visible: true,
      ),
      (
        run: run,
        interval: interval('previous'),
        remaining: const Duration(minutes: 25),
        visible: false,
      ),
      (
        run: run,
        interval: interval('current'),
        remaining: null,
        visible: false,
      ),
      (
        run: null,
        interval: interval('current'),
        remaining: const Duration(minutes: 25),
        visible: false,
      ),
    ]) {
      final container = ProviderContainer(
        overrides: [
          activeFocusRunProvider.overrideWithValue(AsyncData(entry.run)),
          activeFocusIntervalProvider.overrideWithValue(
            AsyncData(entry.interval),
          ),
          activeFocusRemainingProvider.overrideWith((ref) => entry.remaining),
        ],
      );
      expect(container.read(todayFocusStripVisibleProvider), entry.visible);
      container.dispose();
    }
  });
}
