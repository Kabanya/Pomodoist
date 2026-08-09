import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:pomodoist/l10n/app_localizations.dart';

import '../features/tasks/domain/task_models.dart';
import 'app_l10n.dart';

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

String formatTaskSchedule(BuildContext context, TaskSchedule? schedule) {
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
}) {
  final date = schedule.displayDate;
  final dateLabel = _formatTaskListDate(context, date, now: now);
  if (schedule.isAllDay) {
    return _withRecurrence(context, dateLabel, schedule.recurrence);
  }
  return _withRecurrence(
    context,
    '$dateLabel ${_formatTime(context, schedule.start!.toLocal())}',
    schedule.recurrence,
  );
}

String? formatTaskListScheduleWithinDate(
  BuildContext context,
  TaskSchedule schedule,
) {
  if (schedule.isAllDay) {
    return _formatRecurrence(context, schedule.recurrence);
  }
  return _withRecurrence(
    context,
    _formatTime(context, schedule.start!.toLocal()),
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
    MaterialLocalizations.of(context).formatMediumDate(date);

String _formatTaskListDate(
  BuildContext context,
  DateTime date, {
  DateTime? now,
}) {
  final l10n = context.l10n;
  final today = _dateOnly((now ?? DateTime.now()).toLocal());
  final day = _dateOnly(date.toLocal());
  final offset = day.difference(today).inDays;
  return switch (offset) {
    -1 => l10n.yesterday,
    0 => l10n.today,
    1 => l10n.tomorrow,
    _ => intl.DateFormat.MMMMd(l10n.localeName).format(day),
  };
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

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
