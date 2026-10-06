import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/domain/models/habits/habit_models.dart';

Habit habitFromRow(HabitRow row) => Habit(
  id: row.id,
  userId: row.userId,
  title: row.title,
  icon: row.icon,
  projectId: row.projectId,
  reminderMinutes: row.reminderMinutes,
  scheduleHistory: (jsonDecode(row.scheduleHistoryJson) as List).map(
    (s) => HabitSchedule.fromJson(Map<String, dynamic>.from(s as Map)),
  ),
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
  isDeleted: row.isDeleted,
);
HabitsCompanion habitToRow(Habit habit) => HabitsCompanion.insert(
  id: habit.id,
  userId: habit.userId,
  title: habit.title,
  icon: Value(habit.icon),
  projectId: Value(habit.projectId),
  reminderMinutes: Value(habit.reminderMinutes),
  scheduleHistoryJson: jsonEncode(
    habit.scheduleHistory.map((s) => s.toJson()).toList(),
  ),
  createdAt: habit.createdAt,
  updatedAt: habit.updatedAt,
  isDeleted: Value(habit.isDeleted),
);
HabitCheckIn habitCheckInFromRow(HabitCheckInRow row) => HabitCheckIn(
  id: row.id,
  userId: row.userId,
  habitId: row.habitId,
  day: habitDateFromKey(row.day),
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
  isDeleted: row.isDeleted,
  dayPeriod: row.dayPeriod == null
      ? null
      : HabitDayPeriod.values.byName(row.dayPeriod!),
);
HabitCheckInsCompanion habitCheckInToRow(HabitCheckIn checkIn) =>
    HabitCheckInsCompanion.insert(
      id: checkIn.id,
      userId: checkIn.userId,
      habitId: checkIn.habitId,
      day: habitDayKey(checkIn.day),
      createdAt: checkIn.createdAt,
      updatedAt: checkIn.updatedAt,
      isDeleted: Value(checkIn.isDeleted),
      dayPeriod: Value(checkIn.dayPeriod?.name),
    );
