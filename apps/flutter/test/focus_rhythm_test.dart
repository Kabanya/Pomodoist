import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/focus/domain/focus_models.dart';
import 'package:pomodoist/features/focus/presentation/focus_rhythm.dart';

void main() {
  group('focus rhythm projection', () {
    test('builds a standard four-work cadence', () {
      final rhythm = buildFocusRhythm(
        preset: _preset(),
        targetWorkIntervals: 4,
      );

      expect(rhythm.steps.map((step) => step.phase), [
        FocusRhythmPhase.work,
        FocusRhythmPhase.shortBreak,
        FocusRhythmPhase.work,
        FocusRhythmPhase.shortBreak,
        FocusRhythmPhase.work,
        FocusRhythmPhase.shortBreak,
        FocusRhythmPhase.work,
        FocusRhythmPhase.longBreak,
      ]);
      expect(rhythm.steps.map((step) => step.workOrdinal), [
        1,
        1,
        2,
        2,
        3,
        3,
        4,
        4,
      ]);
      expect(rhythm.steps.map((step) => step.sequence), [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
      ]);
      expect(rhythm.steps.map((step) => step.state).toSet(), {
        FocusRhythmState.upcoming,
      });
      expect(rhythm.steps.map((step) => step.source).toSet(), {
        FocusRhythmSource.projected,
      });
      expect(rhythm.steps.clear, throwsUnsupportedError);
    });

    test('uses a custom long-break cadence', () {
      final rhythm = buildFocusRhythm(
        preset: _preset(cadence: 2),
        targetWorkIntervals: 3,
      );

      expect(rhythm.steps.map((step) => step.phase), [
        FocusRhythmPhase.work,
        FocusRhythmPhase.shortBreak,
        FocusRhythmPhase.work,
        FocusRhythmPhase.longBreak,
        FocusRhythmPhase.work,
        FocusRhythmPhase.shortBreak,
      ]);
    });

    test('includes the final long break required to complete the run', () {
      final rhythm = buildFocusRhythm(
        preset: _preset(cadence: 4),
        targetWorkIntervals: 4,
      );

      final finalStep = rhythm.steps.last;
      expect(finalStep.phase, FocusRhythmPhase.longBreak);
      expect(finalStep.workOrdinal, 4);
      expect(finalStep.plannedSeconds, 15 * 60);
      expect(finalStep.isProjected, isTrue);
      expect(finalStep.isActual, isFalse);
    });
  });

  group('focus rhythm history', () {
    test('maps active ready running and paused interval states', () {
      const expectedStates = {
        'ready': FocusRhythmState.ready,
        'running': FocusRhythmState.running,
        'paused': FocusRhythmState.paused,
      };

      for (final entry in expectedStates.entries) {
        final rhythm = buildFocusRhythm(
          preset: _preset(),
          targetWorkIntervals: 1,
          intervals: [
            _interval(
              id: entry.key,
              type: 'work',
              status: entry.key,
              plannedSeconds: 321,
              sequence: 7,
            ),
          ],
        );

        final actual = rhythm.steps.first;
        expect(actual.phase, FocusRhythmPhase.work);
        expect(actual.state, entry.value);
        expect(actual.sequence, 7);
        expect(actual.workOrdinal, 1);
        expect(actual.plannedSeconds, 321);
        expect(actual.source, FocusRhythmSource.actual);
        expect(rhythm.steps.last.phase, FocusRhythmPhase.shortBreak);
      }
    });

    test(
      'preserves preset-change history and projects with current preset',
      () {
        final rhythm = buildFocusRhythm(
          preset: _preset(
            cadence: 2,
            workSeconds: 50 * 60,
            shortBreakSeconds: 10 * 60,
            longBreakSeconds: 30 * 60,
          ),
          targetWorkIntervals: 2,
          intervals: [
            _interval(
              id: 'historical-break',
              type: 'longBreak',
              status: 'completed',
              plannedSeconds: 4 * 60,
              sequence: 4,
            ),
            _interval(
              id: 'historical-work',
              type: 'work',
              status: 'completed',
              plannedSeconds: 20 * 60,
              sequence: 3,
            ),
          ],
        );

        expect(rhythm.steps.map((step) => step.phase), [
          FocusRhythmPhase.work,
          FocusRhythmPhase.longBreak,
          FocusRhythmPhase.work,
          FocusRhythmPhase.longBreak,
        ]);
        expect(rhythm.steps.map((step) => step.plannedSeconds), [
          20 * 60,
          4 * 60,
          50 * 60,
          30 * 60,
        ]);
        expect(rhythm.steps.map((step) => step.sequence), [3, 4, 5, 6]);
        expect(rhythm.steps.map((step) => step.source), [
          FocusRhythmSource.actual,
          FocusRhythmSource.actual,
          FocusRhythmSource.projected,
          FocusRhythmSource.projected,
        ]);
      },
    );

    test('skipped work adds a break and a replacement work', () {
      final rhythm = buildFocusRhythm(
        preset: _preset(),
        targetWorkIntervals: 1,
        intervals: [
          _interval(
            id: 'skipped-work',
            type: 'work',
            status: 'skipped',
            plannedSeconds: 25 * 60,
            sequence: 1,
          ),
        ],
      );

      expect(rhythm.steps.map((step) => step.phase), [
        FocusRhythmPhase.work,
        FocusRhythmPhase.shortBreak,
        FocusRhythmPhase.work,
        FocusRhythmPhase.shortBreak,
      ]);
      expect(rhythm.steps.map((step) => step.workOrdinal), [1, 1, 1, 1]);
      expect(rhythm.steps.first.state, FocusRhythmState.skipped);
      expect(rhythm.steps.first.source, FocusRhythmSource.actual);
      expect(rhythm.steps.skip(1).map((step) => step.source).toSet(), {
        FocusRhythmSource.projected,
      });
    });

    test(
      'normalizes malformed cadence and target and handles large targets',
      () {
        final malformed = buildFocusRhythm(
          preset: _preset(cadence: 0),
          targetWorkIntervals: 0,
        );
        final large = buildFocusRhythm(
          preset: _preset(),
          targetWorkIntervals: 5000,
        );

        expect(malformed.steps, hasLength(2));
        expect(malformed.steps.last.phase, FocusRhythmPhase.longBreak);
        expect(large.steps, hasLength(10000));
        expect(large.steps.last.workOrdinal, 5000);
        expect(large.steps.last.phase, FocusRhythmPhase.longBreak);
      },
    );

    test('degrades unknown stored values without throwing', () {
      final rhythm = buildFocusRhythm(
        preset: _preset(),
        targetWorkIntervals: 1,
        intervals: [
          _interval(
            id: 'unknown',
            type: 'unexpected-phase',
            status: 'unexpected-state',
            plannedSeconds: 77,
            sequence: -5,
          ),
        ],
      );

      final actual = rhythm.steps.first;
      expect(actual.phase, FocusRhythmPhase.work);
      expect(actual.state, FocusRhythmState.upcoming);
      expect(actual.plannedSeconds, 77);
      expect(actual.sequence, -5);
      expect(actual.source, FocusRhythmSource.actual);
      expect(rhythm.steps, hasLength(2));
    });
  });
}

FocusPresetItem _preset({
  int cadence = 4,
  int workSeconds = 25 * 60,
  int shortBreakSeconds = 5 * 60,
  int longBreakSeconds = 15 * 60,
}) {
  final now = DateTime.utc(2026);
  return FocusPresetItem(
    id: 'preset',
    userId: 'user',
    name: 'Preset',
    workSeconds: workSeconds,
    shortBreakSeconds: shortBreakSeconds,
    longBreakSeconds: longBreakSeconds,
    intervalsBeforeLongBreak: cadence,
    autoStartBreaks: false,
    autoStartWork: false,
    allowPause: true,
    strictMode: false,
    isDefault: true,
    createdAt: now,
    updatedAt: now,
  );
}

FocusIntervalItem _interval({
  required String id,
  required String type,
  required String status,
  required int plannedSeconds,
  required int sequence,
}) {
  final now = DateTime.utc(2026);
  return FocusIntervalItem(
    id: id,
    runId: 'run',
    type: type,
    status: status,
    plannedSeconds: plannedSeconds,
    startedAt: now,
    pausedTotalSeconds: 0,
    sequenceNumber: sequence,
    createdAt: now,
    updatedAt: now,
  );
}
