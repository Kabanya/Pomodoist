import 'package:pomodoist/domain/models/focus/focus_models.dart';

/// Fixed instant every fixture timestamp defaults to.
final DateTime focusFixtureNow = DateTime.utc(2026, 1, 1, 12);

/// Owner id the local database assigns to rows it creates itself.
const focusFixtureUserId = 'local-user';

/// The shipped "Classic" preset: 25/5/15 minutes over four intervals.
FocusPresetItem focusPresetPomodoro() => buildFocusPreset(isDefault: true);

/// The shipped "Deep Work" preset: 50/10/25 minutes over four intervals.
FocusPresetItem focusPresetDeepWork() => buildFocusPreset(
  id: deepWorkPresetId,
  name: 'Deep Work',
  workSeconds: 50 * 60,
  shortBreakSeconds: 10 * 60,
  longBreakSeconds: 25 * 60,
);

FocusPresetItem buildFocusPreset({
  String id = defaultPresetId,
  String userId = focusFixtureUserId,
  String name = 'Classic',
  int workSeconds = 25 * 60,
  int shortBreakSeconds = 5 * 60,
  int longBreakSeconds = 15 * 60,
  int intervalsBeforeLongBreak = 4,
  bool autoStartBreaks = false,
  bool autoStartWork = false,
  bool allowPause = true,
  bool strictMode = false,
  bool isDefault = false,
  DateTime? createdAt,
  DateTime? updatedAt,
}) => FocusPresetItem(
  id: id,
  userId: userId,
  name: name,
  workSeconds: workSeconds,
  shortBreakSeconds: shortBreakSeconds,
  longBreakSeconds: longBreakSeconds,
  intervalsBeforeLongBreak: intervalsBeforeLongBreak,
  autoStartBreaks: autoStartBreaks,
  autoStartWork: autoStartWork,
  allowPause: allowPause,
  strictMode: strictMode,
  isDefault: isDefault,
  createdAt: createdAt ?? focusFixtureNow,
  updatedAt: updatedAt ?? focusFixtureNow,
);

FocusRunItem buildFocusRun({
  String id = 'run-1',
  String userId = focusFixtureUserId,
  String? taskId,
  String? projectId,
  String presetId = defaultPresetId,
  String status = 'active',
  DateTime? startedAt,
  DateTime? endedAt,
  int targetWorkIntervals = 4,
  int completedWorkIntervals = 0,
  String? note,
  DateTime? createdAt,
  DateTime? updatedAt,
}) => FocusRunItem(
  id: id,
  userId: userId,
  taskId: taskId,
  projectId: projectId,
  presetId: presetId,
  status: status,
  startedAt: startedAt ?? focusFixtureNow,
  endedAt: endedAt,
  targetWorkIntervals: targetWorkIntervals,
  completedWorkIntervals: completedWorkIntervals,
  note: note,
  createdAt: createdAt ?? focusFixtureNow,
  updatedAt: updatedAt ?? focusFixtureNow,
);

FocusRunCompletionEvent buildFocusRunCompletionEvent({
  String runId = 'run-1',
  String? taskId,
  String? taskTitle,
  int completedWorkIntervals = 4,
  int targetWorkIntervals = 4,
  DateTime? completedAt,
}) => FocusRunCompletionEvent(
  runId: runId,
  taskId: taskId,
  taskTitle: taskTitle,
  completedWorkIntervals: completedWorkIntervals,
  targetWorkIntervals: targetWorkIntervals,
  completedAt: completedAt ?? focusFixtureNow,
);

FocusIntervalItem buildFocusInterval({
  String id = 'interval-1',
  String runId = 'run-1',
  String? taskId,
  String? projectId,
  String type = 'work',
  String status = 'running',
  int plannedSeconds = 25 * 60,
  DateTime? startedAt,
  DateTime? pausedAt,
  int pausedTotalSeconds = 0,
  DateTime? completedAt,
  DateTime? stoppedAt,
  int sequenceNumber = 1,
  DateTime? createdAt,
  DateTime? updatedAt,
}) => FocusIntervalItem(
  id: id,
  runId: runId,
  taskId: taskId,
  projectId: projectId,
  type: type,
  status: status,
  plannedSeconds: plannedSeconds,
  startedAt: startedAt ?? focusFixtureNow,
  pausedAt: pausedAt,
  pausedTotalSeconds: pausedTotalSeconds,
  completedAt: completedAt,
  stoppedAt: stoppedAt,
  sequenceNumber: sequenceNumber,
  createdAt: createdAt ?? focusFixtureNow,
  updatedAt: updatedAt ?? focusFixtureNow,
);

FocusDailyStats buildFocusDailyStats({
  int completedTasks = 0,
  int completedFocusIntervals = 0,
  int totalFocusSeconds = 0,
  int interruptedIntervals = 0,
  int plannedFocusIntervals = 0,
}) => FocusDailyStats(
  completedTasks: completedTasks,
  completedFocusIntervals: completedFocusIntervals,
  totalFocusSeconds: totalFocusSeconds,
  interruptedIntervals: interruptedIntervals,
  plannedFocusIntervals: plannedFocusIntervals,
);

StartFocusRunInput buildStartFocusRunInput({
  String? taskId,
  String? projectId,
  String? presetId,
  int? targetWorkIntervals,
  String? note,
}) => StartFocusRunInput(
  taskId: taskId,
  projectId: projectId,
  presetId: presetId,
  targetWorkIntervals: targetWorkIntervals,
  note: note,
);

CreateFocusPresetInput buildCreateFocusPresetInput({
  String name = 'Classic',
  int workSeconds = 25 * 60,
  int shortBreakSeconds = 5 * 60,
  int longBreakSeconds = 15 * 60,
  int intervalsBeforeLongBreak = 4,
  bool autoStartBreaks = false,
  bool autoStartWork = false,
  bool allowPause = true,
  bool strictMode = false,
}) => CreateFocusPresetInput(
  name: name,
  workSeconds: workSeconds,
  shortBreakSeconds: shortBreakSeconds,
  longBreakSeconds: longBreakSeconds,
  intervalsBeforeLongBreak: intervalsBeforeLongBreak,
  autoStartBreaks: autoStartBreaks,
  autoStartWork: autoStartWork,
  allowPause: allowPause,
  strictMode: strictMode,
);

UpdateFocusPresetInput buildUpdateFocusPresetInput({
  String name = 'Classic',
  int workSeconds = 25 * 60,
  int shortBreakSeconds = 5 * 60,
  int longBreakSeconds = 15 * 60,
  int intervalsBeforeLongBreak = 4,
  bool autoStartBreaks = false,
  bool autoStartWork = false,
  bool allowPause = true,
  bool strictMode = false,
}) => UpdateFocusPresetInput(
  name: name,
  workSeconds: workSeconds,
  shortBreakSeconds: shortBreakSeconds,
  longBreakSeconds: longBreakSeconds,
  intervalsBeforeLongBreak: intervalsBeforeLongBreak,
  autoStartBreaks: autoStartBreaks,
  autoStartWork: autoStartWork,
  allowPause: allowPause,
  strictMode: strictMode,
);
