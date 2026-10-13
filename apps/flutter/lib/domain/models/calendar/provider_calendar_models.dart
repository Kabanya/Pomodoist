import 'calendar_models.dart';

enum CalendarProvider { google, outlook }

/// Safe server projection. OAuth credentials are never stored on the client.
class CalendarConnection extends GoogleCalendarConnection {
  const CalendarConnection({
    required this.provider,
    required super.id,
    super.accountEmail,
    super.calendarId,
    required super.status,
    super.lastError,
    super.warning,
    super.lastSyncFinishedAt,
    required super.createdAt,
    required super.updatedAt,
  }) : super(calendarName: 'Pomodoist');
  final CalendarProvider provider;

  factory CalendarConnection.fromJson(Map<String, dynamic> json) =>
      CalendarConnection(
        provider: CalendarProvider.values.byName(json['provider'] as String),
        id: json['connectionId'] as String,
        accountEmail: json['accountEmail'] as String?,
        calendarId: json['calendarId'] as String?,
        status: json['status'] as String,
        lastError: json['lastError'] as String?,
        warning: json['warning'] as String?,
        lastSyncFinishedAt: _date(json['lastSyncFinishedAt']),
        createdAt:
            _date(json['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt:
            _date(json['updatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
  static DateTime? _date(dynamic value) => value is String
      ? DateTime.tryParse(value)
      : value is num
      ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
      : null;
}

class CalendarEventLink {
  const CalendarEventLink({
    required this.connectionId,
    required this.provider,
    required this.taskId,
    required this.eventId,
    this.unsupportedReason,
  });
  final String connectionId;
  final CalendarProvider provider;
  final String taskId;
  final String eventId;
  final String? unsupportedReason;
  factory CalendarEventLink.fromJson(Map<String, dynamic> json) =>
      CalendarEventLink(
        connectionId: json['connectionId'] as String,
        provider: CalendarProvider.values.byName(json['provider'] as String),
        taskId: json['taskId'] as String,
        eventId: json['eventId'] as String,
        unsupportedReason: json['unsupportedReason'] as String?,
      );
}
