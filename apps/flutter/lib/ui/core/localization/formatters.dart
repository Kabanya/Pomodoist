import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:pomodoist/ui/core/localization/app_date_formatter.dart';

import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/domain/models/tasks/task_time.dart';

String taskTimeStatusLabel(AppLocalizations l10n, TaskTimeState state) =>
    switch (state) {
      TaskTimeState.future => l10n.taskTimeStatusFuture,
      TaskTimeState.focused => l10n.taskTimeStatusFocused,
      TaskTimeState.current => l10n.taskTimeStatusCurrent,
      TaskTimeState.overdue => l10n.taskTimeStatusOverdue,
      TaskTimeState.completed => l10n.taskTimeStatusCompleted,
    };

String formatDurationCompact(Duration duration) {
  final totalSeconds = duration.inSeconds.clamp(0, 999999);
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

String formatFocusTime(BuildContext context, int seconds) {
  final l10n = context.l10n;
  if (seconds <= 0) {
    return l10n.durationMinutes(0);
  }
  final duration = Duration(seconds: seconds);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) {
    return l10n.durationMinutes(minutes);
  }
  return l10n.durationHoursMinutes(hours, minutes);
}

String formatDueDate(BuildContext context, DateTime? date) {
  if (date == null) {
    return context.l10n.noDate;
  }
  return _formatDate(context, date);
}

String formatLocalDate(BuildContext context, DateTime date) =>
    _formatDate(context, date);

String formatCompactMonthRange(DateTime start, DateTime end, String locale) {
  final monthYear = intl.DateFormat.yMMM(locale);
  if (start.year != end.year) {
    return '${monthYear.format(start)}–${monthYear.format(end)}';
  }
  if (start.month == end.month) return monthYear.format(start);

  // Replace the month field in the locale's pattern, keeping year placement
  // and grammatical markers intact, including in numeric-month locales.
  final pattern = monthYear.pattern!;
  final monthField = RegExp(r'M+|L+').firstMatch(pattern)!;
  // A trailing space forces an explicit field pattern: the `M` skeleton in
  // Japanese expands to `M月`, whose marker already belongs to monthYear.
  final month = intl.DateFormat('${monthField.group(0)} ', locale);
  final range =
      '${month.format(start).trimRight()}–${month.format(end).trimRight()}'
          .replaceAll("'", "''");
  return intl.DateFormat(
    pattern.replaceRange(monthField.start, monthField.end, "'$range'"),
    locale,
  ).format(end);
}

String formatTaskSchedule(
  BuildContext context,
  TaskSchedule? schedule, {
  TaskTimeDisplayMode displayMode = TaskTimeDisplayMode.smart,
  int defaultTimedBlockMinutes = 30,
}) {
  final l10n = context.l10n;
  if (schedule == null) {
    return l10n.noDate;
  }
  final recurrence = _formatRecurrence(context, schedule.recurrence);
  String withRecurrence(String value) {
    return recurrence == null ? value : '$value, $recurrence';
  }

  if (schedule.isAllDay) {
    return withRecurrence(_formatDate(context, schedule.date!));
  }
  final start = schedule.start!.toLocal();
  final end = schedule.end!.toLocal();
  final sameDay =
      start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;
  final date = _formatDate(context, start);
  final startTime = _formatTime(context, start);
  final endTime = _formatTime(context, end);
  if (!shouldShowTaskTimeRange(
    schedule,
    displayMode,
    defaultTimedBlockMinutes: defaultTimedBlockMinutes,
  )) {
    return withRecurrence('$date, $startTime');
  }
  if (sameDay) {
    return withRecurrence('$date, $startTime-$endTime');
  }
  return withRecurrence(
    '$date, $startTime-${_formatDate(context, end)}, $endTime',
  );
}

String formatTaskListSchedule(
  BuildContext context,
  TaskSchedule schedule, {
  DateTime? now,
  TaskTimeDisplayMode displayMode = TaskTimeDisplayMode.smart,
  int defaultTimedBlockMinutes = 30,
}) {
  final date = schedule.displayDate;
  final dateLabel = _formatTaskListDate(context, date, now: now);
  if (schedule.isAllDay) {
    return _withRecurrence(context, dateLabel, schedule.recurrence);
  }
  final start = schedule.start!.toLocal();
  final end = schedule.end!.toLocal();
  final startTime = _formatTime(context, start);
  if (!shouldShowTaskTimeRange(
    schedule,
    displayMode,
    defaultTimedBlockMinutes: defaultTimedBlockMinutes,
  )) {
    return _withRecurrence(
      context,
      '$dateLabel $startTime',
      schedule.recurrence,
    );
  }
  final sameDay = _isSameDay(start, end);
  return _withRecurrence(
    context,
    sameDay
        ? '$dateLabel $startTime-${_formatTime(context, end)}'
        : '$dateLabel $startTime-${_formatTaskListDate(context, end, now: now)} ${_formatTime(context, end)}',
    schedule.recurrence,
  );
}

