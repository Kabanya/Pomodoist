import 'dart:convert';

class TaskSchedule {
  const TaskSchedule._({
    required this.kind,
    this.date,
    this.start,
    this.end,
    this.timeZone,
    this.recurrence,
    this.recurrenceSeriesId,
  });

  factory TaskSchedule.allDay(
    DateTime date, {
    TaskRecurrence? recurrence,
    String? recurrenceSeriesId,
  }) {
    return TaskSchedule._(
      kind: TaskScheduleKind.allDay,
      date: _dateOnly(date),
      recurrence: recurrence,
      recurrenceSeriesId: recurrence == null
          ? _cleanSeriesId(recurrenceSeriesId)
          : null,
    );
  }

  factory TaskSchedule.timed({
    required DateTime start,
    required DateTime end,
    String? timeZone,
    TaskRecurrence? recurrence,
    String? recurrenceSeriesId,
  }) {
    if (!end.isAfter(start)) {
      throw ArgumentError.value(end, 'end', 'End must be after start');
    }
    return TaskSchedule._(
      kind: TaskScheduleKind.timed,
      start: start.toUtc(),
      end: end.toUtc(),
      timeZone: timeZone,
      recurrence: recurrence,
      recurrenceSeriesId: recurrence == null
          ? _cleanSeriesId(recurrenceSeriesId)
          : null,
    );
  }

  final TaskScheduleKind kind;
  final DateTime? date;
  final DateTime? start;
  final DateTime? end;
  final String? timeZone;
  final TaskRecurrence? recurrence;
  final String? recurrenceSeriesId;

  bool get isAllDay => kind == TaskScheduleKind.allDay;
  bool get isTimed => kind == TaskScheduleKind.timed;
  bool get isRecurringOccurrence =>
      recurrence != null || recurrenceSeriesId != null;
  String? get recurrenceSeriesKey => recurrence?.seriesId ?? recurrenceSeriesId;

  DateTime get displayDate {
    return switch (kind) {
      TaskScheduleKind.allDay => date!,
      TaskScheduleKind.timed => _dateOnly(start!.toLocal()),
    };
  }

  Duration? get duration {
    if (!isTimed) {
      return null;
    }
    return end!.difference(start!);
  }

  DateTime get occurrenceStartLocal {
    return switch (kind) {
      TaskScheduleKind.allDay => date!,
      TaskScheduleKind.timed => start!.toLocal(),
    };
  }

  TaskSchedule withRecurrence(TaskRecurrence? value) {
    return switch (kind) {
      TaskScheduleKind.allDay => TaskSchedule.allDay(date!, recurrence: value),
      TaskScheduleKind.timed => TaskSchedule.timed(
        start: start!,
        end: end!,
        timeZone: timeZone,
        recurrence: value,
      ),
    };
  }

  TaskSchedule withRecurrenceSeriesId(String? value) {
    return switch (kind) {
      TaskScheduleKind.allDay => TaskSchedule.allDay(
        date!,
        recurrenceSeriesId: value,
      ),
      TaskScheduleKind.timed => TaskSchedule.timed(
        start: start!,
        end: end!,
        timeZone: timeZone,
        recurrenceSeriesId: value,
      ),
    };
  }

  TaskSchedule withoutRecurrence({bool keepSeriesId = false}) {
    return withRecurrenceSeriesId(keepSeriesId ? recurrenceSeriesKey : null);
  }

  TaskSchedule nextOccurrence() {
    final repeat = recurrence;
    if (repeat == null) {
      return this;
    }
    return switch (kind) {
      TaskScheduleKind.allDay => TaskSchedule.allDay(
        _addRecurrence(date!, repeat),
        recurrence: repeat,
      ),
      TaskScheduleKind.timed => () {
        final localStart = start!.toLocal();
        final nextStart = _addRecurrence(localStart, repeat);
        return TaskSchedule.timed(
          start: nextStart,
          end: nextStart.add(duration!),
          timeZone: timeZone,
          recurrence: repeat,
        );
      }(),
    };
  }

