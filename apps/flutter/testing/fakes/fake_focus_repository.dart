import 'package:pomodoist/data/repositories/focus/focus_repository.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/utils/result.dart';

import 'strict_fake.dart';

/// A [FocusRepository] where every method answers out of the box: reads are
/// served from the stub fields, writes succeed unless an `<method>Error` field
/// is set, and every call is appended to its recording list.
class FakeFocusRepository extends StrictFake implements FocusRepository {
  /// One entry per call, so a test can count subscriptions.
  final List<void> watchPresetsCalls = [];

  /// One entry per call, so a test can count subscriptions.
  final List<void> watchActiveRunCalls = [];

  /// One entry per call, so a test can count subscriptions.
  final List<void> watchActiveIntervalCalls = [];

  final List<String> watchRunsForTaskCalls = [];
  final List<String> watchIntervalsForTaskCalls = [];
  final List<String> watchIntervalsForRunCalls = [];
  final List<DateTime> watchDailyStatsCalls = [];
  final List<CreateFocusPresetInput> createPresetCalls = [];
  final List<({String id, UpdateFocusPresetInput input})> updatePresetCalls = [];
  final List<String> deletePresetCalls = [];
  final List<String> setDefaultPresetCalls = [];
  final List<String> changeActiveRunPresetCalls = [];
  final List<({StartFocusRunInput input, DateTime? now})> startRunCalls = [];

  /// One entry per call, so a test can count activations.
  final List<void> startReadyIntervalCalls = [];

  final List<DateTime?> pauseActiveIntervalCalls = [];
  final List<DateTime?> resumeActiveIntervalCalls = [];
  final List<DateTime?> restartActiveIntervalCalls = [];
  final List<DateTime?> completeActiveIntervalCalls = [];
  final List<DateTime?> skipActiveIntervalCalls = [];
  final List<({StopFocusReason reason, DateTime? now})> stopActiveRunCalls = [];
  final List<({String runId, String? note})> logDistractionCalls = [];

  List<FocusPresetItem> presets = const [];
  FocusRunItem? activeRun;
  FocusIntervalItem? activeInterval;
  List<FocusRunItem> runsForTask = const [];
  List<FocusIntervalItem> intervalsForTask = const [];
  List<FocusIntervalItem> intervalsForRun = const [];
  FocusDailyStats dailyStats = const FocusDailyStats(
    completedTasks: 0,
    completedFocusIntervals: 0,
    totalFocusSeconds: 0,
    interruptedIntervals: 0,
    plannedFocusIntervals: 0,
  );

  String createdPresetId = 'preset-1';
  String startedRunId = 'run-1';

  Object? createPresetError;
  Object? updatePresetError;
  Object? deletePresetError;
  Object? setDefaultPresetError;
  Object? changeActiveRunPresetError;
  Object? startRunError;
  Object? startReadyIntervalError;
  Object? pauseActiveIntervalError;
  Object? resumeActiveIntervalError;
  Object? restartActiveIntervalError;
  Object? completeActiveIntervalError;
  Object? skipActiveIntervalError;
  Object? stopActiveRunError;
  Object? logDistractionError;

  @override
  Stream<List<FocusPresetItem>> watchPresets() {
    watchPresetsCalls.add(null);
    return Stream.value(presets);
  }

  @override
  Stream<FocusRunItem?> watchActiveRun() {
    watchActiveRunCalls.add(null);
    return Stream.value(activeRun);
  }

  @override
  Stream<FocusIntervalItem?> watchActiveInterval() {
    watchActiveIntervalCalls.add(null);
    return Stream.value(activeInterval);
  }

  @override
  Stream<List<FocusRunItem>> watchRunsForTask(String taskId) {
    watchRunsForTaskCalls.add(taskId);
    return Stream.value(runsForTask);
  }

  @override
  Stream<List<FocusIntervalItem>> watchIntervalsForTask(String taskId) {
    watchIntervalsForTaskCalls.add(taskId);
    return Stream.value(intervalsForTask);
  }

  @override
  Stream<List<FocusIntervalItem>> watchIntervalsForRun(String runId) {
    watchIntervalsForRunCalls.add(runId);
    return Stream.value(intervalsForRun);
  }

