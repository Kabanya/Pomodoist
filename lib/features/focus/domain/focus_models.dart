class FocusRunItem {
  const FocusRunItem({
    required this.id,
    required this.userId,
    required this.presetId,
    required this.status,
    required this.startedAt,
    required this.targetWorkIntervals,
    required this.completedWorkIntervals,
    required this.createdAt,
    required this.updatedAt,
    this.taskId,
    this.projectId,
    this.endedAt,
    this.note,
  });

  final String id;
  final String userId;
  final String? taskId;
  final String? projectId;
  final String presetId;
  final String status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int targetWorkIntervals;
  final int completedWorkIntervals;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class FocusIntervalItem {
  const FocusIntervalItem({
    required this.id,
    required this.runId,
    required this.type,
    required this.status,
    required this.plannedSeconds,
    required this.startedAt,
    required this.pausedTotalSeconds,
    required this.sequenceNumber,
    required this.createdAt,
    required this.updatedAt,
    this.taskId,
    this.projectId,
    this.pausedAt,
    this.completedAt,
    this.stoppedAt,
  });

  final String id;
  final String runId;
  final String? taskId;
  final String? projectId;
  final String type;
  final String status;
  final int plannedSeconds;
  final DateTime startedAt;
  final DateTime? pausedAt;
  final int pausedTotalSeconds;
  final DateTime? completedAt;
  final DateTime? stoppedAt;
  final int sequenceNumber;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class FocusPresetItem {
  const FocusPresetItem({
    required this.id,
    required this.userId,
    required this.name,
    required this.workSeconds,
    required this.shortBreakSeconds,
    required this.longBreakSeconds,
    required this.intervalsBeforeLongBreak,
    required this.autoStartBreaks,
    required this.autoStartWork,
    required this.allowPause,
    required this.strictMode,
    required this.isDefault,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String name;
  final int workSeconds;
  final int shortBreakSeconds;
  final int longBreakSeconds;
  final int intervalsBeforeLongBreak;
  final bool autoStartBreaks;
  final bool autoStartWork;
  final bool allowPause;
  final bool strictMode;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class FocusDailyStats {
  const FocusDailyStats({
    required this.completedTasks,
    required this.completedFocusIntervals,
    required this.totalFocusSeconds,
    required this.interruptedIntervals,
    required this.plannedFocusIntervals,
  });

  final int completedTasks;
  final int completedFocusIntervals;
  final int totalFocusSeconds;
  final int interruptedIntervals;
  final int plannedFocusIntervals;
}

class StartFocusRunInput {
  const StartFocusRunInput({
    this.taskId,
    this.projectId,
    this.presetId,
    this.targetWorkIntervals,
    this.note,
  });

  final String? taskId;
  final String? projectId;
  final String? presetId;
  final int? targetWorkIntervals;
  final String? note;
}

class CreateFocusPresetInput {
  const CreateFocusPresetInput({
    required this.name,
    required this.workSeconds,
    required this.shortBreakSeconds,
    required this.longBreakSeconds,
    required this.intervalsBeforeLongBreak,
    this.autoStartBreaks = false,
    this.autoStartWork = false,
    this.allowPause = true,
    this.strictMode = false,
  });

  final String name;
  final int workSeconds;
  final int shortBreakSeconds;
  final int longBreakSeconds;
  final int intervalsBeforeLongBreak;
  final bool autoStartBreaks;
  final bool autoStartWork;
  final bool allowPause;
  final bool strictMode;
}

class UpdateFocusPresetInput {
  const UpdateFocusPresetInput({
    required this.name,
    required this.workSeconds,
    required this.shortBreakSeconds,
    required this.longBreakSeconds,
    required this.intervalsBeforeLongBreak,
    required this.autoStartBreaks,
    required this.autoStartWork,
    required this.allowPause,
    required this.strictMode,
  });

  final String name;
  final int workSeconds;
  final int shortBreakSeconds;
  final int longBreakSeconds;
  final int intervalsBeforeLongBreak;
  final bool autoStartBreaks;
  final bool autoStartWork;
  final bool allowPause;
  final bool strictMode;
}

enum StopFocusReason { stopped, interrupted }

abstract interface class FocusRepository {
  Stream<List<FocusPresetItem>> watchPresets();
  Stream<FocusRunItem?> watchActiveRun();
  Stream<FocusIntervalItem?> watchActiveInterval();
  Stream<List<FocusRunItem>> watchRunsForTask(String taskId);
  Stream<List<FocusIntervalItem>> watchIntervalsForTask(String taskId);
  Stream<List<FocusIntervalItem>> watchIntervalsForRun(String runId);
  Stream<FocusDailyStats> watchDailyStats(DateTime localDate);
  Future<String> createPreset(CreateFocusPresetInput input);
  Future<void> updatePreset(String id, UpdateFocusPresetInput input);
  Future<void> deletePreset(String id);
  Future<void> setDefaultPreset(String id);
  Future<void> changeActiveRunPreset(String presetId);
  Future<String> startRun(StartFocusRunInput input, {DateTime? now});
  Future<void> startReadyInterval();
  Future<void> pauseActiveInterval({DateTime? now});
  Future<void> resumeActiveInterval({DateTime? now});
  Future<void> restartActiveInterval({DateTime? now});
  Future<void> completeActiveInterval({DateTime? now});
  Future<void> skipActiveInterval({DateTime? now});
  Future<void> stopActiveRun({required StopFocusReason reason, DateTime? now});
  Future<void> logDistraction({required String runId, String? note});
}

FocusPresetItem? selectedFocusPresetOrDefault(
  List<FocusPresetItem> presets,
  String? selectedId,
) {
  for (final preset in presets) {
    if (preset.id == selectedId) {
      return preset;
    }
  }
  for (final preset in presets) {
    if (preset.isDefault) {
      return preset;
    }
  }
  return presets.isEmpty ? null : presets.first;
}

int estimateFocusIntervalsForDuration({
  required Duration duration,
  required FocusPresetItem preset,
}) {
  final seconds = duration.inSeconds;
  if (seconds < preset.workSeconds) {
    return 0;
  }

  final cadence = preset.intervalsBeforeLongBreak < 1
      ? 1
      : preset.intervalsBeforeLongBreak;
  var elapsed = 0;
  var intervals = 0;
  while (true) {
    final nextInterval = intervals + 1;
    final breakSeconds = nextInterval % cadence == 0
        ? preset.longBreakSeconds
        : preset.shortBreakSeconds;
    final nextElapsed = elapsed + preset.workSeconds + breakSeconds;
    if (nextElapsed > seconds) {
      break;
    }
    elapsed = nextElapsed;
    intervals = nextInterval;
  }

  return intervals == 0 ? 1 : intervals;
}
