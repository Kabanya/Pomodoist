import '../../../tasks/domain/task_models.dart';

const googleCalendarDonePrefix = '[Done]';
const googleCalendarCompletedColorId = '8';

class GoogleCalendarListResult {
  const GoogleCalendarListResult({
    required this.events,
    this.nextPageToken,
    this.nextSyncToken,
  });

  final List<GoogleCalendarEvent> events;
  final String? nextPageToken;
  final String? nextSyncToken;
}

class GoogleCalendarEvent {
  const GoogleCalendarEvent({
    this.id,
    this.status,
    this.summary,
    this.description,
    this.start,
    this.end,
    this.etag,
    this.updated,
    this.htmlLink,
    this.colorId,
    this.clearColorId = false,
    this.recurrence = const [],
    this.privateExtendedProperties = const {},
  });

  final String? id;
  final String? status;
  final String? summary;
  final String? description;
  final GoogleCalendarEventTime? start;
  final GoogleCalendarEventTime? end;
  final String? etag;
  final DateTime? updated;
  final String? htmlLink;
  final String? colorId;
  final bool clearColorId;
  final List<String> recurrence;
  final Map<String, String> privateExtendedProperties;

  bool get isCancelled => status == 'cancelled';
  bool get isRecurring => recurrence.isNotEmpty;

  String? get pomodoistTaskId => privateExtendedProperties['pomodoistTaskId'];

  TaskSchedule? get schedule {
    final startValue = start;
    final endValue = end;
    if (startValue == null || endValue == null) {
      return null;
    }
    if (startValue.date != null) {
      return TaskSchedule.allDay(startValue.date!);
    }
    if (startValue.dateTime != null && endValue.dateTime != null) {
      return TaskSchedule.timed(
        start: startValue.dateTime!,
        end: endValue.dateTime!,
        timeZone: startValue.timeZone,
      );
    }
    return null;
  }

  factory GoogleCalendarEvent.fromJson(Map<String, Object?> json) {
    final extendedProperties = json['extendedProperties'];
    final privateProperties =
        extendedProperties is Map<String, Object?> &&
            extendedProperties['private'] is Map
        ? Map<Object?, Object?>.from(extendedProperties['private']! as Map)
        : const <Object?, Object?>{};
    return GoogleCalendarEvent(
      id: json['id'] as String?,
      status: json['status'] as String?,
      summary: json['summary'] as String?,
      description: json['description'] as String?,
      start: json['start'] is Map
          ? GoogleCalendarEventTime.fromJson(
              Map<String, Object?>.from(json['start']! as Map),
            )
          : null,
      end: json['end'] is Map
          ? GoogleCalendarEventTime.fromJson(
              Map<String, Object?>.from(json['end']! as Map),
            )
          : null,
      etag: json['etag'] as String?,
      updated: _parseDateTime(json['updated']),
      htmlLink: json['htmlLink'] as String?,
      colorId: json['colorId'] as String?,
      recurrence: json['recurrence'] is List
          ? (json['recurrence']! as List).whereType<String>().toList()
          : const [],
      privateExtendedProperties: privateProperties.map(
        (key, value) => MapEntry('$key', '$value'),
      ),
    );
  }

  Map<String, Object?> toJson() {
    return {
      if (summary != null) 'summary': summary,
      if (description != null) 'description': description,
      if (start != null) 'start': start!.toJson(),
      if (end != null) 'end': end!.toJson(),
      if (colorId != null)
        'colorId': colorId
      else if (clearColorId)
        'colorId': null,
      if (privateExtendedProperties.isNotEmpty)
        'extendedProperties': {'private': privateExtendedProperties},
    };
  }

  static DateTime? _parseDateTime(Object? value) {
    if (value is! String) {
      return null;
    }
    return DateTime.tryParse(value)?.toUtc();
  }
}

class GoogleCalendarEventTime {
  const GoogleCalendarEventTime({this.date, this.dateTime, this.timeZone});

  factory GoogleCalendarEventTime.allDay(DateTime date) {
    return GoogleCalendarEventTime(date: _dateOnly(date));
  }

  factory GoogleCalendarEventTime.timed(DateTime value, {String? timeZone}) {
    return GoogleCalendarEventTime(dateTime: value.toUtc(), timeZone: timeZone);
  }

  final DateTime? date;
  final DateTime? dateTime;
  final String? timeZone;

  factory GoogleCalendarEventTime.fromJson(Map<String, Object?> json) {
    return GoogleCalendarEventTime(
      date: _parseDate(json['date']),
      dateTime: _parseDateTime(json['dateTime']),
      timeZone: json['timeZone'] as String?,
    );
  }

  Map<String, Object?> toJson() {
    if (date != null) {
      return {'date': _formatDate(date!)};
    }
    final zone = _googleCalendarTimeZone(timeZone);
    return {'dateTime': dateTime!.toUtc().toIso8601String(), 'timeZone': ?zone};
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String) {
      return null;
    }
    final parts = value.split('-');
    if (parts.length != 3) {
      return null;
    }
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) {
      return null;
    }
    return DateTime(year, month, day);
  }

  static DateTime? _parseDateTime(Object? value) {
    if (value is! String) {
      return null;
    }
    return DateTime.tryParse(value)?.toUtc();
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static String _formatDate(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  static String? _googleCalendarTimeZone(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    if (trimmed == 'UTC') {
      return trimmed;
    }
    // ponytail: Google requires IANA names; DateTime.timeZoneName gives
    // abbreviations like MSK, so omit those because dateTime is already UTC.
    return RegExp(
          r'^[A-Za-z]+/[A-Za-z0-9_+\-]+(?:/[A-Za-z0-9_+\-]+)*$',
        ).hasMatch(trimmed)
        ? trimmed
        : null;
  }
}

GoogleCalendarEvent eventFromTask(
  TaskItem task, {
  bool clearActiveColor = false,
}) {
  final schedule = task.schedule;
  if (schedule == null) {
    throw ArgumentError.value(task.id, 'task', 'Task has no schedule');
  }
  final times = _eventTimes(schedule);
  return GoogleCalendarEvent(
    summary: titleForCalendar(task),
    description: task.description,
    start: times.$1,
    end: times.$2,
    colorId: task.isCompleted ? googleCalendarCompletedColorId : null,
    clearColorId: !task.isCompleted && clearActiveColor,
    privateExtendedProperties: {
      'pomodoistSource': 'pomodoist',
      'pomodoistTaskId': task.id,
    },
  );
}

String titleForCalendar(TaskItem task) {
  final content = stripDonePrefix(task.content);
  return task.isCompleted ? '$googleCalendarDonePrefix $content' : content;
}

String stripDonePrefix(String value) {
  final trimmed = value.trim();
  if (trimmed.startsWith(googleCalendarDonePrefix)) {
    return trimmed.substring(googleCalendarDonePrefix.length).trim();
  }
  return trimmed;
}

bool titleMarksDone(String? value) {
  return value?.trim().startsWith(googleCalendarDonePrefix) ?? false;
}

(GoogleCalendarEventTime, GoogleCalendarEventTime) _eventTimes(
  TaskSchedule schedule,
) {
  if (schedule.isAllDay) {
    final date = schedule.date!;
    return (
      GoogleCalendarEventTime.allDay(date),
      GoogleCalendarEventTime.allDay(date.add(const Duration(days: 1))),
    );
  }
  return (
    GoogleCalendarEventTime.timed(schedule.start!, timeZone: schedule.timeZone),
    GoogleCalendarEventTime.timed(schedule.end!, timeZone: schedule.timeZone),
  );
}
