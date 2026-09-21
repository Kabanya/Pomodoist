import 'package:pomodoist/domain/models/planning/task_decomposition.dart';
import 'package:pomodoist/domain/models/productivity/achievement_models.dart';

DecomposedTaskDraft buildDecomposedTaskDraft({
  String quickAdd = 'Buy milk',
  String? description,
  List<DecomposedTaskDraft> subtasks = const [],
}) {
  return DecomposedTaskDraft(
    quickAdd: quickAdd,
    description: description,
    subtasks: subtasks,
  );
}

/// Builds [count] drafts numbered from 1, so every item has a distinct
/// `quickAdd` and stable ordering across runs.
List<DecomposedTaskDraft> buildDecomposedTaskDrafts(
  int count, {
  String prefix = 'Task',
  String? description,
}) {
  return List.generate(
    count,
    (index) => buildDecomposedTaskDraft(
      quickAdd: '$prefix ${index + 1}',
      description: description,
    ),
    growable: false,
  );
}

TaskDecompositionException buildTaskDecompositionException({
  String message = 'Decomposition failed',
}) {
  return TaskDecompositionException(message);
}

AchievementItem buildAchievement({
  String id = 'focus_1',
  AchievementGroup group = AchievementGroup.focus,
  AchievementPresentation presentation = AchievementPresentation.globalBanner,
  int progress = 0,
  int target = 1,
}) {
  return AchievementItem(
    id: id,
    group: group,
    presentation: presentation,
    progress: progress,
    target: target,
  );
}

/// Builds [count] achievements with distinct `achievement_<n>` ids, so every
/// item is individually addressable across runs.
List<AchievementItem> buildAchievements(
  int count, {
  AchievementGroup group = AchievementGroup.focus,
  AchievementPresentation presentation = AchievementPresentation.globalBanner,
  int progress = 0,
  int target = 1,
}) {
  return List.generate(
    count,
    (index) => buildAchievement(
      id: 'achievement_${index + 1}',
      group: group,
      presentation: presentation,
      progress: progress,
      target: target,
    ),
    growable: false,
  );
}
