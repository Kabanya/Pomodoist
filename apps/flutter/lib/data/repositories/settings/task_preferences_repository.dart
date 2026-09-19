import 'package:flutter/foundation.dart';
import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'package:pomodoist/domain/models/tasks/task_time.dart';
import 'package:pomodoist/utils/result.dart';

abstract interface class TaskPreferencesRepository implements Listenable {
  TaskPreferences get state;
  Future<Result<void>> load();
  Future<Result<void>> setReengagementEnabled(bool enabled);
  Future<Result<void>> setQuickAddMinutes(int minutes);
  Future<Result<void>> setTimeDisplayMode(TaskTimeDisplayMode mode);
  Future<Result<void>> setListStyle(TaskListStyle style);
  Future<Result<void>> setRowSpacing(TaskRowSpacing spacing);
  Future<Result<void>> setVisibleHours(int startMinutes, int endMinutes);
  Future<Result<void>> setHourWidth(int width);
  Future<Result<void>> zoomIn();
  Future<Result<void>> zoomOut();
  Future<Result<void>> toggleCollapsedProject(String projectId);
}
