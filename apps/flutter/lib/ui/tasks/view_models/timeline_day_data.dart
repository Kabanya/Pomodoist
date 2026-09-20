import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

const timelineMinutesPerDay = 24 * 60;

class TimelineDayData {
  const TimelineDayData({
    required this.allDay,
    required this.visibleTimed,
    required this.beforeHours,
    required this.afterHours,
    required this.timedByProject,
  });

  final List<TaskItem> allDay;
  final List<TaskItem> visibleTimed;
  final List<TaskItem> beforeHours;
  final List<TaskItem> afterHours;
  final Map<String, List<TaskItem>> timedByProject;
}

TimelineDayData buildTimelineDayData(
  Iterable<TaskItem> tasks, {
  required DateTime day,
  required TimelineVisibleHours visibleHours,
}) {
  final allDay = <TaskItem>[];
  final visibleTimed = <TaskItem>[];
  final beforeHours = <TaskItem>[];
  final afterHours = <TaskItem>[];

  for (final task in tasks) {
    final schedule = task.schedule;
    if (task.isCompleted ||
        schedule == null ||
        !isSameLocalDay(schedule.displayDate, day)) {
      continue;
    }
    if (schedule.isAllDay) {
      allDay.add(task);
      continue;
    }
    final startMinutes = timelineStartMinutes(schedule);
    if (startMinutes < visibleHours.startMinutes) {
      beforeHours.add(task);
    } else if (startMinutes >= visibleHours.endMinutes) {
      afterHours.add(task);
    } else {
      visibleTimed.add(task);
    }
  }

  allDay.sort(compareTimelineTaskOrder);
  visibleTimed.sort(compareTimedTaskOrder);
  beforeHours.sort(compareTimedTaskOrder);
  afterHours.sort(compareTimedTaskOrder);

  final timedByProject = <String, List<TaskItem>>{};
  for (final task in visibleTimed) {
    timedByProject.putIfAbsent(task.projectId, () => []).add(task);
  }

  return TimelineDayData(
    allDay: List.unmodifiable(allDay),
    visibleTimed: List.unmodifiable(visibleTimed),
    beforeHours: List.unmodifiable(beforeHours),
    afterHours: List.unmodifiable(afterHours),
    timedByProject: Map.unmodifiable({
      for (final entry in timedByProject.entries)
        entry.key: List<TaskItem>.unmodifiable(entry.value),
    }),
  );
}

int compareTimelineTaskOrder(TaskItem a, TaskItem b) {
  final dayOrderCompare = (a.dayOrder ?? 999999).compareTo(
    b.dayOrder ?? 999999,
  );
  if (dayOrderCompare != 0) {
    return dayOrderCompare;
  }
  return a.orderKey.compareTo(b.orderKey);
}

int compareTimedTaskOrder(TaskItem a, TaskItem b) {
  final scheduleCompare = timelineStartMinutes(
    a.schedule!,
  ).compareTo(timelineStartMinutes(b.schedule!));
  if (scheduleCompare != 0) {
    return scheduleCompare;
  }
  return compareTimelineTaskOrder(a, b);
}

int timelineStartMinutes(TaskSchedule schedule) {
  final start = schedule.start!.toLocal();
  return start.hour * 60 + start.minute;
}

int timelineEndMinutes(TaskSchedule schedule) {
  final end = schedule.end!.toLocal();
  if (!isSameLocalDay(schedule.start!.toLocal(), end)) {
    return timelineMinutesPerDay;
  }
  return end.hour * 60 + end.minute;
}

DateTime timelineDateOnly(DateTime date) =>
    DateTime(date.year, date.month, date.day);

bool isSameLocalDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
