import 'package:pomodoist/domain/models/tasks/task_models.dart';

class ProductivitySummary {
  ProductivitySummary({
    required this.completedTasks,
    required this.completedFocusIntervals,
    required this.totalFocusSeconds,
    required this.plannedFocusIntervals,
    required this.openTasks,
    required this.allTimeCompletedTasks,
    required this.allTimeCompletedFocusIntervals,
    List<ProductivityDaySummary> lastSevenDays = const [],
    List<ProjectFocusSummary> todayProjects = const [],
    List<ProjectFocusSummary> lastSevenDaysProjects = const [],
  }) : lastSevenDays = List.unmodifiable(lastSevenDays),
       todayProjects = List.unmodifiable(todayProjects),
       lastSevenDaysProjects = List.unmodifiable(lastSevenDaysProjects);

  final int completedTasks;
  final int completedFocusIntervals;
  final int totalFocusSeconds;
  final int plannedFocusIntervals;
  final int openTasks;
  final int allTimeCompletedTasks;
  final int allTimeCompletedFocusIntervals;
  final List<ProductivityDaySummary> lastSevenDays;
  final List<ProjectFocusSummary> todayProjects;
  final List<ProjectFocusSummary> lastSevenDaysProjects;
}

class ProjectFocusSummary {
  ProjectFocusSummary({
    required this.projectId,
    required this.project,
    required this.totalFocusSeconds,
    required this.completedFocusIntervals,
    required List<TaskFocusSummary> tasks,
  }) : tasks = List.unmodifiable(tasks);

  final String? projectId;
  final ProjectItem? project;
  final int totalFocusSeconds;
  final int completedFocusIntervals;
  final List<TaskFocusSummary> tasks;

  String? get name => project?.name;
  String? get color => project?.color;
  bool get isUnavailable =>
      projectId != null && (project == null || project!.isDeleted);
}

class TaskFocusSummary {
  const TaskFocusSummary({
    required this.taskId,
    required this.name,
    required this.canOpen,
    required this.totalFocusSeconds,
    required this.completedFocusIntervals,
  });

  final String? taskId;
  final String? name;
  final bool canOpen;
  final int totalFocusSeconds;
  final int completedFocusIntervals;
}

class ProductivityDaySummary {
  const ProductivityDaySummary({
    required this.localDate,
    required this.completedTasks,
    required this.completedFocusIntervals,
    required this.totalFocusSeconds,
  });

  final DateTime localDate;
  final int completedTasks;
  final int completedFocusIntervals;
  final int totalFocusSeconds;
}
