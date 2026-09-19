import 'package:pomodoist/domain/models/calendar/calendar_models.dart';

abstract interface class CalendarIntegrationRepository {
  Stream<GoogleCalendarConnection?> watchConnection();
  Stream<GoogleCalendarEventLink?> watchLinkForTask(String taskId);
}
