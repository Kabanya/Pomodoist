import 'dart:async';

import 'package:pomodoist/data/repositories/focus/focus_preferences_repository.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/domain/models/focus/focus_view_mode.dart';
import 'package:pomodoist/utils/result.dart';

class StoredFocusPreferencesRepository implements FocusPreferencesRepository {
  StoredFocusPreferencesRepository(this._preferences);
  final PreferencesService _preferences;
  final _states = StreamController<FocusPreferencesState>.broadcast(sync: true);
  FocusPreferencesState _state = const FocusPreferencesState();
  @override
  FocusPreferencesState get state => _state;
  @override
  Stream<FocusPreferencesState> watch() => _states.stream;
  final _changed = <String>{};
  bool _disposed = false;
  int _generation = 0;
  void _publish(FocusPreferencesState value) {
    if (_disposed) return;
    _state = value;
    _states.add(value);
  }

  @override
  Future<Result<void>> load() => Result.capture(() async {
    final generation = _generation;
    final values = (await _preferences.read(const [
      focusViewModePreferenceKey,
      focusTimerVisualStylePreferenceKey,
      focusSessionDisplayPreferenceKey,
      lastFocusPresetIdPreferenceKey,
      focusCompletionCelebrationEnabledPreferenceKey,
    ])).getOrThrow();
    if (_disposed || generation != _generation) return;
    _publish(
      FocusPreferencesState(
        viewMode: _changed.contains(focusViewModePreferenceKey)
            ? state.viewMode
            : FocusViewMode.fromStorageValue(
                values[focusViewModePreferenceKey] as String?,
              ),
        timerStyle: _changed.contains(focusTimerVisualStylePreferenceKey)
            ? state.timerStyle
            : FocusTimerVisualStyle.fromStorageValue(
                values[focusTimerVisualStylePreferenceKey] as String?,
              ),
        sessionDisplay: _changed.contains(focusSessionDisplayPreferenceKey)
            ? state.sessionDisplay
            : FocusSessionDisplay.fromStorageValue(
                values[focusSessionDisplayPreferenceKey] as String?,
              ),
        lastPresetId: _changed.contains(lastFocusPresetIdPreferenceKey)
            ? state.lastPresetId
            : values[lastFocusPresetIdPreferenceKey] as String?,
        celebrationEnabled:
            _changed.contains(focusCompletionCelebrationEnabledPreferenceKey)
            ? state.celebrationEnabled
            : values[focusCompletionCelebrationEnabledPreferenceKey] as bool? ??
                  true,
      ),
    );
  });
  @override
  Future<Result<void>> setViewMode(FocusViewMode value) =>
      Result.capture(() async {
        _changed.add(focusViewModePreferenceKey);
        try {
          (await _preferences.write({
            focusViewModePreferenceKey: value.storageValue,
          })).getOrThrow();
          _publish(
            FocusPreferencesState(
              viewMode: value,
              timerStyle: state.timerStyle,
              sessionDisplay: state.sessionDisplay,
              lastPresetId: state.lastPresetId,
              celebrationEnabled: state.celebrationEnabled,
            ),
          );
        } catch (_) {
          _changed.remove(focusViewModePreferenceKey);
          rethrow;
        }
      });
  @override
  Future<Result<void>> setTimerStyle(FocusTimerVisualStyle value) =>
      Result.capture(() async {
        _changed.add(focusTimerVisualStylePreferenceKey);
        try {
          (await _preferences.write({
            focusTimerVisualStylePreferenceKey: value.storageValue,
          })).getOrThrow();
          _publish(
            FocusPreferencesState(
              viewMode: state.viewMode,
              timerStyle: value,
              sessionDisplay: state.sessionDisplay,
              lastPresetId: state.lastPresetId,
              celebrationEnabled: state.celebrationEnabled,
            ),
          );
        } catch (_) {
          _changed.remove(focusTimerVisualStylePreferenceKey);
          rethrow;
        }
      });
  @override
  Future<Result<void>> setSessionDisplay(FocusSessionDisplay value) =>
      Result.capture(() async {
        _changed.add(focusSessionDisplayPreferenceKey);
        try {
          (await _preferences.write({
            focusSessionDisplayPreferenceKey: value.storageValue,
          })).getOrThrow();
          _publish(
            FocusPreferencesState(
              viewMode: state.viewMode,
              timerStyle: state.timerStyle,
              sessionDisplay: value,
              lastPresetId: state.lastPresetId,
              celebrationEnabled: state.celebrationEnabled,
            ),
          );
        } catch (_) {
          _changed.remove(focusSessionDisplayPreferenceKey);
          rethrow;
        }
      });
  @override
  Future<Result<void>> setPresetId(String? value) => Result.capture(() async {
    _changed.add(lastFocusPresetIdPreferenceKey);
    try {
      (await _preferences.write({
        lastFocusPresetIdPreferenceKey: value,
      })).getOrThrow();
      _publish(
        FocusPreferencesState(
          viewMode: state.viewMode,
          timerStyle: state.timerStyle,
          sessionDisplay: state.sessionDisplay,
          lastPresetId: value,
          celebrationEnabled: state.celebrationEnabled,
        ),
      );
    } catch (_) {
      _changed.remove(lastFocusPresetIdPreferenceKey);
      rethrow;
    }
  });
  @override
  Future<Result<void>> setCelebrationEnabled(bool value) =>
      Result.capture(() async {
        _changed.add(focusCompletionCelebrationEnabledPreferenceKey);
        try {
          (await _preferences.write({
            focusCompletionCelebrationEnabledPreferenceKey: value,
          })).getOrThrow();
          _publish(
            FocusPreferencesState(
              viewMode: state.viewMode,
              timerStyle: state.timerStyle,
              sessionDisplay: state.sessionDisplay,
              lastPresetId: state.lastPresetId,
              celebrationEnabled: value,
            ),
          );
        } catch (_) {
          _changed.remove(focusCompletionCelebrationEnabledPreferenceKey);
          rethrow;
        }
      });
  @override
  Future<Result<void>> clear() => Result.capture(() async {
    ++_generation;
    _changed.clear();
    (await _preferences.write({
      focusViewModePreferenceKey: null,
      focusTimerVisualStylePreferenceKey: null,
      focusSessionDisplayPreferenceKey: null,
      lastFocusPresetIdPreferenceKey: null,
      focusCompletionCelebrationEnabledPreferenceKey: null,
    })).getOrThrow();
    _publish(const FocusPreferencesState());
  });

  @override
  void dispose() {
    _disposed = true;
    _states.close();
  }
}
