import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/core/notifications/notification_scheduler.dart';

void main() {
  test('Linux notifications provide the required initialization settings', () {
    final linux = NotificationScheduler.initializationSettings.linux;

    expect(linux, isNotNull);
    expect(linux!.defaultActionName, 'Open Pomodoist');
  });
}
