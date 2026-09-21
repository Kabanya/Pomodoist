import 'package:pomodoist/domain/models/tasks/task_models.dart';

/// The fixed instant that fixture creation timestamps default to.
final DateTime fixtureCreatedAt = DateTime.utc(2026, 1, 1, 12);

/// The fixed instant that fixture update timestamps default to, five minutes
/// after [fixtureCreatedAt] so the two stay distinguishable.
final DateTime fixtureUpdatedAt = DateTime.utc(2026, 1, 1, 12, 5);

/// The fixed calendar day that all-day schedules default to.
final DateTime fixtureDate = DateTime.utc(2026, 1, 2);

/// The order key for position [index]: `a`, `b`, … `z`, `aa`, `ab`, ….
String fixtureOrderKey(int index) {
  var value = index + 1;
  final letters = <String>[];
  while (value > 0) {
    final remainder = (value - 1) % 26;
    letters.add(String.fromCharCode('a'.codeUnitAt(0) + remainder));
    value = (value - 1) ~/ 26;
  }
  return letters.reversed.join();
}

/// A recurrence of every day, starting from [seriesId].
TaskRecurrence buildRecurrence({
  int interval = 1,
  TaskRecurrenceUnit unit = TaskRecurrenceUnit.day,
  String seriesId = 'series-1',
}) {
  return TaskRecurrence(interval: interval, unit: unit, seriesId: seriesId);
}

/// An all-day schedule on [date], unless [start] or [end] is given, which
/// yields a timed one starting at [start] or [fixtureCreatedAt] and lasting an
/// hour when only one bound is given.
TaskSchedule buildSchedule({
  DateTime? date,
  DateTime? start,
  DateTime? end,
  String? timeZone,
  TaskRecurrence? recurrence,
  String? recurrenceSeriesId,
}) {
  if (start == null && end == null) {
    return TaskSchedule.allDay(
      date ?? fixtureDate,
      recurrence: recurrence,
      recurrenceSeriesId: recurrenceSeriesId,
    );
  }
  final resolvedStart = start ?? fixtureCreatedAt;
  return TaskSchedule.timed(
    start: resolvedStart,
    end: end ?? resolvedStart.add(const Duration(hours: 1)),
    timeZone: timeZone,
    recurrence: recurrence,
    recurrenceSeriesId: recurrenceSeriesId,
  );
}

/// A task with every field defaulted, so a test overrides only what it asserts.
///
/// A `schedule` is encoded into the due JSON; an explicit `dueJson` wins.
TaskItem buildTask({
  String id = 'task-1',
  String userId = 'user-1',
  String content = 'Task 1',
  String projectId = 'project-1',
  int priority = 4,
  String status = 'active',
  String orderKey = 'a',
  DateTime? createdAt,
  DateTime? updatedAt,
  String? description,
  String? sectionId,
  String? parentId,
  String? dueJson,
  String? deadlineJson,
  int? durationSeconds,
  int? estimatedFocusIntervals,
  int completedFocusIntervals = 0,
  int totalFocusSeconds = 0,
  int? dayOrder,
  bool isCollapsed = false,
  bool isDeleted = false,
  DateTime? completedAt,
  String? scopeId,
  String? createdBy,
  String? completedBy,
  List<String> assigneeIds = const [],
  bool canEdit = true,
  TaskSchedule? schedule,
}) {
  return TaskItem(
    id: id,
    userId: userId,
    content: content,
    projectId: projectId,
    priority: priority,
    status: status,
    orderKey: orderKey,
    createdAt: createdAt ?? fixtureCreatedAt,
    updatedAt: updatedAt ?? fixtureUpdatedAt,
    description: description,
    sectionId: sectionId,
    parentId: parentId,
    dueJson: dueJson ?? schedule?.toJsonString(),
    deadlineJson: deadlineJson,
    durationSeconds: durationSeconds,
    estimatedFocusIntervals: estimatedFocusIntervals,
    completedFocusIntervals: completedFocusIntervals,
    totalFocusSeconds: totalFocusSeconds,
    dayOrder: dayOrder,
    isCollapsed: isCollapsed,
    isDeleted: isDeleted,
    completedAt: completedAt,
    scopeId: scopeId,
    createdBy: createdBy,
    completedBy: completedBy,
    assigneeIds: assigneeIds,
    canEdit: canEdit,
  );
}

