import 'package:pomodoist/data/repositories/calendar/google_calendar_repository.dart';
import 'package:pomodoist/domain/models/calendar/calendar_models.dart';

import 'strict_fake.dart';

/// Configurable [CalendarIntegrationRepository] double.
///
/// Both streams emit the matching field and complete, and every call is
/// recorded in its `<method>Calls` list.
class FakeCalendarIntegrationRepository extends StrictFake
    implements CalendarIntegrationRepository {
  /// Connection emitted by [watchConnection]; null means not connected.
  GoogleCalendarConnection? connection;

  /// Link emitted by [watchLinkForTask]; null means the task is not linked.
  GoogleCalendarEventLink? linkForTask;

  final watchConnectionCalls = <void>[];
  final watchLinkForTaskCalls = <String>[];

  @override
  Stream<GoogleCalendarConnection?> watchConnection() {
    watchConnectionCalls.add(null);
    return Stream.value(connection);
  }

  @override
  Stream<GoogleCalendarEventLink?> watchLinkForTask(String taskId) {
    watchLinkForTaskCalls.add(taskId);
    return Stream.value(linkForTask);
  }
}