  TaskSchedule nextOccurrenceAfter(DateTime now, {bool advanceFirst = false}) {
    var next = advanceFirst ? nextOccurrence() : this;
    while (!next.occurrenceStartLocal.isAfter(now.toLocal())) {
      next = next.nextOccurrence();
    }
    return next;
  }

  String toJsonString() {
    final json = switch (kind) {
      TaskScheduleKind.allDay => {
        'type': 'allDay',
        'date': _formatDate(date!),
        if (recurrence != null) 'recurrence': recurrence!.toJson(),
        if (recurrence == null && recurrenceSeriesId != null)
          'recurrenceSeriesId': recurrenceSeriesId,
      },
      TaskScheduleKind.timed => {
        'type': 'timed',
        'start': start!.toUtc().toIso8601String(),
        'end': end!.toUtc().toIso8601String(),
        if (timeZone != null && timeZone!.trim().isNotEmpty)
          'timeZone': timeZone,
        if (recurrence != null) 'recurrence': recurrence!.toJson(),
        if (recurrence == null && recurrenceSeriesId != null)
          'recurrenceSeriesId': recurrenceSeriesId,
      },
    };
    return jsonEncode(json);
  }

  static TaskSchedule? fromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final type = decoded['type'];
    if (type == 'timed') {
      final start = _parseDateTime(decoded['start']);
      final end = _parseDateTime(decoded['end']);
      final recurrence = TaskRecurrence.fromJson(decoded['recurrence']);
      final recurrenceSeriesId = _cleanSeriesId(decoded['recurrenceSeriesId']);
      if (start == null || end == null || !end.isAfter(start)) {
        return null;
      }
      final timeZone = decoded['timeZone'];
      return TaskSchedule.timed(
        start: start,
        end: end,
        timeZone: timeZone is String ? timeZone : null,
        recurrence: recurrence,
        recurrenceSeriesId: recurrenceSeriesId,
      );
    }

    final date = _parseDateOnly(decoded['date']);
    final recurrence = TaskRecurrence.fromJson(decoded['recurrence']);
    final recurrenceSeriesId = _cleanSeriesId(decoded['recurrenceSeriesId']);
    if (date == null) {
      return null;
    }
    return TaskSchedule.allDay(
      date,
      recurrence: recurrence,
      recurrenceSeriesId: recurrenceSeriesId,
    );
  }

  static DateTime? _parseDateTime(Object? value) {
    if (value is! String) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  static DateTime? _parseDateOnly(Object? value) {
    if (value is! String) {
      return null;
    }
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      final parts = value.split('-').map(int.parse).toList();
      return DateTime(parts[0], parts[1], parts[2]);
    }
    final parsed = DateTime.tryParse(value);
    return parsed == null ? null : _dateOnly(parsed);
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static String? _cleanSeriesId(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String _formatDate(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  static DateTime _addRecurrence(DateTime value, TaskRecurrence recurrence) {
    return switch (recurrence.unit) {
      TaskRecurrenceUnit.day => value.add(Duration(days: recurrence.interval)),
      TaskRecurrenceUnit.week => value.add(
        Duration(days: 7 * recurrence.interval),
      ),
      TaskRecurrenceUnit.month => _addMonths(value, recurrence.interval),
    };
  }

  static DateTime _addMonths(DateTime value, int months) {
    final targetMonth = value.month + months;
    final year = value.year + (targetMonth - 1) ~/ 12;
    final month = (targetMonth - 1) % 12 + 1;
    final day = value.day.clamp(1, _lastDayOfMonth(year, month)).toInt();
    return DateTime(
      year,
      month,
      day,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    );
  }

  static int _lastDayOfMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TaskSchedule &&
            other.kind == kind &&
            other.date == date &&
            other.start == start &&
            other.end == end &&
            other.timeZone == timeZone &&
            other.recurrence == recurrence &&
            other.recurrenceSeriesId == recurrenceSeriesId;
  }

  @override
  int get hashCode => Object.hash(
    kind,
    date,
    start,
    end,
    timeZone,
    recurrence,
    recurrenceSeriesId,
  );
}

enum TaskScheduleKind { allDay, timed }

class TaskRecurrence {
  const TaskRecurrence({
    required this.interval,
    required this.unit,
    required this.seriesId,
  }) : assert(interval >= 1 && interval <= 999),
       assert(seriesId.length > 0);

  final int interval;
  final TaskRecurrenceUnit unit;
  final String seriesId;

  Map<String, Object?> toJson() {
    return {'interval': interval, 'unit': unit.name, 'seriesId': seriesId};
  }

  static TaskRecurrence? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final json = Map<String, Object?>.from(raw);
    final interval = json['interval'];
    TaskRecurrenceUnit? unit;
    for (final value in TaskRecurrenceUnit.values) {
      if (value.name == json['unit']) {
        unit = value;
        break;
      }
    }
    final seriesId = json['seriesId'];
    if (interval is! int ||
        interval < 1 ||
        interval > 999 ||
        unit == null ||
        seriesId is! String ||
        seriesId.trim().isEmpty) {
      return null;
    }
    return TaskRecurrence(interval: interval, unit: unit, seriesId: seriesId);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TaskRecurrence &&
            other.interval == interval &&
            other.unit == unit &&
            other.seriesId == seriesId;
  }

  @override
  int get hashCode => Object.hash(interval, unit, seriesId);
}

