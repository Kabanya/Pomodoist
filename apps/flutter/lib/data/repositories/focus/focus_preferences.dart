import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pomodoist/domain/models/focus/focus_view_mode.dart';
import 'package:pomodoist/utils/result.dart';

const focusViewModePreferenceKey = 'focus.viewMode';
const focusTimerVisualStylePreferenceKey = 'focus.timerVisualStyle';
const lastFocusPresetIdPreferenceKey = 'focus.lastPresetId';
const focusCompletionCelebrationEnabledPreferenceKey =
    'focus.completionCelebration.enabled';

class FocusPreferencesState {
  const FocusPreferencesState({
    this.viewMode = FocusViewMode.minimal,
    this.timerStyle = FocusTimerVisualStyle.circle,
    this.lastPresetId,
    this.celebrationEnabled = true,
  });
  final FocusViewMode viewMode;
  final FocusTimerVisualStyle timerStyle;
  final String? lastPresetId;
  final bool celebrationEnabled;
}

class FocusPreferencesRepository extends ChangeNotifier {
  FocusPreferencesRepository(this._preferences);
  final Future<SharedPreferences?> Function() _preferences;
  FocusPreferencesState _state = const FocusPreferencesState();
  FocusPreferencesState get state => _state;
  final _changed = <String>{};
  bool _disposed = false;
  int _generation = 0;
  void _publish(FocusPreferencesState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  Future<Result<void>> load() => Result.capture(() async {
    final generation = _generation;
    final prefs = await _preferences();
    if (_disposed || generation != _generation) return;
    _publish(
      FocusPreferencesState(
        viewMode: _changed.contains(focusViewModePreferenceKey)
            ? state.viewMode
            : FocusViewMode.fromStorageValue(
                prefs?.getString(focusViewModePreferenceKey),
              ),
        timerStyle: _changed.contains(focusTimerVisualStylePreferenceKey)
            ? state.timerStyle
            : FocusTimerVisualStyle.fromStorageValue(
                prefs?.getString(focusTimerVisualStylePreferenceKey),
              ),
        lastPresetId: _changed.contains(lastFocusPresetIdPreferenceKey)
            ? state.lastPresetId
            : prefs?.getString(lastFocusPresetIdPreferenceKey),
        celebrationEnabled:
            _changed.contains(focusCompletionCelebrationEnabledPreferenceKey)
            ? state.celebrationEnabled
            : prefs?.getBool(focusCompletionCelebrationEnabledPreferenceKey) ??
                  true,
      ),
    );
  });
  Future<Result<void>> setViewMode(FocusViewMode value) =>
      Result.capture(() async {
        _changed.add(focusViewModePreferenceKey);
        _publish(
          FocusPreferencesState(
            viewMode: value,
            timerStyle: state.timerStyle,
            lastPresetId: state.lastPresetId,
            celebrationEnabled: state.celebrationEnabled,
          ),
        );
        await (await _preferences())?.setString(
          focusViewModePreferenceKey,
          value.storageValue,
        );
      });
  Future<Result<void>> setTimerStyle(FocusTimerVisualStyle value) =>
      Result.capture(() async {
        _changed.add(focusTimerVisualStylePreferenceKey);
        _publish(
          FocusPreferencesState(
            viewMode: state.viewMode,
            timerStyle: value,
            lastPresetId: state.lastPresetId,
            celebrationEnabled: state.celebrationEnabled,
          ),
        );
        await (await _preferences())?.setString(
          focusTimerVisualStylePreferenceKey,
          value.storageValue,
        );
      });
  Future<Result<void>> setPresetId(String? value) => Result.capture(() async {
    _changed.add(lastFocusPresetIdPreferenceKey);
    _publish(
      FocusPreferencesState(
        viewMode: state.viewMode,
        timerStyle: state.timerStyle,
        lastPresetId: value,
        celebrationEnabled: state.celebrationEnabled,
      ),
    );
    final prefs = await _preferences();
    if (value == null || value.trim().isEmpty) {
      await prefs?.remove(lastFocusPresetIdPreferenceKey);
    } else {
      await prefs?.setString(lastFocusPresetIdPreferenceKey, value);
    }
  });
  Future<Result<void>> setCelebrationEnabled(bool value) =>
      Result.capture(() async {
        _changed.add(focusCompletionCelebrationEnabledPreferenceKey);
        _publish(
          FocusPreferencesState(
            viewMode: state.viewMode,
            timerStyle: state.timerStyle,
            lastPresetId: state.lastPresetId,
            celebrationEnabled: value,
          ),
        );
        await (await _preferences())?.setBool(
          focusCompletionCelebrationEnabledPreferenceKey,
          value,
        );
      });
  Future<Result<void>> clear() => Result.capture(() async {
    ++_generation;
    _changed.clear();
    final prefs = await _preferences();
    for (final key in [
      focusViewModePreferenceKey,
      focusTimerVisualStylePreferenceKey,
      lastFocusPresetIdPreferenceKey,
      focusCompletionCelebrationEnabledPreferenceKey,
    ]) {
      await prefs?.remove(key);
    }
    _publish(const FocusPreferencesState());
  });
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
