import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class NotificationScheduler {
  NotificationScheduler({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const int focusNotificationId = 42;
  static const int reengagementNotificationId = 43;
  static const String taskStartPayloadPrefix = 'task.start:';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) {
      _initialized = true;
      return;
    }

    tz_data.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
        macOS: DarwinInitializationSettings(),
      ),
    );
    _initialized = true;
  }

  Future<void> scheduleFocusIntervalEnd({
    required DateTime expectedEndAt,
    required String title,
    required String body,
  }) async {
    await initialize();
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.linux) {
      return;
    }

    final scheduled = tz.TZDateTime.from(expectedEndAt.toLocal(), tz.local);
    await _plugin.zonedSchedule(
      id: focusNotificationId,
      title: title,
      body: body,
      scheduledDate: scheduled,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'focus',
          'Focus',
          channelDescription: 'Focus interval completion notifications',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      ),
      payload: 'focus.interval.end',
    );
  }

  Future<void> scheduleReengagementReminder({
    required DateTime firstAt,
    required String title,
    required String body,
  }) async {
    await initialize();
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.linux) {
      return;
    }

    final scheduled = tz.TZDateTime.from(firstAt.toLocal(), tz.local);
    await _plugin.zonedSchedule(
      id: reengagementNotificationId,
      title: title,
      body: body,
      scheduledDate: scheduled,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'return_reminders',
          'Return reminders',
          channelDescription: 'Gentle reminders to return to Pomodoist',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      ),
      payload: 'reengagement.daily',
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> scheduleTaskStart({
    required String taskId,
    required DateTime startAt,
    required String title,
    required String body,
  }) async {
    await initialize();
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.linux) {
      return;
    }

    final id = taskStartNotificationId(taskId);
    final scheduled = tz.TZDateTime.from(startAt.toLocal(), tz.local);
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduled,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'task_start',
          'Task start',
          channelDescription: 'Task start notifications',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      ),
      payload: '$taskStartPayloadPrefix$taskId',
    );
  }

  Future<void> requestNotificationPermissions() async {
    await initialize();
    if (kIsWeb) {
      return;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      case TargetPlatform.iOS:
        await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      case TargetPlatform.macOS:
        await _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return;
    }
  }

  Future<void> cancelReengagementReminder() async {
    await initialize();
    if (kIsWeb) {
      return;
    }
    await _plugin.cancel(id: reengagementNotificationId);
  }

  Future<void> cancelFocusNotification() async {
    await initialize();
    if (kIsWeb) {
      return;
    }
    await _plugin.cancel(id: focusNotificationId);
  }

  Future<void> cancelTaskStart(String taskId) async {
    await initialize();
    if (kIsWeb) {
      return;
    }
    await _plugin.cancel(id: taskStartNotificationId(taskId));
  }

  Future<Set<String>> pendingTaskStartTaskIds() async {
    await initialize();
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.linux) {
      return const {};
    }
    final pending = await _plugin.pendingNotificationRequests();
    return {
      for (final request in pending)
        if (request.payload?.startsWith(taskStartPayloadPrefix) ?? false)
          request.payload!.substring(taskStartPayloadPrefix.length),
    };
  }

  static int taskStartNotificationId(String taskId) {
    var hash = 0x811c9dc5;
    for (final codeUnit in taskId.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return 100000 + hash;
  }
}
