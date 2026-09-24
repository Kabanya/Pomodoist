import 'dart:convert';

import 'task_models.dart';

enum CalendarMode { day, week, month, routine }

final class CalendarPeriod {
  CalendarPeriod({
    required this.name,
    required this.startMinutes,
    required this.endMinutes,
  }) {
    if (startMinutes < 0 || endMinutes > 1440 || endMinutes <= startMinutes) {
      throw ArgumentError('Period must fit within one day');
    }
  }

  final String name;
  final int startMinutes;
  final int endMinutes;

  Map<String, Object> toJson() => {
    'name': name,
    'startMinutes': startMinutes,
    'endMinutes': endMinutes,
  };
}

final class CalendarSettings {
  CalendarSettings({
    this.mode = CalendarMode.week,
    this.routineName = '',
    List<CalendarPeriod>? periods,
  }) : periods = List.unmodifiable(periods ?? defaultPeriods) {
    var previousEnd = 0;
    for (final period in this.periods) {
      if (period.startMinutes < previousEnd) {
        throw ArgumentError(
          'Routine periods must be ordered and non-overlapping',
        );
      }
      previousEnd = period.endMinutes;
    }
  }

  static final List<CalendarPeriod> defaultPeriods = List.unmodifiable([
    CalendarPeriod(name: '', startMinutes: 540, endMinutes: 720),
    CalendarPeriod(name: '', startMinutes: 720, endMinutes: 900),
    CalendarPeriod(name: '', startMinutes: 900, endMinutes: 1140),
  ]);

  static void validateRoutine(String name, List<CalendarPeriod> periods) {
    if (name.trim().isEmpty ||
        periods.isEmpty ||
        periods.any((period) => period.name.trim().isEmpty)) {
      throw ArgumentError('Routine and period names are required');
    }
    CalendarSettings(periods: periods);
  }

  final CalendarMode mode;
  final String routineName;
  final List<CalendarPeriod> periods;

  CalendarSettings copyWith({
    CalendarMode? mode,
    String? routineName,
    List<CalendarPeriod>? periods,
  }) => CalendarSettings(
    mode: mode ?? this.mode,
    routineName: routineName ?? this.routineName,
    periods: periods ?? this.periods,
  );

  String toJsonString() => jsonEncode({
    'mode': mode.name,
    'routineName': routineName,
    'periods': [for (final period in periods) period.toJson()],
  });

  static CalendarSettings fromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return CalendarSettings();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return CalendarSettings();
      final mode = CalendarMode.values
          .where((value) => value.name == decoded['mode'])
          .firstOrNull;
      final storedPeriods = decoded['periods'];
      final periods = <CalendarPeriod>[];
      if (storedPeriods is List) {
        for (final value in storedPeriods) {
          if (value is! Map ||
              value['name'] is! String ||
              value['startMinutes'] is! int ||
              value['endMinutes'] is! int) {
            return CalendarSettings();
          }
          periods.add(
            CalendarPeriod(
              name: value['name'] as String,
              startMinutes: value['startMinutes'] as int,
              endMinutes: value['endMinutes'] as int,
            ),
          );
        }
      }
      return CalendarSettings(
        mode: mode ?? CalendarMode.week,
        routineName: decoded['routineName'] is String
            ? decoded['routineName'] as String
            : '',
        periods: storedPeriods is List ? periods : null,
      );
    } catch (_) {
      return CalendarSettings();
    }
  }
}

final class CalendarEvent {
  const CalendarEvent({
    required this.task,
    required this.startMinutes,
    required this.endMinutes,
    required this.lane,
    required this.laneCount,
    required this.continuesBefore,
    required this.continuesAfter,
  });

  final TaskItem task;
  final int startMinutes;
  final int endMinutes;
  final int lane;
  final int laneCount;
  final bool continuesBefore;
  final bool continuesAfter;
}

final class CalendarDay {
  CalendarDay({
    required this.date,
    required List<TaskItem> allDay,
    required List<CalendarEvent> events,
    required List<TaskItem> tasks,
  }) : allDay = List.unmodifiable(allDay),
       events = List.unmodifiable(events),
       tasks = List.unmodifiable(tasks);

  final DateTime date;
  final List<TaskItem> allDay;
  final List<CalendarEvent> events;
  final List<TaskItem> tasks;
}

final class CalendarPresentation {
  CalendarPresentation({
    required List<CalendarDay> days,
    required List<TaskItem> unscheduled,
    required Map<String, ProjectItem> projectsById,
  }) : days = List.unmodifiable(days),
       unscheduled = List.unmodifiable(unscheduled),
       projectsById = Map.unmodifiable(projectsById);

  final List<CalendarDay> days;
  final List<TaskItem> unscheduled;
  final Map<String, ProjectItem> projectsById;
}

final class CalendarRoutineDay {
  CalendarRoutineDay({
    required this.day,
    required List<List<TaskItem>> periods,
    required List<TaskItem> outside,
  }) : periods = List.unmodifiable(periods.map(List<TaskItem>.unmodifiable)),
       outside = List.unmodifiable(outside);

  final CalendarDay day;
  final List<List<TaskItem>> periods;
  final List<TaskItem> outside;
}
