import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/core/notifications/notification_scheduler.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(tz_data.initializeTimeZones);

  test('Windows reengagement reminders cover 30 local calendar days', () {
    final berlin = tz.getLocation('Europe/Berlin');
    final firstAt = tz.TZDateTime(berlin, 2026, 3, 28, 20, 30);

    final reminders = NotificationScheduler.windowsReengagementReminders(
      firstAt,
    );

    expect(reminders, hasLength(30));
    expect(reminders.map((reminder) => reminder.id).toSet(), hasLength(30));
    expect(reminders.first.id, 43000);
    expect(reminders.last.id, 43029);
    expect(
      reminders.first.scheduledDate,
      tz.TZDateTime(berlin, 2026, 3, 28, 20, 30),
    );
    expect(
      reminders[1].scheduledDate,
      tz.TZDateTime(berlin, 2026, 3, 29, 20, 30),
    );
    expect(
      reminders.last.scheduledDate,
      tz.TZDateTime(berlin, 2026, 4, 26, 20, 30),
    );
    expect(
      reminders.first.scheduledDate.timeZoneOffset,
      const Duration(hours: 1),
    );
    expect(reminders[1].scheduledDate.timeZoneOffset, const Duration(hours: 2));
  });

  test('Windows notifications use the Pomodoist package identity', () {
    final windows = NotificationScheduler.initializationSettings.windows;

    expect(windows, isNotNull);
    expect(windows!.appName, 'Pomodoist');
    expect(windows.appUserModelId, 'com.finchforge.pomodoist');
    expect(windows.guid, '8681f633-939c-46f5-84cc-18f295e4382c');

    expect(NotificationScheduler.focusDetails.windows, isNotNull);
    expect(NotificationScheduler.reengagementDetails.windows, isNotNull);
    expect(NotificationScheduler.taskStartDetails.windows, isNotNull);
  });

  test('Windows reminder replacement cancels the whole range first', () async {
    final berlin = tz.getLocation('Europe/Berlin');
    final firstAt = tz.TZDateTime(berlin, 2026, 10, 24, 20, 30);
    final events = <String>[];

    await NotificationScheduler.replaceWindowsReengagementReminders(
      firstAt: firstAt,
      cancel: (id) async => events.add('cancel:$id'),
      schedule: (reminder) async => events.add('schedule:${reminder.id}'),
    );

    expect(events, hasLength(61));
    expect(events.first, 'cancel:43');
    expect(events[1], 'cancel:43000');
    expect(events[30], 'cancel:43029');
    expect(events[31], 'schedule:43000');
    expect(events.last, 'schedule:43029');
    expect(
      events.take(31).every((event) => event.startsWith('cancel:')),
      isTrue,
    );
    expect(
      events.skip(31).every((event) => event.startsWith('schedule:')),
      isTrue,
    );
  });
}
