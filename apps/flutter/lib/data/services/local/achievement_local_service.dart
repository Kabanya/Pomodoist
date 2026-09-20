import 'package:pomodoist/data/services/local/database/app_database.dart';

class AchievementLocalService {
  AchievementLocalService(this._db);

  final AppDatabase _db;

  Stream<List<TaskCompletionRow>> watchTaskCompletions() {
    return _db.select(_db.taskCompletions).watch();
  }

  Stream<List<FocusIntervalRow>> watchActiveFocusIntervals() {
    return (_db.select(
      _db.focusIntervals,
    )..where((interval) => interval.isDeleted.equals(false))).watch();
  }

  Future<List<TaskCompletionRow>> allTaskCompletions() {
    return _db.select(_db.taskCompletions).get();
  }

  Future<List<FocusIntervalRow>> activeFocusIntervals() {
    return (_db.select(
      _db.focusIntervals,
    )..where((interval) => interval.isDeleted.equals(false))).get();
  }
}
