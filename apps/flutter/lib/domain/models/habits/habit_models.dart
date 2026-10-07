/// Habit dates are calendar values, never instants converted through UTC.
DateTime habitDate(DateTime value) =>
    DateTime(value.year, value.month, value.day);
String habitDayKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
DateTime habitDateFromKey(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const FormatException('Invalid habit date');
  }
  final date = DateTime.tryParse(value);
  if (date == null || date.year < 1 || habitDayKey(date) != value) {
    throw const FormatException('Invalid habit date');
  }
  return habitDate(date);
}

DateTime habitEndAfterDays(DateTime start, int days) {
  if (days < 1) throw ArgumentError.value(days);
  return DateTime(start.year, start.month, start.day + days - 1);
}

enum HabitViewMode { list, rhythm }

enum HabitDayPeriod { automatic, anytime, morning, afternoon, evening, night }

HabitDayPeriod resolveHabitDayPeriod({
  HabitDayPeriod selection = HabitDayPeriod.automatic,
  required int target,
  int? reminderMinutes,
}) {
  if (selection != HabitDayPeriod.automatic) return selection;
  if (target > 1 || reminderMinutes == null) return HabitDayPeriod.anytime;
  return switch (reminderMinutes) {
    < 300 => HabitDayPeriod.night,
    < 720 => HabitDayPeriod.morning,
    < 1080 => HabitDayPeriod.afternoon,
    _ => HabitDayPeriod.evening,
  };
}

HabitDayPeriod _habitDayPeriodFromJson(Object? value) {
  return HabitDayPeriod.values.where((p) => p.name == value).firstOrNull ??
      (throw const FormatException('Invalid habit day period'));
}

Map<HabitDayPeriod, int> habitPeriodTargetsFromJson(Object? value) {
  if (value is! Map || value.isEmpty) {
    throw const FormatException('Invalid habit period targets');
  }
  final result = <HabitDayPeriod, int>{};
  for (final entry in value.entries) {
    final period = _habitDayPeriodFromJson(entry.key);
    if (period == HabitDayPeriod.automatic ||
        period == HabitDayPeriod.anytime ||
        entry.value is! int ||
        (entry.value as int) < 1 ||
        (entry.value as int) > 99) {
      throw const FormatException('Invalid habit period targets');
    }
    result[period] = entry.value as int;
  }
  return result;
}

class HabitSchedule {
  HabitSchedule({
    required DateTime effectiveFrom,
    required DateTime startDate,
    DateTime? endDate,
    required Iterable<int> weekdays,
    required this.targetPerDay,
    this.dayPeriod = HabitDayPeriod.automatic,
    Map<HabitDayPeriod, int> periodTargets = const {},
  }) : periodTargets = Map.unmodifiable(periodTargets),
       effectiveFrom = habitDate(effectiveFrom),
       startDate = habitDate(startDate),
       endDate = endDate == null ? null : habitDate(endDate),
       weekdays = List.unmodifiable(weekdays) {
    if (targetPerDay < 1 ||
        targetPerDay > 99 ||
        this.weekdays.isEmpty ||
        this.weekdays.any((d) => d < 1 || d > 7) ||
        this.weekdays.toSet().length != this.weekdays.length ||
        this.endDate != null && this.endDate!.isBefore(this.startDate)) {
      throw ArgumentError('Invalid habit schedule');
    }
    if (this.periodTargets.isNotEmpty &&
        (dayPeriod != HabitDayPeriod.automatic ||
            this.periodTargets.keys.any(
              (p) =>
                  p == HabitDayPeriod.automatic || p == HabitDayPeriod.anytime,
            ) ||
            this.periodTargets.values.any((n) => n < 1 || n > 99) ||
            this.periodTargets.values.fold(0, (a, b) => a + b) !=
                targetPerDay)) {
      throw ArgumentError('Invalid habit period targets');
    }
  }
  final DateTime effectiveFrom, startDate;
  final DateTime? endDate;
  final List<int> weekdays;
  final int targetPerDay;
  final HabitDayPeriod dayPeriod;
  final Map<HabitDayPeriod, int> periodTargets;
  Map<HabitDayPeriod, int> targetsFor(int? reminderMinutes) =>
      periodTargets.isNotEmpty
      ? {
          for (final p in HabitDayPeriod.values)
            if (periodTargets.containsKey(p)) p: periodTargets[p]!,
        }
      : {
          resolveHabitDayPeriod(
            selection: dayPeriod,
            target: targetPerDay,
            reminderMinutes: reminderMinutes,
          ): targetPerDay,
        };
  bool includes(DateTime value) {
    final day = habitDate(value);
    return !day.isBefore(startDate) &&
        (endDate == null || !day.isAfter(endDate!)) &&
        weekdays.contains(day.weekday);
  }