  @override
  Stream<FocusDailyStats> watchDailyStats(DateTime localDate) {
    watchDailyStatsCalls.add(localDate);
    return Stream.value(dailyStats);
  }

  @override
  Future<Result<String>> createPreset(CreateFocusPresetInput input) async {
    createPresetCalls.add(input);
    return switch (createPresetError) {
      final error? => Result.error(error, StackTrace.current),
      _ => Result.ok(createdPresetId),
    };
  }

  @override
  Future<Result<void>> updatePreset(
    String id,
    UpdateFocusPresetInput input,
  ) async {
    updatePresetCalls.add((id: id, input: input));
    return switch (updatePresetError) {
      final error? => Result.error(error, StackTrace.current),
      _ => Result.ok(null),
    };
  }

  @override
  Future<Result<void>> deletePreset(String id) async {
    deletePresetCalls.add(id);
    return switch (deletePresetError) {
      final error? => Result.error(error, StackTrace.current),
      _ => Result.ok(null),
    };
  }

  @override
  Future<Result<void>> setDefaultPreset(String id) async {
    setDefaultPresetCalls.add(id);
    return switch (setDefaultPresetError) {
      final error? => Result.error(error, StackTrace.current),
      _ => Result.ok(null),
    };
  }

  @override
  Future<Result<void>> changeActiveRunPreset(String presetId) async {
    changeActiveRunPresetCalls.add(presetId);
    return switch (changeActiveRunPresetError) {
      final error? => Result.error(error, StackTrace.current),
      _ => Result.ok(null),
    };
  }

  @override
  Future<Result<String>> startRun(
    StartFocusRunInput input, {
    DateTime? now,
  }) async {
    startRunCalls.add((input: input, now: now));
    return switch (startRunError) {
      final error? => Result.error(error, StackTrace.current),
      _ => Result.ok(startedRunId),
    };
  }

  @override
  Future<Result<void>> startReadyInterval() async {
    startReadyIntervalCalls.add(null);
    return switch (startReadyIntervalError) {
      final error? => Result.error(error, StackTrace.current),
      _ => Result.ok(null),
    };
  }

  @override
  Future<Result<void>> pauseActiveInterval({DateTime? now}) async {
    pauseActiveIntervalCalls.add(now);
    return switch (pauseActiveIntervalError) {
      final error? => Result.error(error, StackTrace.current),
      _ => Result.ok(null),
    };
  }

  @override
  Future<Result<void>> resumeActiveInterval({DateTime? now}) async {
    resumeActiveIntervalCalls.add(now);
    return switch (resumeActiveIntervalError) {
      final error? => Result.error(error, StackTrace.current),
      _ => Result.ok(null),
    };
  }

  @override
  Future<Result<void>> restartActiveInterval({DateTime? now}) async {
    restartActiveIntervalCalls.add(now);
    return switch (restartActiveIntervalError) {
      final error? => Result.error(error, StackTrace.current),
      _ => Result.ok(null),
    };
  }

  @override
  Future<Result<void>> completeActiveInterval({DateTime? now}) async {
    completeActiveIntervalCalls.add(now);
    return switch (completeActiveIntervalError) {
      final error? => Result.error(error, StackTrace.current),
      _ => Result.ok(null),
    };
  }

  @override
  Future<Result<void>> skipActiveInterval({DateTime? now}) async {
    skipActiveIntervalCalls.add(now);
    return switch (skipActiveIntervalError) {
      final error? => Result.error(error, StackTrace.current),
      _ => Result.ok(null),
    };
  }

  @override
  Future<Result<void>> stopActiveRun({
    required StopFocusReason reason,
    DateTime? now,
  }) async {
    stopActiveRunCalls.add((reason: reason, now: now));
    return switch (stopActiveRunError) {
      final error? => Result.error(error, StackTrace.current),
      _ => Result.ok(null),
    };
  }

  @override
  Future<Result<void>> logDistraction({
    required String runId,
    String? note,
  }) async {
    logDistractionCalls.add((runId: runId, note: note));
    return switch (logDistractionError) {
      final error? => Result.error(error, StackTrace.current),
      _ => Result.ok(null),
    };
  }
}