enum TaskRecurrenceUnit { day, week, month }

class TaskItem {
  const TaskItem({
    required this.id,
    required this.userId,
    required this.content,
    required this.projectId,
    required this.priority,
    required this.status,
    required this.completedFocusIntervals,
    required this.totalFocusSeconds,
    required this.orderKey,
    required this.isDeleted,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.sectionId,
    this.parentId,
    this.dueJson,
    this.deadlineJson,
    this.durationSeconds,
    this.estimatedFocusIntervals,
    this.dayOrder,
    this.isCollapsed = false,
    this.completedAt,
  });

  final String id;
  final String userId;
  final String content;
  final String? description;
  final String projectId;
  final String? sectionId;
  final String? parentId;
  final int priority;
  final String? dueJson;
  final String? deadlineJson;
  final int? durationSeconds;
  final String status;
  final int? estimatedFocusIntervals;
  final int completedFocusIntervals;
  final int totalFocusSeconds;
  final String orderKey;
  final int? dayOrder;
  final bool isCollapsed;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  bool get isCompleted => status == 'completed';

  DateTime? get dueDate {
    return schedule?.displayDate;
  }

  TaskSchedule? get schedule => TaskSchedule.fromJsonString(dueJson);

  int get remainingFocusIntervals {
    final estimate = estimatedFocusIntervals;
    if (estimate == null) {
      return 0;
    }
    final remaining = estimate - completedFocusIntervals;
    return remaining < 0 ? 0 : remaining;
  }
}

class ProjectItem {
  const ProjectItem({
    required this.id,
    required this.userId,
    required this.name,
    required this.orderKey,
    required this.createdAt,
    required this.updatedAt,
    this.color,
    this.parentId,
    this.viewStyle = 'list',
    this.isFavorite = false,
    this.isArchived = false,
    this.isDeleted = false,
  });

  final String id;
  final String userId;
  final String name;
  final String? color;
  final String? parentId;
  final String viewStyle;
  final bool isFavorite;
  final bool isArchived;
  final bool isDeleted;
  final String orderKey;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class LabelItem {
  const LabelItem({
    required this.id,
    required this.userId,
    required this.name,
    required this.orderKey,
    required this.createdAt,
    required this.updatedAt,
    this.color,
    this.isFavorite = false,
    this.isDeleted = false,
  });

  final String id;
  final String userId;
  final String name;
  final String? color;
  final String orderKey;
  final bool isFavorite;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;
}

enum LabelKind { user, kanbanStatus }

enum KanbanSystemKey { backlog, todo, inProgress, done }

class KanbanStatus {
  const KanbanStatus({
    required this.id,
    required this.userId,
    required this.name,
    required this.orderKey,
    required this.createdAt,
    required this.updatedAt,
    this.color,
    this.systemKey,
  });

