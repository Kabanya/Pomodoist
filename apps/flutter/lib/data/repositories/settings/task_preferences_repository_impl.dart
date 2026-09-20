import 'dart:async';

import 'package:pomodoist/data/repositories/settings/task_preferences_repository.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'package:pomodoist/domain/models/tasks/task_time.dart';
import 'package:pomodoist/utils/result.dart';

class LocalTaskPreferencesRepository implements TaskPreferencesRepository {
  LocalTaskPreferencesRepository(this._preferences);
  final PreferencesService _preferences;
  final _states = StreamController<TaskPreferences>.broadcast(sync: true);
  final _edited = <String>{};
  bool _disposed = false;
  TaskPreferences _state = TaskPreferences();

  @override
  TaskPreferences get state => _state;

  @override
  Stream<TaskPreferences> watch() => _states.stream;

  void _publish(TaskPreferences value) {
    if (_disposed) return;
    _state = value;
    _states.add(value);
  }

  @override
  Future<Result<void>> load() => Result.capture(() async {
    final values = (await _preferences.read(const [
      reengagementNotificationsEnabledPreferenceKey,
      quickAddDefaultTimedBlockMinutesPreferenceKey,
      taskTimeDisplayModePreferenceKey,
      taskListStylePreferenceKey,
      taskRowSpacingPreferenceKey,
      timelineVisibleStartMinutesPreferenceKey,
      timelineVisibleEndMinutesPreferenceKey,
      timelineHourWidthPreferenceKey,
      timelineCollapsedProjectIdsPreferenceKey,
    ])).getOrThrow();
    if (_disposed) return;
    values.removeWhere((key, _) => _edited.contains(key));
    final minutes = values[quickAddDefaultTimedBlockMinutesPreferenceKey];
    final start = values[timelineVisibleStartMinutesPreferenceKey];
    final end = values[timelineVisibleEndMinutesPreferenceKey];
    final width = values[timelineHourWidthPreferenceKey];
    final collapsed = values[timelineCollapsedProjectIdsPreferenceKey];
    _publish(
      _state.copyWith(
        reengagementEnabled:
            values[reengagementNotificationsEnabledPreferenceKey] is bool
            ? values[reengagementNotificationsEnabledPreferenceKey] as bool
            : null,
        quickAddMinutes:
            minutes is int &&
                minutes >= minQuickAddTimedBlockMinutes &&
                minutes <= maxQuickAddTimedBlockMinutes
            ? minutes
            : null,
        timeDisplayMode: values[taskTimeDisplayModePreferenceKey] is String
            ? TaskTimeDisplayMode.fromStorageValue(
                values[taskTimeDisplayModePreferenceKey] as String,
              )
            : null,
        listStyle: TaskListStyle.values
            .where((v) => v.name == values[taskListStylePreferenceKey])
            .firstOrNull,
        rowSpacing: TaskRowSpacing.values
            .where((v) => v.name == values[taskRowSpacingPreferenceKey])
            .firstOrNull,
        visibleHours: start is int && end is int && _validHours(start, end)
            ? TimelineVisibleHours(startMinutes: start, endMinutes: end)
            : null,
        hourWidth: width is int && timelineHourWidthLevels.contains(width)
            ? width
            : null,
        collapsedProjectIds: collapsed is List<String>
            ? Set.unmodifiable(collapsed)
            : null,
      ),
    );
  });

  Future<Result<void>> _save(
    TaskPreferences next,
    Map<String, Object?> values,
  ) {
    if (_disposed) return Future.value(const Result.ok(null));
    _edited.addAll(values.keys);
    _publish(next);
    return _preferences.write(values);
  }

  @override
  Future<Result<void>> setReengagementEnabled(bool enabled) => _save(
    state.copyWith(reengagementEnabled: enabled),
    {reengagementNotificationsEnabledPreferenceKey: enabled},
  );
  @override
  Future<Result<void>> setQuickAddMinutes(int minutes) {
    if (minutes < minQuickAddTimedBlockMinutes ||
        minutes > maxQuickAddTimedBlockMinutes) {
      return Future.value(const Result.ok(null));
    }
    return _save(state.copyWith(quickAddMinutes: minutes), {
      quickAddDefaultTimedBlockMinutesPreferenceKey: minutes,
    });
  }

  @override
  Future<Result<void>> setTimeDisplayMode(TaskTimeDisplayMode mode) => _save(
    state.copyWith(timeDisplayMode: mode),
    {taskTimeDisplayModePreferenceKey: mode.storageValue},
  );
  @override
  Future<Result<void>> setListStyle(TaskListStyle style) => _save(
    state.copyWith(listStyle: style),
    {taskListStylePreferenceKey: style.name},
  );
  @override
  Future<Result<void>> setRowSpacing(TaskRowSpacing spacing) => _save(
    state.copyWith(rowSpacing: spacing),
    {taskRowSpacingPreferenceKey: spacing.name},
  );
  bool _validHours(int start, int end) =>
      start >= 0 &&
      end <= 1440 &&
      start < end &&
      start % timelineSnapMinutes == 0 &&
      end % timelineSnapMinutes == 0;
  @override
  Future<Result<void>> setVisibleHours(int startMinutes, int endMinutes) {
    if (!_validHours(startMinutes, endMinutes)) {
      return Future.value(const Result.ok(null));
    }
    return _save(
      state.copyWith(
        visibleHours: TimelineVisibleHours(
          startMinutes: startMinutes,
          endMinutes: endMinutes,
        ),
      ),
      {
        timelineVisibleStartMinutesPreferenceKey: startMinutes,
        timelineVisibleEndMinutesPreferenceKey: endMinutes,
      },
    );
  }

  @override
  Future<Result<void>> setHourWidth(int width) {
    if (!timelineHourWidthLevels.contains(width)) {
      return Future.value(const Result.ok(null));
    }
    return _save(state.copyWith(hourWidth: width), {
      timelineHourWidthPreferenceKey: width,
    });
  }

  @override
  Future<Result<void>> zoomIn() => _zoom(1);
  @override
  Future<Result<void>> zoomOut() => _zoom(-1);
  Future<Result<void>> _zoom(int delta) => setHourWidth(
    timelineHourWidthLevels[(timelineHourWidthLevels.indexOf(state.hourWidth) +
            delta)
        .clamp(0, timelineHourWidthLevels.length - 1)],
  );
  @override
  Future<Result<void>> toggleCollapsedProject(String projectId) {
    final next = {...state.collapsedProjectIds};
    if (!next.remove(projectId)) next.add(projectId);
    return _save(state.copyWith(collapsedProjectIds: Set.unmodifiable(next)), {
      timelineCollapsedProjectIdsPreferenceKey: next.toList()..sort(),
    });
  }

  void dispose() {
    _disposed = true;
    _states.close();
  }
}