String? formatTaskListScheduleWithinDate(
  BuildContext context,
  TaskSchedule schedule, {
  TaskTimeDisplayMode displayMode = TaskTimeDisplayMode.smart,
  int defaultTimedBlockMinutes = 30,
}) {
  if (schedule.isAllDay) {
    return _formatRecurrence(context, schedule.recurrence);
  }
  final start = schedule.start!.toLocal();
  final end = schedule.end!.toLocal();
  final startTime = _formatTime(context, start);
  if (!shouldShowTaskTimeRange(
    schedule,
    displayMode,
    defaultTimedBlockMinutes: defaultTimedBlockMinutes,
  )) {
    return _withRecurrence(context, startTime, schedule.recurrence);
  }
  return _withRecurrence(
    context,
    _isSameDay(start, end)
        ? '$startTime-${_formatTime(context, end)}'
        : '$startTime-${_formatDate(context, end)} ${_formatTime(context, end)}',
    schedule.recurrence,
  );
}

String _withRecurrence(
  BuildContext context,
  String value,
  TaskRecurrence? recurrence,
) {
  final label = _formatRecurrence(context, recurrence);
  return label == null ? value : '$value, $label';
}

String? _formatRecurrence(BuildContext context, TaskRecurrence? recurrence) {
  if (recurrence == null) {
    return null;
  }
  final l10n = context.l10n;
  return switch (recurrence.unit) {
    TaskRecurrenceUnit.day => l10n.recurrenceEveryDays(recurrence.interval),
    TaskRecurrenceUnit.week => l10n.recurrenceEveryWeeks(recurrence.interval),
    TaskRecurrenceUnit.month => l10n.recurrenceEveryMonths(recurrence.interval),
  };
}

String _formatDate(BuildContext context, DateTime date) =>
    AppDateFormatter.of(context).format(
      date,
      automatic: () => MaterialLocalizations.of(context).formatMediumDate(date),
    );

String _formatTaskListDate(
  BuildContext context,
  DateTime date, {
  DateTime? now,
}) => AppDateFormatter.of(
  context,
).formatTaskListDate(date, context.l10n, now: now ?? DateTime.now());

bool _isSameDay(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

String _formatTime(BuildContext context, DateTime date) {
  return MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay.fromDateTime(date),
    alwaysUse24HourFormat:
        MediaQuery.maybeOf(context)?.alwaysUse24HourFormat ?? false,
  );
}

String focusIntervalTypeLabel(AppLocalizations l10n, String type) {
  return switch (type) {
    'work' => l10n.work,
    'longBreak' => l10n.longBreak,
    _ => l10n.breakLabel,
  };
}

String focusIntervalStatusLabel(AppLocalizations l10n, String status) {
  return switch (status) {
    'ready' => l10n.readyShort,
    'paused' => l10n.pause,
    'completed' => l10n.intervalCompleted,
    _ => status,
  };
}

List<List<String>> taskListScheduleRows(
  TaskSchedule? schedule, {
  required String Function(DateTime) formatDate,
  required String Function(DateTime) formatTime,
  String? recurrenceLabel,
  bool withinDate = false,
  TaskTimeDisplayMode displayMode = TaskTimeDisplayMode.smart,
  int defaultTimedBlockMinutes = 30,
}) {
  if (schedule == null) return [];
  final rows = <List<String>>[];
  if (schedule.isAllDay) {
    if (!withinDate) rows.add([formatDate(schedule.date!)]);
  } else {
    final start = schedule.start!.toLocal();
    final end = schedule.end!.toLocal();
    final showRange = shouldShowTaskTimeRange(
      schedule,
      displayMode,
      defaultTimedBlockMinutes: defaultTimedBlockMinutes,
    );
    final sameDay = _isSameDay(start, end);
    rows.add([
      if (!withinDate) formatDate(start),
      showRange && sameDay
          ? '${formatTime(start)}-${formatTime(end)}'
          : formatTime(start),
    ]);
    if (showRange && !sameDay) rows.add([formatDate(end), formatTime(end)]);
  }
  if (recurrenceLabel != null) rows.add([recurrenceLabel]);
  return rows;
}

/// Mobile rows keep date/time blocks whole and recurrence on a separate line.
List<List<String>> formatTaskListScheduleRows(
  BuildContext context,
  TaskSchedule? schedule, {
  DateTime? now,
  bool withinDate = false,
  TaskTimeDisplayMode displayMode = TaskTimeDisplayMode.smart,
  int defaultTimedBlockMinutes = 30,
}) => taskListScheduleRows(
  schedule,
  formatDate: (date) => withinDate
      ? _formatDate(context, date)
      : _formatTaskListDate(context, date, now: now),
  formatTime: (date) => _formatTime(context, date),
  recurrenceLabel: _formatRecurrence(context, schedule?.recurrence),
  withinDate: withinDate,
  displayMode: displayMode,
  defaultTimedBlockMinutes: defaultTimedBlockMinutes,
);
