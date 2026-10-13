import 'dart:convert';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/domain/models/calendar/provider_calendar_models.dart';

class ProviderCalendarRepository {
  ProviderCalendarRepository(this._db);
  final AppDatabase _db;

  Stream<List<CalendarConnection>> watchConnections() =>
      (_db.select(_db.calendarProjections)
            ..where((row) => row.entityType.equals('calendar_connection')))
          .watch()
          .map(
            (rows) => rows
                .map(
                  (row) => CalendarConnection.fromJson(
                    jsonDecode(row.dataJson) as Map<String, dynamic>,
                  ),
                )
                .toList(),
          );

  Stream<List<CalendarEventLink>> watchLinksForTask(String taskId) =>
      (_db.select(_db.calendarProjections)
            ..where((row) => row.entityType.equals('calendar_event_link')))
          .watch()
          .map(
            (rows) => rows
                .map(
                  (row) => CalendarEventLink.fromJson(
                    jsonDecode(row.dataJson) as Map<String, dynamic>,
                  ),
                )
                .where((link) => link.taskId == taskId)
                .toList(),
          );
}
