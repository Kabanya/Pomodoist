import 'package:pomodoist/domain/models/habits/habit_models.dart';
import 'package:pomodoist/utils/result.dart';

abstract interface class HabitRepository {
  Stream<List<Habit>> watchHabits();
  Stream<List<HabitCheckIn>> watchCheckIns();
  Future<Result<String>> createHabit(HabitDraft draft, {required DateTime now});
  Future<Result<void>> updateHabit(
    String id,
    HabitDraft draft, {
    required DateTime now,
  });
  Future<Result<void>> updateIcon(
    String id,
    String? icon, {
    required DateTime now,
  });
  Future<Result<void>> deleteHabit(String id, {required DateTime now});
  Future<Result<void>> addCheckIn(
    String id,
    DateTime day, {
    required DateTime now,
    HabitDayPeriod? period,
  });
  Future<Result<void>> undoCheckIn(
    String id,
    DateTime day, {
    required DateTime now,
    HabitDayPeriod? period,
  });
}
