class GoogleCalendarConnection {
  const GoogleCalendarConnection({
    required this.id,
    this.accountEmail,
    this.calendarId,
    this.ownerDeviceId,
    required this.calendarName,
    this.syncToken,
    required this.status,
    this.lastError,
    this.warning,
    this.lastSyncStartedAt,
    this.lastSyncFinishedAt,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id;
  final String? accountEmail;
  final String? calendarId;
  final String? ownerDeviceId;
  final String calendarName;
  final String? syncToken;
  final String status;
  final String? lastError;
  final String? warning;
  final DateTime? lastSyncStartedAt;
  final DateTime? lastSyncFinishedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class GoogleCalendarEventLink {
  const GoogleCalendarEventLink({
    required this.taskId,
    required this.calendarId,
    required this.eventId,
    this.etag,
    this.googleUpdatedAt,
    this.lastSyncedLocalUpdatedAt,
    this.unsupportedReason,
    required this.createdAt,
    required this.updatedAt,
  });
  final String taskId;
  final String calendarId;
  final String eventId;
  final String? etag;
  final DateTime? googleUpdatedAt;
  final DateTime? lastSyncedLocalUpdatedAt;
  final String? unsupportedReason;
  final DateTime createdAt;
  final DateTime updatedAt;
}
