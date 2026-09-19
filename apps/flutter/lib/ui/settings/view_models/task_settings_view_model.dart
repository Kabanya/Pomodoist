import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/settings/task_preferences_repository.dart';
import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'package:pomodoist/domain/models/tasks/task_time.dart';

final taskListSettingsViewModelProvider =
    NotifierProvider<
      TaskListSettingsViewModel,
      ({TaskListStyle style, TaskRowSpacing spacing})
    >(TaskListSettingsViewModel.new);

class TaskListSettingsViewModel
    extends Notifier<({TaskListStyle style, TaskRowSpacing spacing})> {
  late TaskPreferencesRepository _repository;
  @override
  ({TaskListStyle style, TaskRowSpacing spacing}) build() {
    _repository = ref.watch(taskPreferencesRepositoryProvider);
    final preferences = ref.watch(taskPreferencesStateProvider);
    return (style: preferences.listStyle, spacing: preferences.rowSpacing);
  }

  Future<void> setStyle(TaskListStyle style) async =>
      (await _repository.setListStyle(style)).getOrThrow();
  Future<void> setSpacing(TaskRowSpacing spacing) async =>
      (await _repository.setRowSpacing(spacing)).getOrThrow();
}

final class TaskDurationSettingsState {
  const TaskDurationSettingsState({
    required this.minutes,
    required this.timeDisplayMode,
    this.invalidInput = false,
  });
  final int minutes;
  final TaskTimeDisplayMode timeDisplayMode;
  final bool invalidInput;
}

final taskDurationSettingsViewModelProvider =
    NotifierProvider.autoDispose<
      TaskDurationSettingsViewModel,
      TaskDurationSettingsState
    >(TaskDurationSettingsViewModel.new);

class TaskDurationSettingsViewModel
    extends Notifier<TaskDurationSettingsState> {
  late TaskPreferencesRepository _repository;
  @override
  TaskDurationSettingsState build() {
    _repository = ref.watch(taskPreferencesRepositoryProvider);
    final preferences = ref.watch(taskPreferencesStateProvider);
    return TaskDurationSettingsState(
      minutes: preferences.quickAddMinutes,
      timeDisplayMode: preferences.timeDisplayMode,
    );
  }

  Future<void> setMinutes(int value) async =>
      (await _repository.setQuickAddMinutes(value)).getOrThrow();
  Future<void> setTimeDisplayMode(TaskTimeDisplayMode mode) async =>
      (await _repository.setTimeDisplayMode(mode)).getOrThrow();
  Future<void> saveCustomMinutes(String raw) async {
    final minutes = int.tryParse(raw);
    if (minutes == null ||
        minutes < minQuickAddTimedBlockMinutes ||
        minutes > maxQuickAddTimedBlockMinutes) {
      state = TaskDurationSettingsState(
        minutes: state.minutes,
        timeDisplayMode: state.timeDisplayMode,
        invalidInput: true,
      );
      return;
    }
    state = TaskDurationSettingsState(
      minutes: state.minutes,
      timeDisplayMode: state.timeDisplayMode,
    );
    await setMinutes(minutes);
  }
}