  Map<String, Object?> toJson() => {
    'effectiveFrom': habitDayKey(effectiveFrom),
    'startDate': habitDayKey(startDate),
    'endDate': endDate == null ? null : habitDayKey(endDate!),
    'weekdays': weekdays,
    'targetPerDay': targetPerDay,
    if (dayPeriod != HabitDayPeriod.automatic) 'dayPeriod': dayPeriod.name,
    if (periodTargets.isNotEmpty)
      'periodTargets': {
        for (final e in periodTargets.entries) e.key.name: e.value,
      },
  };
  factory HabitSchedule.fromJson(Map<String, dynamic> json) => HabitSchedule(
    effectiveFrom: habitDateFromKey(json['effectiveFrom'] as String),
    startDate: habitDateFromKey(json['startDate'] as String),
    endDate: json['endDate'] == null
        ? null
        : habitDateFromKey(json['endDate'] as String),
    weekdays: (json['weekdays'] as List).cast<int>(),
    targetPerDay: json['targetPerDay'] as int,
    dayPeriod: json.containsKey('dayPeriod')
        ? _habitDayPeriodFromJson(json['dayPeriod'])
        : HabitDayPeriod.automatic,
    periodTargets: json.containsKey('periodTargets')
        ? habitPeriodTargetsFromJson(json['periodTargets'])
        : const {},
  );
}

class Habit {
  Habit({
    required this.id,
    required this.userId,
    required this.title,
    this.icon,
    this.projectId,
    this.reminderMinutes,
    required Iterable<HabitSchedule> scheduleHistory,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  }) : scheduleHistory = List.unmodifiable(scheduleHistory) {
    if (id.isEmpty ||
        title.trim().isEmpty ||
        title.length > 200 ||
        this.scheduleHistory.isEmpty ||
        reminderMinutes != null &&
            (reminderMinutes! < 0 || reminderMinutes! > 1439)) {
      throw ArgumentError('Invalid habit');
    }
    for (var i = 1; i < this.scheduleHistory.length; i++) {
      if (!this.scheduleHistory[i].effectiveFrom.isAfter(
        this.scheduleHistory[i - 1].effectiveFrom,
      )) {
        throw ArgumentError('Habit schedule versions must be ordered');
      }
    }
  }
  final String id, userId, title;
  final String? icon, projectId;
  final int? reminderMinutes;
  final List<HabitSchedule> scheduleHistory;
  final DateTime createdAt, updatedAt;
  final bool isDeleted;
  HabitSchedule? scheduleFor(DateTime value) {
    final day = habitDate(value);
    HabitSchedule? result;
    for (final schedule in scheduleHistory) {
      if (!schedule.effectiveFrom.isAfter(day)) result = schedule;
    }
    return result;
  }