/// [count] tasks in ascending order, with ids `task-1`, `task-2`, … and order
/// keys `a`, `b`, … so tests can assert ordering.
List<TaskItem> buildTasks(
  int count, {
  String projectId = 'project-1',
  String userId = 'user-1',
  String status = 'active',
  int priority = 4,
  String? sectionId,
  String? parentId,
  bool isDeleted = false,
  TaskSchedule? schedule,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  return [
    for (var index = 0; index < count; index++)
      buildTask(
        id: 'task-${index + 1}',
        content: 'Task ${index + 1}',
        orderKey: fixtureOrderKey(index),
        projectId: projectId,
        userId: userId,
        status: status,
        priority: priority,
        sectionId: sectionId,
        parentId: parentId,
        isDeleted: isDeleted,
        schedule: schedule,
        createdAt: createdAt,
        updatedAt: updatedAt,
      ),
  ];
}

/// A project with every field defaulted.
ProjectItem buildProject({
  String id = 'project-1',
  String userId = 'user-1',
  String name = 'Project 1',
  String orderKey = 'a',
  DateTime? createdAt,
  DateTime? updatedAt,
  String? color,
  String? icon,
  String? parentId,
  String viewStyle = 'list',
  bool isFavorite = false,
  bool isArchived = false,
  bool isDeleted = false,
  String? scopeId,
  bool canEdit = true,
  bool canManage = true,
  bool isOwner = true,
}) {
  return ProjectItem(
    id: id,
    userId: userId,
    name: name,
    orderKey: orderKey,
    createdAt: createdAt ?? fixtureCreatedAt,
    updatedAt: updatedAt ?? fixtureUpdatedAt,
    color: color,
    icon: icon,
    parentId: parentId,
    viewStyle: viewStyle,
    isFavorite: isFavorite,
    isArchived: isArchived,
    isDeleted: isDeleted,
    scopeId: scopeId,
    canEdit: canEdit,
    canManage: canManage,
    isOwner: isOwner,
  );
}

/// [count] projects in ascending order, with ids `project-1`, `project-2`, …
/// and order keys `a`, `b`, ….
List<ProjectItem> buildProjects(
  int count, {
  String userId = 'user-1',
  String? parentId,
  String viewStyle = 'list',
  bool isFavorite = false,
  bool isArchived = false,
  bool isDeleted = false,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  return [
    for (var index = 0; index < count; index++)
      buildProject(
        id: 'project-${index + 1}',
        name: 'Project ${index + 1}',
        orderKey: fixtureOrderKey(index),
        userId: userId,
        parentId: parentId,
        viewStyle: viewStyle,
        isFavorite: isFavorite,
        isArchived: isArchived,
        isDeleted: isDeleted,
        createdAt: createdAt,
        updatedAt: updatedAt,
      ),
  ];
}

/// A label with every field defaulted.
LabelItem buildLabel({
  String id = 'label-1',
  String userId = 'user-1',
  String name = 'Label 1',
  String orderKey = 'a',
  DateTime? createdAt,
  DateTime? updatedAt,
  String? color,
  String? icon,
  bool isFavorite = false,
  bool isDeleted = false,
}) {
  return LabelItem(
    id: id,
    userId: userId,
    name: name,
    orderKey: orderKey,
    createdAt: createdAt ?? fixtureCreatedAt,
    updatedAt: updatedAt ?? fixtureUpdatedAt,
    color: color,
    icon: icon,
    isFavorite: isFavorite,
    isDeleted: isDeleted,
  );
}

/// [count] labels in ascending order, with ids `label-1`, `label-2`, … and
/// order keys `a`, `b`, ….
List<LabelItem> buildLabels(
  int count, {
  String userId = 'user-1',
  bool isFavorite = false,
  bool isDeleted = false,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  return [
    for (var index = 0; index < count; index++)
      buildLabel(
        id: 'label-${index + 1}',
        name: 'Label ${index + 1}',
        orderKey: fixtureOrderKey(index),
        userId: userId,
        isFavorite: isFavorite,
        isDeleted: isDeleted,
        createdAt: createdAt,
        updatedAt: updatedAt,
      ),
  ];
}

/// A kanban status with every field defaulted; [systemKey] stays null, so the
/// column is editable rather than one of the protected backlog or done ones.
KanbanStatus buildKanbanStatus({
  String id = 'status-1',
  String userId = 'user-1',
  String name = 'Status 1',
  String orderKey = 'a',
  DateTime? createdAt,
  DateTime? updatedAt,
  String? color,
  KanbanSystemKey? systemKey,
}) {
  return KanbanStatus(
    id: id,
    userId: userId,
    name: name,
    orderKey: orderKey,
    createdAt: createdAt ?? fixtureCreatedAt,
    updatedAt: updatedAt ?? fixtureUpdatedAt,
    color: color,
    systemKey: systemKey,
  );
}

/// Kanban settings with no selected projects, focused on the default status.
KanbanSettings buildKanbanSettings({
  String id = 'kanban-settings-1',
  String userId = 'user-1',
  Iterable<String> selectedProjectIds = const [],
  String focusStatusLabelId = 'status-1',
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  return KanbanSettings(
    id: id,
    userId: userId,
    selectedProjectIds: selectedProjectIds,
    focusStatusLabelId: focusStatusLabelId,
    createdAt: createdAt ?? fixtureCreatedAt,
    updatedAt: updatedAt ?? fixtureUpdatedAt,
  );
}

/// A card holding a default task in a project matching that task's project.
KanbanCard buildKanbanCard({
  TaskItem? task,
  ProjectItem? project,
  String statusId = 'status-1',
  int totalSubtasks = 0,
  int completedSubtasks = 0,
}) {
  final resolvedTask = task ?? buildTask();
  return KanbanCard(
    task: resolvedTask,
    project: project ?? buildProject(id: resolvedTask.projectId),
    statusId: statusId,
    totalSubtasks: totalSubtasks,
    completedSubtasks: completedSubtasks,
  );
}

/// A board with one default status, no cards, and the focus on its first
/// column when [focusedStatusId] is omitted.
KanbanBoardSnapshot buildKanbanBoard({
  List<KanbanStatus>? statuses,
  Map<String, List<KanbanCard>>? cardsByStatusId,
  KanbanSettings? settings,
  String? focusedStatusId,
  List<ProjectItem>? availableProjects,
}) {
  final resolvedStatuses = statuses ?? [buildKanbanStatus()];
  final resolvedSettings = settings ?? buildKanbanSettings();
  return KanbanBoardSnapshot(
    statuses: resolvedStatuses,
    settings: resolvedSettings,
    focusedStatusId:
        focusedStatusId ??
        (resolvedStatuses.isEmpty
            ? resolvedSettings.focusStatusLabelId
            : resolvedStatuses.first.id),
    availableProjects: availableProjects ?? [buildProject()],
    cardsByStatusId: cardsByStatusId ?? const {},
  );
}

/// A new-task input carrying only [content] and a target project.
CreateTaskInput buildCreateTaskInput({
  String content = 'Task 1',
  String? description,
  String? projectId = 'project-1',
  String? labelId,
  String? sectionId,
  String? parentId,
  int? priority,
  List<String> labelNames = const [],
  DateTime? dueDate,
  TaskSchedule? schedule,
  DateTime? deadline,
  int? durationSeconds,
  int? estimatedFocusIntervals,
  String? kanbanStatusId,
}) {
  return CreateTaskInput(
    content: content,
    description: description,
    projectId: projectId,
    labelId: labelId,
    sectionId: sectionId,
    parentId: parentId,
    priority: priority,
    labelNames: labelNames,
    dueDate: dueDate,
    schedule: schedule,
    deadline: deadline,
    durationSeconds: durationSeconds,
    estimatedFocusIntervals: estimatedFocusIntervals,
    kanbanStatusId: kanbanStatusId,
  );
}

/// A task patch with nothing set, so only the overridden fields are updated.
UpdateTaskPatch buildUpdateTaskPatch({
  String? content,
  String? description,
  bool updateDescription = false,
  int? priority,
  DateTime? dueDate,
  TaskSchedule? schedule,
  bool clearSchedule = false,
  int? estimatedFocusIntervals,
  bool? isCollapsed,
  List<String>? labelNames,
}) {
  return UpdateTaskPatch(
    content: content,
    description: description,
    updateDescription: updateDescription,
    priority: priority,
    dueDate: dueDate,
    schedule: schedule,
    clearSchedule: clearSchedule,
    estimatedFocusIntervals: estimatedFocusIntervals,
    isCollapsed: isCollapsed,
    labelNames: labelNames,
  );
}

/// A project patch with nothing set, so only the overridden fields are updated.
UpdateProjectPatch buildUpdateProjectPatch({
  String? name,
  String? color,
  String? icon,
  bool? isFavorite,
}) {
  return UpdateProjectPatch(
    name: name,
    color: color,
    icon: icon,
    isFavorite: isFavorite,
  );
}

/// A task query; [TaskQueryKind.all] unless [kind] says otherwise.
TaskQuery buildTaskQuery({
  TaskQueryKind kind = TaskQueryKind.all,
  String? projectId,
  String? labelId,
  String? search,
  String? creatorId,
  String? assigneeId,
  DateTime? now,
  DateTime? date,
}) {
  return TaskQuery(
    kind: kind,
    projectId: projectId,
    labelId: labelId,
    search: search,
    creatorId: creatorId,
    assigneeId: assigneeId,
    now: now,
    date: date,
  );
}

/// A calendar-sourced task on a default all-day schedule.
RemoteCalendarTaskInput buildRemoteCalendarTaskInput({
  String content = 'Task 1',
  TaskSchedule? schedule,
  DateTime? updatedAt,
  String? description,
  bool isCompleted = false,
}) {
  return RemoteCalendarTaskInput(
    content: content,
    schedule: schedule ?? buildSchedule(),
    updatedAt: updatedAt ?? fixtureUpdatedAt,
    description: description,
    isCompleted: isCompleted,
  );
}

/// A calendar patch with nothing set but the revision timestamp.
RemoteCalendarTaskPatch buildRemoteCalendarTaskPatch({
  DateTime? updatedAt,
  String? content,
  String? description,
  bool updateDescription = false,
  TaskSchedule? schedule,
  bool? isCompleted,
  bool? isDeleted,
}) {
  return RemoteCalendarTaskPatch(
    updatedAt: updatedAt ?? fixtureUpdatedAt,
    content: content,
    description: description,
    updateDescription: updateDescription,
    schedule: schedule,
    isCompleted: isCompleted,
    isDeleted: isDeleted,
  );
}

/// A deletion batch holding the default task id and expiring at
/// [fixtureUpdatedAt].
DeletedTaskBatch buildDeletedTaskBatch({
  Set<String> taskIds = const {'task-1'},
  DateTime? undoUntil,
}) {
  return DeletedTaskBatch(
    taskIds: taskIds,
    undoUntil: undoUntil ?? fixtureUpdatedAt,
  );
}