  final String id;
  final String userId;
  final String name;
  final String? color;
  final String orderKey;
  final KanbanSystemKey? systemKey;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isBacklog => systemKey == KanbanSystemKey.backlog;
  bool get isDone => systemKey == KanbanSystemKey.done;
  bool get isProtected => isBacklog || isDone;
}

class KanbanSettings {
  KanbanSettings({
    required this.id,
    required this.userId,
    required Iterable<String> selectedProjectIds,
    required this.focusStatusLabelId,
    required this.createdAt,
    required this.updatedAt,
  }) : selectedProjectIds = List.unmodifiable(selectedProjectIds);

  final String id;
  final String userId;
  final List<String> selectedProjectIds;
  final String focusStatusLabelId;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class KanbanCard {
  const KanbanCard({
    required this.task,
    required this.project,
    required this.statusId,
    required this.totalSubtasks,
    required this.completedSubtasks,
  });

  final TaskItem task;
  final ProjectItem project;
  final String statusId;
  final int totalSubtasks;
  final int completedSubtasks;
}

class KanbanBoardSnapshot {
  KanbanBoardSnapshot({
    required Iterable<KanbanStatus> statuses,
    required this.settings,
    required Iterable<ProjectItem> availableProjects,
    required Map<String, List<KanbanCard>> cardsByStatusId,
  }) : statuses = List.unmodifiable(statuses),
       availableProjects = List.unmodifiable(availableProjects),
       cardsByStatusId = Map<String, List<KanbanCard>>.unmodifiable({
         for (final entry in cardsByStatusId.entries)
           entry.key: List<KanbanCard>.unmodifiable(entry.value),
       });

  final List<KanbanStatus> statuses;
  final KanbanSettings settings;
  final List<ProjectItem> availableProjects;
  final Map<String, List<KanbanCard>> cardsByStatusId;

  List<KanbanCard> cardsForStatus(String statusId) {
    return cardsByStatusId[statusId] ?? const [];
  }
}

enum TaskQueryKind {
  inbox,
  today,
  upcoming,
  day,
  project,
  search,
  all,
  completed,
}

class TaskQuery {
  const TaskQuery({
    required this.kind,
    this.projectId,
    this.search,
    this.now,
    this.date,
  });

  const TaskQuery.inbox() : this(kind: TaskQueryKind.inbox);
  const TaskQuery.today() : this(kind: TaskQueryKind.today);
  const TaskQuery.upcoming() : this(kind: TaskQueryKind.upcoming);
  const TaskQuery.day(DateTime date)
    : this(kind: TaskQueryKind.day, date: date);
  const TaskQuery.all() : this(kind: TaskQueryKind.all);
  const TaskQuery.completed() : this(kind: TaskQueryKind.completed);

  final TaskQueryKind kind;
  final String? projectId;
  final String? search;
  final DateTime? now;
  final DateTime? date;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TaskQuery &&
            other.kind == kind &&
            other.projectId == projectId &&
            other.search == search &&
            other.now == now &&
            other.date == date;
  }

  @override
  int get hashCode => Object.hash(kind, projectId, search, now, date);
}

class CreateTaskInput {
  const CreateTaskInput({
    required this.content,
    this.description,
    this.projectId,
    this.sectionId,
    this.parentId,
    this.priority,
    this.labelNames = const [],
    this.dueDate,
    this.schedule,
    this.deadline,
    this.durationSeconds,
    this.estimatedFocusIntervals,
    this.kanbanStatusId,
  });

  final String content;
  final String? description;
  final String? projectId;
  final String? sectionId;
  final String? parentId;
  final int? priority;
  final List<String> labelNames;
  final DateTime? dueDate;
  final TaskSchedule? schedule;
  final DateTime? deadline;
  final int? durationSeconds;
  final int? estimatedFocusIntervals;
  final String? kanbanStatusId;
}

class UpdateTaskPatch {
  const UpdateTaskPatch({
    this.content,
    this.description,
    this.updateDescription = false,
    this.priority,
    this.dueDate,
    this.schedule,
    this.clearSchedule = false,
    this.estimatedFocusIntervals,
    this.isCollapsed,
    this.labelNames,
  });

