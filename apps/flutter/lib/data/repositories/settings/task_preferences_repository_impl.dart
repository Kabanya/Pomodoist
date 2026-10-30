import 'dart:async';
import 'dart:convert';

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
  Future<Result<void>>? _loadFuture;
  Future<Result<void>> _branchWrites = Future.value(const Result.ok(null));
  Future<Result<void>> _projectModeWrites = Future.value(const Result.ok(null));
  Future<Result<void>> _branchStyleWrites = Future.value(const Result.ok(null));
  Future<Result<void>> _detailLayoutWrites = Future.value(
    const Result.ok(null),
  );
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
  Future<Result<void>> load({bool reload = false}) {
    if (reload) {
      _edited.clear();
      _loadFuture = null;
    }
    return _loadFuture ??= _load(reload: reload).then((result) {
      if (result is Failure<void>) _loadFuture = null;
      return result;
    });
  }

  Future<Result<void>> _load({bool reload = false}) => Result.capture(() async {
    final values = (await _preferences.read(const [
      reengagementNotificationsEnabledPreferenceKey,
      quickAddDefaultTimedBlockMinutesPreferenceKey,
      taskTimeDisplayModePreferenceKey,
      taskListStylePreferenceKey,
      taskDetailLayoutPreferenceKey,
      projectViewModePreferenceKey,
      projectCatalogViewModePreferenceKey,
      taskRowSpacingPreferenceKey,
      taskBranchStylePreferenceKey,
      taskBranchExpansionPreferenceKey,
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
    final branches = _readBranchExpansion(
      values[taskBranchExpansionPreferenceKey],
    );
    for (final entry in _state.branchExpansion.entries) {
      branches[entry.key] = {...?branches[entry.key], ...entry.value};
    }
    final base = reload && _edited.isEmpty ? TaskPreferences() : _state;
    _publish(
      base.copyWith(
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
        projectViewMode: ProjectViewMode.values
            .where((v) => v.name == values[projectViewModePreferenceKey])
            .firstOrNull,
        projectCatalogViewMode: ProjectViewMode.values
            .where((v) => v.name == values[projectCatalogViewModePreferenceKey])
            .firstOrNull,
        detailLayout: TaskDetailLayout.values
            .where((v) => v.name == values[taskDetailLayoutPreferenceKey])
            .firstOrNull,
        listStyle: TaskListStyle.values
            .where((v) => v.name == values[taskListStylePreferenceKey])
            .firstOrNull,
        branchStyle: TaskBranchStyle.values
            .where((v) => v.name == values[taskBranchStylePreferenceKey])
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
        branchExpansion: branches,
      ),
    );
  });

  Map<String, Map<String, bool>> _readBranchExpansion(Object? value) {
    if (value is! String) return {};
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map ||
          decoded['version'] != 1 ||
          decoded['scopes'] is! Map) {
        return {};
      }
      return {
        for (final scope in (decoded['scopes'] as Map).entries)
          if (scope.key is String &&
              (scope.key as String).isNotEmpty &&
              scope.value is Map)
            scope.key as String: {
              for (final task in (scope.value as Map).entries)
                if (task.key is String &&
                    (task.key as String).isNotEmpty &&
                    task.value is bool)
                  task.key as String: task.value as bool,
            },
      };
    } on FormatException {
      return {};
    }
  }

  @override
  Future<Result<void>> setBranchExpanded(
    String scopeKey,
    String taskId,
    bool expanded,
  ) {
    if (_disposed || scopeKey.isEmpty || taskId.isEmpty) {
      return Future.value(const Result.ok(null));
    }
    _publish(
      state.copyWith(
        branchExpansion: {
          ...state.branchExpansion,
          scopeKey: {...?state.branchExpansion[scopeKey], taskId: expanded},
        },
      ),
    );
    // Load untouched scopes before writing, and keep rapid toggles in order.
    return _branchWrites = _branchWrites.then(
      (_) => Result.capture(() async {
        (await load()).getOrThrow();
        if (_disposed) return;
        (await _preferences.write({
          taskBranchExpansionPreferenceKey: jsonEncode({
            'version': 1,
            'scopes': state.branchExpansion,
          }),
        })).getOrThrow();
      }),
    );
  }

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
  Future<Result<void>> setProjectViewMode(ProjectViewMode mode) =>
      _saveProjectMode(
        state.copyWith(projectViewMode: mode),
        projectViewModePreferenceKey,
        mode,
      );
  @override
  Future<Result<void>> setProjectCatalogViewMode(ProjectViewMode mode) =>
      _saveProjectMode(
        state.copyWith(projectCatalogViewMode: mode),
        projectCatalogViewModePreferenceKey,
        mode,
      );
  Future<Result<void>> _saveProjectMode(
    TaskPreferences next,
    String key,
    ProjectViewMode mode,
  ) {
    if (_disposed) return Future.value(const Result.ok(null));
    _edited.add(key);
    _publish(next);
    return _projectModeWrites = _projectModeWrites.then(
      (_) => _preferences.write({key: mode.name}),
    );
  }

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
  @override
  Future<Result<void>> setBranchStyle(TaskBranchStyle style) {
    if (_disposed) return Future.value(const Result.ok(null));
    _edited.add(taskBranchStylePreferenceKey);
    _publish(state.copyWith(branchStyle: style));
    return _branchStyleWrites = _branchStyleWrites.then(
      (_) => Result.capture(() async {
        (await _preferences.write({
          taskBranchStylePreferenceKey: style.name,
        })).getOrThrow();
      }),
    );
  }

  @override
  Future<Result<void>> setDetailLayout(TaskDetailLayout layout) {
    if (_disposed) return Future.value(const Result.ok(null));
    _edited.add(taskDetailLayoutPreferenceKey);
    _publish(state.copyWith(detailLayout: layout));
    return _detailLayoutWrites = _detailLayoutWrites.then(
      (_) => _preferences.write({taskDetailLayoutPreferenceKey: layout.name}),
    );
  }

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
