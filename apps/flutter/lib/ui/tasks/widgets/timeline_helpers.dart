part of 'timeline_screen.dart';

const _defaultTimedTaskDuration = Duration(minutes: 30);

const _timeRulerHeight = 32.0;

const _laneHeight = 64.0;

const _inlineAddWidth = 280.0;

const _blockGap = 4.0;

List<_TimedTaskLayout> _layoutTimedTasks(List<TaskItem> tasks) {
  final sorted = [...tasks]..sort(compareTimedTaskOrder);
  final layouts = <_TimedTaskLayout>[];
  var index = 0;
  while (index < sorted.length) {
    final cluster = <TaskItem>[];
    var clusterEnd = timelineEndMinutes(sorted[index].schedule!);
    do {
      final task = sorted[index];
      cluster.add(task);
      clusterEnd = math.max(clusterEnd, timelineEndMinutes(task.schedule!));
      index++;
    } while (index < sorted.length &&
        timelineStartMinutes(sorted[index].schedule!) < clusterEnd);

    final laneEnds = <int>[];
    final assigned = <TaskItem, int>{};
    for (final task in cluster) {
      final start = timelineStartMinutes(task.schedule!);
      var lane = laneEnds.indexWhere((end) => end <= start);
      if (lane == -1) {
        lane = laneEnds.length;
        laneEnds.add(0);
      }
      laneEnds[lane] = timelineEndMinutes(task.schedule!);
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
    await ref.read(timelineViewModelProvider.notifier).schedule(task, schedule);
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

TaskSchedule _timedScheduleFor(
  DateTime day,
  int startMinutes,
  Duration duration,
) {
  final start = timelineDateOnly(day).add(Duration(minutes: startMinutes));
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

int _snapMinutes(int minutes) {
  return (minutes / timelineSnapMinutes).round() * timelineSnapMinutes;
}

int _floorSnapMinutes(int minutes) {
  return (minutes ~/ timelineSnapMinutes) * timelineSnapMinutes;
}

String _formatMinutes(int minutes) {
  final clamped = minutes.clamp(0, timelineMinutesPerDay);
  final hour = clamped ~/ 60;
  final minute = clamped % 60;
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

String _formatRouteDate(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

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
    minutes <= timelineMinutesPerDay;
    minutes += timelineSnapMinutes
  )
    minutes,
];
