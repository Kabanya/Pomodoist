import 'package:pomodoist/data/services/local/database/app_database.dart';

class CalendarLocalService {
  CalendarLocalService(this._db);

  final AppDatabase _db;

  Stream<GoogleCalendarConnectionRow?> watchPrimaryConnection() {
    final query = _db.select(_db.googleCalendarConnections)
      ..where((row) => row.id.equals('primary'));
    return query.watchSingleOrNull();
  }

  Stream<GoogleCalendarEventLinkRow?> watchLinkForTask(String taskId) {
    final query = _db.select(_db.googleCalendarEventLinks)
      ..where((row) => row.taskId.equals(taskId));
    return query.watchSingleOrNull();
  }
}
