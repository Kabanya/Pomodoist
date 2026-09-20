import 'timeline_day_data.dart';
import 'timeline_project_layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository.dart';

typedef TimelineState = ({
  DateTime now,
  AsyncValue<List<TaskItem>> tasks,
  AsyncValue<List<ProjectItem>> projects,
  TimelineVisibleHours visibleHours,
  int hourWidth,
  Set<String> collapsed,
  Set<String> temporary,
});
final timelineViewModelProvider =
    NotifierProvider.autoDispose<TimelineViewModel, TimelineState>(
      TimelineViewModel.new,
    );

class TimelineViewModel extends Notifier<TimelineState> {
  Set<String> _temporary = const {};
  late TaskRepository _tasks;
  @override
  TimelineState build() {
    _tasks = ref.watch(taskRepositoryProvider);
    return (
      now:
          (ref.watch(taskTimeTickerProvider).value ??
                  ref.read(clockProvider).now())
              .toLocal(),
      tasks: ref.watch(tasksByQueryProvider(const TaskQuery.all())),
      projects: ref.watch(projectsProvider),
      visibleHours: ref.watch(timelineVisibleHoursProvider),
      hourWidth: ref.watch(timelineHourWidthProvider),
      collapsed: Set.unmodifiable(
        ref.watch(timelineCollapsedProjectIdsProvider),
      ),
      temporary: _temporary,
    );
  }

  void toggleTemporary(String id) {
    final next = {..._temporary};
    if (!next.remove(id)) next.add(id);
    _temporary = Set.unmodifiable(next);
    state = (
      now: state.now,
      tasks: state.tasks,
      projects: state.projects,
      visibleHours: state.visibleHours,
      hourWidth: state.hourWidth,
      collapsed: state.collapsed,
      temporary: _temporary,
    );
  }

  Future<void> setVisibleHours(int start, int end) async {
    (await ref
            .read(taskPreferencesRepositoryProvider)
            .setVisibleHours(start, end))
        .getOrThrow();
  }

  Future<void> setHourWidth(int width) async {
    (await ref.read(taskPreferencesRepositoryProvider).setHourWidth(width))
        .getOrThrow();
  }

  Future<void> zoomIn() async {
    (await ref.read(taskPreferencesRepositoryProvider).zoomIn()).getOrThrow();
  }

  Future<void> zoomOut() async {
    (await ref.read(taskPreferencesRepositoryProvider).zoomOut()).getOrThrow();
  }

  Future<void> toggleCollapsed(String id) async {
    (await ref
            .read(taskPreferencesRepositoryProvider)
            .toggleCollapsedProject(id))
        .getOrThrow();
  }

  Future<void> updateProject(String id, UpdateProjectPatch patch) async {
    (await ref.read(projectRepositoryProvider).updateProject(id, patch))
        .getOrThrow();
  }

  Future<String> create(
    String input, {
    String? projectId,
    required TaskSchedule schedule,
  }) async =>
      (await ref
              .read(quickAddUseCaseProvider)
              .createTask(
                input,
                projectId: projectId,
                defaultSchedule: schedule,
              ))
          .getOrThrow();
  Future<void> schedule(TaskItem task, TaskSchedule schedule) async {
    (await _tasks.updateTask(
      task.id,
      UpdateTaskPatch(schedule: preserveTimelineRecurrence(task, schedule)),
    )).getOrThrow();
  }

  Future<void> move(
    TaskItem task,
    DateTime day,
    int targetMinutes,
    String projectId,
  ) async {
    final existing = task.schedule;
    final duration = existing?.isTimed ?? false
        ? existing!.duration ?? const Duration(minutes: 30)
        : const Duration(minutes: 30);
    final minutes = duration.inMinutes.clamp(timelineSnapMinutes, 1440);
    final start = DateTime(
      day.year,
      day.month,
      day.day,
    ).add(Duration(minutes: targetMinutes.clamp(0, 1440 - minutes)));
    final next = preserveTimelineRecurrence(
      task,
      TaskSchedule.timed(
        start: start,
        end: start.add(Duration(minutes: minutes)),
      ),
    );
    if (task.projectId == projectId) {
      await schedule(task, next);
    } else {
      (await _tasks.placeTaskOnTimeline(
        task.id,
        schedule: next,
        projectId: projectId,
      )).getOrThrow();
    }
  }

  Future<TaskItem?> _current(String id) async {
    try {
      return await _tasks.watchTask(id).first;
    } catch (_) {
      return null;
    }
  }

  Future<TaskItem?> complete(String id) async {
    (await _tasks.completeTask(id)).getOrThrow();
    return _current(id);
  }

  Future<TaskItem?> reopen(String id) async {
    (await _tasks.uncompleteTask(id)).getOrThrow();
    return _current(id);
  }
}

TaskSchedule preserveTimelineRecurrence(TaskItem task, TaskSchedule schedule) {
  final recurrence = task.schedule?.recurrence;
  return recurrence != null
      ? schedule.withRecurrence(recurrence)
      : schedule.withRecurrenceSeriesId(task.schedule?.recurrenceSeriesKey);
}

/// Business projection for a displayed day; retained rows affect rendering only.
final timelineDayPresentationProvider = Provider.autoDispose
    .family<TimelineDayPresentation, ({DateTime day, List<TaskItem> retained})>(
      (ref, input) {
        final state = ref.watch(timelineViewModelProvider);
        final tasks = <String, TaskItem>{
          for (final task in input.retained) task.id: task,
          for (final task in state.tasks.value ?? const <TaskItem>[])
            task.id: task,
        };
        final projects = state.projects.value ?? const <ProjectItem>[];
        final data = buildTimelineDayData(
          tasks.values.toList(),
          day: input.day,
          visibleHours: state.visibleHours,
        );
        final byId = <String, TaskItem>{
          for (final task in [
            ...data.allDay,
            ...data.visibleTimed,
            ...data.beforeHours,
            ...data.afterHours,
          ])
            task.id: task,
        };
        return TimelineDayPresentation(
          data: data,
          tasksById: Map.unmodifiable(byId),
          projectsById: Map.unmodifiable({
            for (final project in projects) project.id: project,
          }),
          projectRows: List.unmodifiable(
            buildTimelineProjectRows(
              projects: projects,
              tasks: byId.values,
              collapsedProjectIds: state.collapsed,
              temporarilyVisibleProjectIds: state.temporary,
            ),
          ),
          menuProjects: List.unmodifiable(
            activeTimelineProjectMenuItems(projects),
          ),
        );
      },
    );

class TimelineDayPresentation {
  const TimelineDayPresentation({
    required this.data,
    required this.tasksById,
    required this.projectsById,
    required this.projectRows,
    required this.menuProjects,
  });
  final TimelineDayData data;
  final Map<String, TaskItem> tasksById;
  final Map<String, ProjectItem> projectsById;
  final List<TimelineProjectRow> projectRows;
  final List<ProjectItem> menuProjects;
}
