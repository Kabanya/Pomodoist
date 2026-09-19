import 'package:pomodoist/domain/models/calendar/calendar_models.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'google_calendar_repository.dart';

class DriftCalendarIntegrationRepository
    implements CalendarIntegrationRepository {
  DriftCalendarIntegrationRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<GoogleCalendarConnection?> watchConnection() {
    final query = _db.select(_db.googleCalendarConnections)
      ..where((row) => row.id.equals('primary'));
    return query.watchSingleOrNull().map(_mapGoogleCalendarConnection);
  }

  @override
  Stream<GoogleCalendarEventLink?> watchLinkForTask(String taskId) {
    final query = _db.select(_db.googleCalendarEventLinks)
      ..where((row) => row.taskId.equals(taskId));
    return query.watchSingleOrNull().map(_mapGoogleCalendarEventLink);
  }
}

GoogleCalendarConnection? _mapGoogleCalendarConnection(
  GoogleCalendarConnectionRow? row,
) => row == null
    ? null
    : GoogleCalendarConnection(
        id: row.id,
        accountEmail: row.accountEmail,
        calendarId: row.calendarId,
        ownerDeviceId: row.ownerDeviceId,
        calendarName: row.calendarName,
        syncToken: row.syncToken,
        status: row.status,
        lastError: row.lastError,
        warning: row.warning,
        lastSyncStartedAt: row.lastSyncStartedAt,
        lastSyncFinishedAt: row.lastSyncFinishedAt,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );

GoogleCalendarEventLink? _mapGoogleCalendarEventLink(
  GoogleCalendarEventLinkRow? row,
) => row == null
    ? null
    : GoogleCalendarEventLink(
        taskId: row.taskId,
        calendarId: row.calendarId,
        eventId: row.eventId,
        etag: row.etag,
        googleUpdatedAt: row.googleUpdatedAt,
        lastSyncedLocalUpdatedAt: row.lastSyncedLocalUpdatedAt,
        unsupportedReason: row.unsupportedReason,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );
