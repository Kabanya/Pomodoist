import 'package:pomodoist/domain/models/calendar/calendar_models.dart';
import 'package:pomodoist/data/services/local/calendar_local_service.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'google_calendar_repository.dart';

class DriftCalendarIntegrationRepository
    implements CalendarIntegrationRepository {
  DriftCalendarIntegrationRepository(AppDatabase db)
    : _calendar = CalendarLocalService(db);

  final CalendarLocalService _calendar;

  @override
  Stream<GoogleCalendarConnection?> watchConnection() {
    return _calendar.watchPrimaryConnection().map(_mapGoogleCalendarConnection);
  }

  @override
  Stream<GoogleCalendarEventLink?> watchLinkForTask(String taskId) {
    return _calendar.watchLinkForTask(taskId).map(_mapGoogleCalendarEventLink);
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
