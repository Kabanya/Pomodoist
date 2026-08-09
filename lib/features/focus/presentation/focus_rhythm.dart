import '../domain/focus_models.dart';

enum FocusRhythmPhase { work, shortBreak, longBreak }

enum FocusRhythmState { completed, skipped, ready, running, paused, upcoming }

enum FocusRhythmSource { actual, projected }

class FocusRhythmStep {
  const FocusRhythmStep({
    required this.phase,
    required this.state,
    required this.sequence,
    required this.workOrdinal,
    required this.plannedSeconds,
    required this.source,
  });

  final FocusRhythmPhase phase;
  final FocusRhythmState state;
  final int sequence;
  final int workOrdinal;
  final int plannedSeconds;
  final FocusRhythmSource source;

  int get sequenceNumber => sequence;
  bool get isActual => source == FocusRhythmSource.actual;
  bool get isProjected => source == FocusRhythmSource.projected;
}

class FocusRhythm {
  FocusRhythm(Iterable<FocusRhythmStep> steps)
    : steps = List<FocusRhythmStep>.unmodifiable(steps);

  final List<FocusRhythmStep> steps;
}

FocusRhythm buildFocusRhythm({
  required FocusPresetItem preset,
  required int targetWorkIntervals,
  Iterable<FocusIntervalItem> intervals = const [],
}) {
  final cadence = preset.intervalsBeforeLongBreak < 1
      ? 1
      : preset.intervalsBeforeLongBreak;
  final target = targetWorkIntervals < 1 ? 1 : targetWorkIntervals;
  final steps = <FocusRhythmStep>[];
  final actualIntervals = intervals.toList()
    ..sort((left, right) {
      final sequenceComparison = left.sequenceNumber.compareTo(
        right.sequenceNumber,
      );
      if (sequenceComparison != 0) {
        return sequenceComparison;
      }
      final createdComparison = left.createdAt.compareTo(right.createdAt);
      return createdComparison != 0
          ? createdComparison
          : left.id.compareTo(right.id);
    });
  var completedWorkIntervals = 0;
  var lastWorkOrdinal = 1;
  var largestSequence = 0;

  for (final interval in actualIntervals) {
    final phase = _phaseFor(interval.type);
    final state = _stateFor(interval.status);
    final workOrdinal = phase == FocusRhythmPhase.work
        ? completedWorkIntervals + 1
        : lastWorkOrdinal;
    if (phase == FocusRhythmPhase.work) {
      lastWorkOrdinal = workOrdinal;
      if (state == FocusRhythmState.completed) {
        completedWorkIntervals++;
      }
    }
    if (interval.sequenceNumber > largestSequence) {
      largestSequence = interval.sequenceNumber;
    }
    steps.add(
      FocusRhythmStep(
        phase: phase,
        state: state,
        sequence: interval.sequenceNumber,
        workOrdinal: workOrdinal,
        plannedSeconds: interval.plannedSeconds,
        source: FocusRhythmSource.actual,
      ),
    );
  }

  var sequence = largestSequence + 1;
  var needsWork = actualIntervals.isEmpty;
  if (actualIntervals.isNotEmpty) {
    final lastStep = steps.last;
    if (lastStep.phase == FocusRhythmPhase.work) {
      if (lastStep.state != FocusRhythmState.skipped &&
          lastStep.state != FocusRhythmState.completed) {
        completedWorkIntervals++;
      }
      final skipped = lastStep.state == FocusRhythmState.skipped;
      final longBreak = !skipped && completedWorkIntervals % cadence == 0;
      steps.add(
        FocusRhythmStep(
          phase: longBreak
              ? FocusRhythmPhase.longBreak
              : FocusRhythmPhase.shortBreak,
          state: FocusRhythmState.upcoming,
          sequence: sequence++,
          workOrdinal: lastStep.workOrdinal,
          plannedSeconds: longBreak
              ? preset.longBreakSeconds
              : preset.shortBreakSeconds,
          source: FocusRhythmSource.projected,
        ),
      );
      needsWork = completedWorkIntervals < target;
    } else {
      needsWork = completedWorkIntervals < target;
    }
  }

  while (needsWork) {
    final workOrdinal = completedWorkIntervals + 1;
    steps.add(
      FocusRhythmStep(
        phase: FocusRhythmPhase.work,
        state: FocusRhythmState.upcoming,
        sequence: sequence++,
        workOrdinal: workOrdinal,
        plannedSeconds: preset.workSeconds,
        source: FocusRhythmSource.projected,
      ),
    );
    completedWorkIntervals++;
    final longBreak = workOrdinal % cadence == 0;
    steps.add(
      FocusRhythmStep(
        phase: longBreak
            ? FocusRhythmPhase.longBreak
            : FocusRhythmPhase.shortBreak,
        state: FocusRhythmState.upcoming,
        sequence: sequence++,
        workOrdinal: workOrdinal,
        plannedSeconds: longBreak
            ? preset.longBreakSeconds
            : preset.shortBreakSeconds,
        source: FocusRhythmSource.projected,
      ),
    );
    needsWork = completedWorkIntervals < target;
  }

  return FocusRhythm(steps);
}

FocusRhythmPhase _phaseFor(String type) {
  return switch (type) {
    'shortBreak' => FocusRhythmPhase.shortBreak,
    'longBreak' => FocusRhythmPhase.longBreak,
    _ => FocusRhythmPhase.work,
  };
}

FocusRhythmState _stateFor(String status) {
  return switch (status) {
    'completed' => FocusRhythmState.completed,
    'skipped' => FocusRhythmState.skipped,
    'ready' => FocusRhythmState.ready,
    'running' => FocusRhythmState.running,
    'paused' => FocusRhythmState.paused,
    _ => FocusRhythmState.upcoming,
  };
}
