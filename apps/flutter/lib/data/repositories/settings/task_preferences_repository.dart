import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'package:pomodoist/domain/models/tasks/task_time.dart';
import 'package:pomodoist/utils/result.dart';

abstract interface class TaskPreferencesRepository {
  /// Current persisted snapshot, read together with [watch] to avoid a gap.
  TaskPreferences get state;

  /// Later updates only; the repository owns and closes the source stream.
  Stream<TaskPreferences> watch();
  Future<Result<void>> load({bool reload = false});
  Future<Result<void>> setReengagementEnabled(bool enabled);
  Future<Result<void>> setQuickAddMinutes(int minutes);
  Future<Result<void>> setTimeDisplayMode(TaskTimeDisplayMode mode);
  Future<Result<void>> setProjectViewMode(ProjectViewMode mode);
  Future<Result<void>> setProjectCatalogViewMode(ProjectViewMode mode);
  Future<Result<void>> setDetailLayout(TaskDetailLayout layout);
  Future<Result<void>> setListStyle(TaskListStyle style);
  Future<Result<void>> setBranchStyle(TaskBranchStyle style);
  Future<Result<void>> setRowSpacing(TaskRowSpacing spacing);
  Future<Result<void>> setBranchExpanded(
    String scopeKey,
    String taskId,
    bool expanded,
  );
  Future<Result<void>> setVisibleHours(int startMinutes, int endMinutes);
  Future<Result<void>> setHourWidth(int width);
  Future<Result<void>> zoomIn();
  Future<Result<void>> zoomOut();
  Future<Result<void>> toggleCollapsedProject(String projectId);
}
