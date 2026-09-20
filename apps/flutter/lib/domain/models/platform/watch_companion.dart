import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/models/planning/task_decomposition.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

enum WatchAction {
  createTask,
  decomposeTranscript,
  commitDrafts,
  completeTask,
  uncompleteTask,
  startFocus,
  pauseFocus,
  resumeFocus,
  restartInterval,
  completeInterval,
  skipInterval,
  stopFocus,
  snapshot,
}

class WatchCommand {
  WatchCommand({
    required this.action,
    this.id,
    this.input = '',
    this.taskId,
    this.presetId,
    this.replaceActive = false,
    this.occurredAt,
    this.locale,
    Iterable<DecomposedTaskDraft> drafts = const [],
  }) : drafts = List.unmodifiable(drafts);

  final WatchAction action;
  final String? id;
  final String input;
  final String? taskId;
  final String? presetId;
  final bool replaceActive;
  final DateTime? occurredAt;
  final String? locale;
  final List<DecomposedTaskDraft> drafts;
}

class WatchSnapshot {
  WatchSnapshot({
    required this.generatedAt,
    required this.locale,
    required this.run,
    required this.interval,
    required this.preset,
    required Map<String, List<TaskItem>> taskLists,
    required Map<String, List<TaskItem>> tasksByProject,
    required Iterable<ProjectItem> projects,
    required Map<String, int> projectCounts,
    required Iterable<String> appliedCommandIds,
  }) : taskLists = Map.unmodifiable({
         for (final e in taskLists.entries)
           e.key: List<TaskItem>.unmodifiable(e.value),
       }),
       tasksByProject = Map.unmodifiable({
         for (final e in tasksByProject.entries)
           e.key: List<TaskItem>.unmodifiable(e.value),
       }),
       projects = List.unmodifiable(projects),
       projectCounts = Map.unmodifiable(projectCounts),
       appliedCommandIds = List.unmodifiable(appliedCommandIds);

  final DateTime generatedAt;
  final String locale;
  final FocusRunItem? run;
  final FocusIntervalItem? interval;
  final FocusPresetItem? preset;
  final Map<String, List<TaskItem>> taskLists;
  final Map<String, List<TaskItem>> tasksByProject;
  final List<ProjectItem> projects;
  final Map<String, int> projectCounts;
  final List<String> appliedCommandIds;
}

class WatchCommandResult {
  WatchCommandResult({
    required this.ok,
    this.conflict = false,
    this.error,
    this.snapshot,
    this.appliedCommandId,
    this.createdId,
    Iterable<String>? createdTaskIds,
    Iterable<DecomposedTaskDraft>? drafts,
  }) : createdTaskIds = createdTaskIds == null
           ? null
           : List.unmodifiable(createdTaskIds),
       drafts = drafts == null ? null : List.unmodifiable(drafts);

  final bool ok;
  final bool conflict;
  final Object? error;
  final WatchSnapshot? snapshot;
  final String? appliedCommandId;
  final String? createdId;
  final List<String>? createdTaskIds;
  final List<DecomposedTaskDraft>? drafts;
}
