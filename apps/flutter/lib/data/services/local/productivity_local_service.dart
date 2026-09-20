import 'package:pomodoist/data/services/local/database/app_database.dart';

class ProductivityLocalService {
  ProductivityLocalService(this._db);

  final AppDatabase _db;

  Stream<List<TaskRow>> watchTasks() {
    return _db.select(_db.tasks).watch();
  }

  Stream<List<FocusIntervalRow>> watchFocusIntervals() {
    return _db.select(_db.focusIntervals).watch();
  }

  Stream<List<TaskCompletionRow>> watchTaskCompletions() {
    return _db.select(_db.taskCompletions).watch();
  }

  Future<void> insertDailyStats(FocusDailyStatsCompanion stats) {
    return _db.into(_db.focusDailyStats).insertOnConflictUpdate(stats);
  }

  Future<List<TaskRow>> activeTasks() {
    return (_db.select(
      _db.tasks,
    )..where((task) => task.isDeleted.equals(false))).get();
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
