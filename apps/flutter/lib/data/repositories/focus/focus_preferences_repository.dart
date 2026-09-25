import 'package:pomodoist/domain/models/focus/focus_view_mode.dart';
import 'package:pomodoist/utils/result.dart';

const focusViewModePreferenceKey = 'focus.viewMode';
const focusTimerVisualStylePreferenceKey = 'focus.timerVisualStyle';
const focusSessionDisplayPreferenceKey = 'focus.sessionDisplay';
const lastFocusPresetIdPreferenceKey = 'focus.lastPresetId';
const focusCompletionCelebrationEnabledPreferenceKey =
    'focus.completionCelebration.enabled';

class FocusPreferencesState {
  const FocusPreferencesState({
    this.viewMode = FocusViewMode.minimal,
    this.timerStyle = FocusTimerVisualStyle.circle,
    this.sessionDisplay = FocusSessionDisplay.compact,
    this.lastPresetId,
    this.celebrationEnabled = true,
  });
  final FocusViewMode viewMode;
  final FocusTimerVisualStyle timerStyle;
  final FocusSessionDisplay sessionDisplay;
  final String? lastPresetId;
  final bool celebrationEnabled;
}

/// Persisted focus view, timer and session styles, preset and celebration.
///
/// [state] is the current snapshot; [watch] delivers later updates. Dirty keys
/// and load generations keep a late hydration from overwriting an edit, and the
/// owner calls [dispose] to close the source stream.
abstract interface class FocusPreferencesRepository {
  FocusPreferencesState get state;

  Stream<FocusPreferencesState> watch();

  Future<Result<void>> load();

  Future<Result<void>> setViewMode(FocusViewMode value);

  Future<Result<void>> setTimerStyle(FocusTimerVisualStyle value);

  Future<Result<void>> setSessionDisplay(FocusSessionDisplay value);

  Future<Result<void>> setPresetId(String? value);

  Future<Result<void>> setCelebrationEnabled(bool value);

  Future<Result<void>> clear();

  void dispose();
}