  final String? content;
  final String? description;
  final bool updateDescription;
  final int? priority;
  final DateTime? dueDate;
  final TaskSchedule? schedule;
  final bool clearSchedule;
  final int? estimatedFocusIntervals;
  final bool? isCollapsed;
  final List<String>? labelNames;
}

class UpdateProjectPatch {
  const UpdateProjectPatch({this.name, this.color, this.isFavorite});

  final String? name;
  final String? color;
  final bool? isFavorite;
}

class RemoteCalendarTaskInput {
  const RemoteCalendarTaskInput({
    required this.content,
    required this.schedule,
    required this.updatedAt,
    this.description,
    this.isCompleted = false,
  });

  final String content;
  final String? description;
  final TaskSchedule schedule;
  final bool isCompleted;
  final DateTime updatedAt;
}

class RemoteCalendarTaskPatch {
  const RemoteCalendarTaskPatch({
    required this.updatedAt,
    this.content,
    this.description,
    this.updateDescription = false,
    this.schedule,
    this.isCompleted,
    this.isDeleted,
  });

  final String? content;
  final String? description;
  final bool updateDescription;
  final TaskSchedule? schedule;
  final bool? isCompleted;
  final bool? isDeleted;
  final DateTime updatedAt;
}

class DeletedTaskBatch {
  const DeletedTaskBatch({required this.taskIds, required this.undoUntil});

  final Set<String> taskIds;
  final DateTime undoUntil;
}

abstract interface class TaskRepository {
  Stream<List<TaskItem>> watchTasks(TaskQuery query);
  Stream<TaskItem?> watchTask(String id);
  Future<String> createTask(CreateTaskInput input);
  Future<List<String>> duplicateTasks(
    Set<String> taskIds, {
    required bool includeSubtasks,
  });
  Future<void> updateTask(String id, UpdateTaskPatch patch);
  Future<void> materializeDueRecurringTasks({DateTime? now});
  Future<void> moveTask(
    String id, {
    String? projectId,
    String? sectionId,
    bool clearSectionId = false,
    String? parentId,
    bool clearParentId = false,
    String? orderKey,
  });
  Future<void> placeTaskOnTimeline(
    String id, {
    required TaskSchedule schedule,
    required String projectId,
  });
  Future<void> completeTask(String id);
  Future<void> uncompleteTask(String id);
  Future<DeletedTaskBatch> deleteTask(String id);
  Future<DeletedTaskBatch> deleteTasks(Set<String> ids);
  Future<DeletedTaskBatch> deleteRecurringOccurrence(
    String id, {
    required bool includeFollowing,
  });
  Future<bool> restoreDeletedTasks(DeletedTaskBatch batch);
  Future<void> updateFocusAggregates(String id);
  Future<String> createTaskFromCalendar(RemoteCalendarTaskInput input);
  Future<void> applyRemoteCalendarPatch(
    String id,
    RemoteCalendarTaskPatch patch,
  );
}

abstract interface class ProjectRepository {
  Stream<List<ProjectItem>> watchProjects();
  Future<ProjectItem?> findByName(String name);
  Future<String> createProject(String name, {String? color});
  Future<void> updateProject(String id, UpdateProjectPatch patch);
  Future<void> deleteProject(String id);
}

abstract interface class LabelRepository {
  Stream<List<LabelItem>> watchLabels();
  Future<LabelItem?> findByName(String name);
  Future<String> createLabel(String name);
  Future<void> deleteLabel(String id);
}

abstract interface class KanbanRepository {
  Stream<KanbanBoardSnapshot> watchBoard();
  Future<String> createStatus(String name, {String? color});
  Future<void> renameStatus(String id, String name);
  Future<void> reorderStatus(String id, int targetIndex);
  Future<void> deleteStatus(String id);
  Future<void> setSelectedProjectIds(Set<String> projectIds);
  Future<void> setFocusStatus(String statusId);
  Future<void> moveTask(
    String taskId, {
    required String statusId,
    int? targetIndex,
  });
}
