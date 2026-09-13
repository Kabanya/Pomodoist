import '../../../../core/db/app_database.dart';

abstract interface class CalendarIntegrationRepository {
  Stream<GoogleCalendarConnectionRow?> watchConnection();
  Stream<GoogleCalendarEventLinkRow?> watchLinkForTask(String taskId);
}

class DriftCalendarIntegrationRepository
    implements CalendarIntegrationRepository {
  DriftCalendarIntegrationRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<GoogleCalendarConnectionRow?> watchConnection() {
    final query = _db.select(_db.googleCalendarConnections)
      ..where((row) => row.id.equals('primary'));
    return query.watchSingleOrNull();
  }

  @override
  Stream<GoogleCalendarEventLinkRow?> watchLinkForTask(String taskId) {
    final query = _db.select(_db.googleCalendarEventLinks)
      ..where((row) => row.taskId.equals(taskId));
    return query.watchSingleOrNull();
  }
}
