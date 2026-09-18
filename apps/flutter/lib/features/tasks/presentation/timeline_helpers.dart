part of 'timeline_screen.dart';

const _defaultTimedTaskDuration = Duration(minutes: 30);

const _minTimedTaskDuration = Duration(minutes: timelineSnapMinutes);

const _minutesPerDay = 24 * 60;

const _timeRulerHeight = 32.0;

const _laneHeight = 64.0;

const _inlineAddWidth = 280.0;

const _blockGap = 4.0;

List<_TimedTaskLayout> _layoutTimedTasks(List<TaskItem> tasks) {
  final sorted = [...tasks]..sort(_compareTimedTaskOrder);
  final layouts = <_TimedTaskLayout>[];
  var index = 0;
  while (index < sorted.length) {
    final cluster = <TaskItem>[];
    var clusterEnd = _endMinutes(sorted[index].schedule!);
    do {
      final task = sorted[index];
      cluster.add(task);
      clusterEnd = math.max(clusterEnd, _endMinutes(task.schedule!));
      index++;
    } while (index < sorted.length &&
        _startMinutes(sorted[index].schedule!) < clusterEnd);

    final laneEnds = <int>[];
    final assigned = <TaskItem, int>{};
    for (final task in cluster) {
      final start = _startMinutes(task.schedule!);
      var lane = laneEnds.indexWhere((end) => end <= start);
      if (lane == -1) {
        lane = laneEnds.length;
        laneEnds.add(0);
      }
      laneEnds[lane] = _endMinutes(task.schedule!);
      assigned[task] = lane;
    }
    final laneCount = math.max(1, laneEnds.length);
    for (final task in cluster) {
      layouts.add(
        _TimedTaskLayout(
          task: task,
          lane: assigned[task]!,
          laneCount: laneCount,
        ),
      );
    }
  }
  return layouts;
}

Future<void> _updateSchedule(
  BuildContext context,
  WidgetRef ref,
  TaskItem task,
  TaskSchedule schedule,
) async {
  try {
    final nextSchedule = _preserveRecurrence(task, schedule);
    await ref
        .read(taskRepositoryProvider)
        .updateTask(task.id, UpdateTaskPatch(schedule: nextSchedule));
    if (context.mounted) {
      TaskMotionScope.maybeOf(context)?.landed({task.id});
      await playHaptic(AppHapticCue.light);
    }
  } catch (_) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.taskActionFailedCount(1))),
    );
  }
}

TaskSchedule _preserveRecurrence(TaskItem task, TaskSchedule schedule) {
  final recurrence = task.schedule?.recurrence;
  if (recurrence != null) {
    return schedule.withRecurrence(recurrence);
  }
  return schedule.withRecurrenceSeriesId(task.schedule?.recurrenceSeriesKey);
}

TaskSchedule _timedScheduleFor(
  DateTime day,
  int startMinutes,
  Duration duration,
) {
  final start = _dateOnly(day).add(Duration(minutes: startMinutes));
  return TaskSchedule.timed(start: start, end: start.add(duration));
}

Color _priorityColor(int priority, AppThemePalette colors) {
  return switch (priority) {
    1 => colors.overdue,
    2 => colors.warning,
    3 => colors.info,
    _ => colors.border,
  };
}

int _compareTimelineTaskOrder(TaskItem a, TaskItem b) {
  final dayOrderCompare = (a.dayOrder ?? 999999).compareTo(
    b.dayOrder ?? 999999,
  );
  if (dayOrderCompare != 0) {
    return dayOrderCompare;
  }
  return a.orderKey.compareTo(b.orderKey);
}

int _compareTimedTaskOrder(TaskItem a, TaskItem b) {
  final scheduleCompare = _startMinutes(
    a.schedule!,
  ).compareTo(_startMinutes(b.schedule!));
  if (scheduleCompare != 0) {
    return scheduleCompare;
  }
  return _compareTimelineTaskOrder(a, b);
}

int _startMinutes(TaskSchedule schedule) {
  final start = schedule.start!.toLocal();
  return start.hour * 60 + start.minute;
}

int _endMinutes(TaskSchedule schedule) {
  final end = schedule.end!.toLocal();
  if (!_isSameDay(schedule.start!.toLocal(), end)) {
    return _minutesPerDay;
  }
  return end.hour * 60 + end.minute;
}

int _snapMinutes(int minutes) {
  return (minutes / timelineSnapMinutes).round() * timelineSnapMinutes;
}

int _floorSnapMinutes(int minutes) {
  return (minutes ~/ timelineSnapMinutes) * timelineSnapMinutes;
}

String _formatMinutes(int minutes) {
  final clamped = minutes.clamp(0, _minutesPerDay);
  final hour = clamped ~/ 60;
  final minute = clamped % 60;
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

String _formatRouteDate(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool _usesImmediateTaskDrag(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => false,
  };
}

final _timeOptions = [
  for (
    var minutes = 0;
    minutes <= _minutesPerDay;
    minutes += timelineSnapMinutes
  )
    minutes,
];
