import 'package:pomodoist/utils/result.dart';

import 'package:pomodoist/domain/models/focus/focus_models.dart';

abstract interface class FocusRepository {
  Stream<List<FocusPresetItem>> watchPresets();
  Stream<FocusRunItem?> watchActiveRun();
  Stream<FocusIntervalItem?> watchActiveInterval();
  Stream<List<FocusRunItem>> watchRunsForTask(String taskId);
  Stream<List<FocusIntervalItem>> watchIntervalsForTask(String taskId);
  Stream<List<FocusIntervalItem>> watchIntervalsForRun(String runId);
  Stream<FocusDailyStats> watchDailyStats(DateTime localDate);
  Future<Result<String>> createPreset(CreateFocusPresetInput input);
  Future<Result<void>> updatePreset(String id, UpdateFocusPresetInput input);
  Future<Result<void>> deletePreset(String id);
  Future<Result<void>> setDefaultPreset(String id);
  Future<Result<void>> changeActiveRunPreset(String presetId);
  Future<Result<String>> startRun(StartFocusRunInput input, {DateTime? now});
  Future<Result<void>> startReadyInterval();
  Future<Result<void>> pauseActiveInterval({DateTime? now});
  Future<Result<void>> resumeActiveInterval({DateTime? now});
  Future<Result<void>> restartActiveInterval({DateTime? now});
  Future<Result<void>> completeActiveInterval({DateTime? now});
  Future<Result<void>> skipActiveInterval({DateTime? now});
  Future<Result<void>> stopActiveRun({
    required StopFocusReason reason,
    DateTime? now,
  });
  Future<Result<void>> logDistraction({required String runId, String? note});
}