  bool isScheduledOn(DateTime day) =>
      !isDeleted && (scheduleFor(day)?.includes(day) ?? false);
  bool isFinishedOn(DateTime value) =>
      !isDeleted &&
      scheduleHistory.last.endDate != null &&
      scheduleHistory.last.endDate!.isBefore(habitDate(value));
  Map<String, Object?> toJson() => {
    'id': id,
    'userId': userId,
    'title': title,
    'icon': icon,
    'projectId': projectId,
    'reminderMinutes': reminderMinutes,
    'scheduleHistory': scheduleHistory.map((s) => s.toJson()).toList(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'isDeleted': isDeleted,
  };
  factory Habit.fromJson(Map<String, dynamic> json) => Habit(
    id: json['id'] as String,
    userId: json['userId'] as String,
    title: json['title'] as String,
    icon: json['icon'] as String?,
    projectId: json['projectId'] as String?,
    reminderMinutes: json['reminderMinutes'] as int?,
    scheduleHistory: (json['scheduleHistory'] as List).map(
      (s) => HabitSchedule.fromJson(Map<String, dynamic>.from(s as Map)),
    ),
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    isDeleted: json['isDeleted'] as bool? ?? false,
  );
}

class HabitDraft {
  HabitDraft({
    required String title,
    required DateTime startDate,
    DateTime? endDate,
    Iterable<int> weekdays = const [1, 2, 3, 4, 5, 6, 7],
    int targetPerDay = 1,
    Map<HabitDayPeriod, int> periodTargets = const {},
    this.dayPeriod = HabitDayPeriod.automatic,
    this.icon,
    this.projectId,
    this.reminderMinutes,
  }) : periodTargets = Map.unmodifiable(periodTargets),
       targetPerDay = periodTargets.isEmpty
           ? targetPerDay
           : periodTargets.values.fold(0, (a, b) => a + b),
       title = title.trim(),
       startDate = habitDate(startDate),
       endDate = endDate == null ? null : habitDate(endDate),
       weekdays = List.unmodifiable(weekdays) {
    if (this.title.isEmpty ||
        this.title.length > 200 ||
        reminderMinutes != null &&
            (reminderMinutes! < 0 || reminderMinutes! > 1439)) {
      throw ArgumentError('Invalid habit draft');
    }
    schedule(this.startDate);
  }
  final String title;
  final DateTime startDate;
  final DateTime? endDate;
  final List<int> weekdays;
  final int targetPerDay;
  final HabitDayPeriod dayPeriod;
  final Map<HabitDayPeriod, int> periodTargets;
  final String? icon, projectId;
  final int? reminderMinutes;
  HabitSchedule schedule(DateTime effectiveFrom) => HabitSchedule(
    effectiveFrom: effectiveFrom,
    startDate: startDate,
    endDate: endDate,
    weekdays: weekdays,
    targetPerDay: targetPerDay,
    dayPeriod: dayPeriod,
    periodTargets: periodTargets,
  );
}

class HabitCheckIn {
  HabitCheckIn({
    required this.id,
    required this.userId,
    required this.habitId,
    required DateTime day,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
    this.dayPeriod,
  }) : day = habitDate(day) {
    if (id.isEmpty ||
        userId.isEmpty ||
        habitId.isEmpty ||
        dayPeriod == HabitDayPeriod.automatic) {
      throw ArgumentError('Invalid habit check-in');
    }
  }
  final String id, userId, habitId;
  final DateTime day, createdAt, updatedAt;
  final bool isDeleted;
  final HabitDayPeriod? dayPeriod;
  Map<String, Object?> toJson() => {
    'id': id,
    'userId': userId,
    'habitId': habitId,
    'day': habitDayKey(day),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'isDeleted': isDeleted,
    if (dayPeriod != null) 'dayPeriod': dayPeriod!.name,
  };
  factory HabitCheckIn.fromJson(Map<String, dynamic> json) => HabitCheckIn(
    id: json['id'] as String,
    userId: json['userId'] as String,
    habitId: json['habitId'] as String,
    day: habitDateFromKey(json['day'] as String),
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    isDeleted: json['isDeleted'] as bool? ?? false,
    dayPeriod: json.containsKey('dayPeriod')
        ? _habitDayPeriodFromJson(json['dayPeriod'])
        : null,
  );
}

int habitCompletionCount(
  String id,
  DateTime day,
  Iterable<HabitCheckIn> checkIns,
) => checkIns
    .where((c) => c.habitId == id && !c.isDeleted && c.day == habitDate(day))
    .length;

/// Assign legacy/unassigned marks deterministically without changing their data.
/// Explicit marks retain their period; obsolete periods follow the same fallback.
Map<String, HabitDayPeriod> habitCheckInPeriods(
  Habit habit,
  DateTime day,
  Iterable<HabitCheckIn> checkIns,
) {
  final schedule = habit.scheduleFor(day);
  if (schedule == null) return {};
  final targets = schedule.targetsFor(habit.reminderMinutes);
  final checks =
      checkIns
          .where(
            (c) =>
                !c.isDeleted &&
                c.habitId == habit.id &&
                c.day == habitDate(day),
          )
          .toList()
        ..sort((a, b) {
          final order = a.createdAt.compareTo(b.createdAt);
          return order == 0 ? a.id.compareTo(b.id) : order;
        });
  final assigned = <String, HabitDayPeriod>{};
  final counts = {for (final p in targets.keys) p: 0};
  for (final check in checks) {
    if (check.dayPeriod != null && targets.containsKey(check.dayPeriod)) {
      assigned[check.id] = check.dayPeriod!;
      counts[check.dayPeriod!] = counts[check.dayPeriod!]! + 1;
    }
  }
  for (final check in checks) {
    if (assigned.containsKey(check.id)) continue;
    final period =
        targets.keys.where((p) => counts[p]! < targets[p]!).firstOrNull ??
        targets.keys.first;
    assigned[check.id] = period;
    counts[period] = counts[period]! + 1;
  }
  return assigned;
}

Map<HabitDayPeriod, int> habitPeriodCounts(
  Habit habit,
  DateTime day,
  Iterable<HabitCheckIn> checks,
) {
  final targets =
      habit.scheduleFor(day)?.targetsFor(habit.reminderMinutes) ??
      <HabitDayPeriod, int>{};
  final assigned = habitCheckInPeriods(habit, day, checks);
  return {
    for (final e in targets.entries)
      e.key: assigned.values.where((p) => p == e.key).length.clamp(0, e.value),
  };
}
