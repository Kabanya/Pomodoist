import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class NotificationScheduler {
  NotificationScheduler({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const int focusNotificationId = 42;
  static const int reengagementNotificationId = 43;
  static const int windowsReengagementNotificationBaseId = 43000;
  static const int windowsReengagementReminderCount = 30;
  static const String taskStartPayloadPrefix = 'task.start:';

  static const InitializationSettings initializationSettings =
      InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
        macOS: DarwinInitializationSettings(),
        windows: WindowsInitializationSettings(
          appName: 'Pomodoist',
          appUserModelId: 'com.finchforge.pomodoist',
          guid: '8681f633-939c-46f5-84cc-18f295e4382c',
        ),
      );

  static const NotificationDetails focusDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'focus',
      'Focus',
      channelDescription: 'Focus interval completion notifications',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
    windows: WindowsNotificationDetails(),
  );

  static const NotificationDetails reengagementDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'return_reminders',
      'Return reminders',
      channelDescription: 'Gentle reminders to return to Pomodoist',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
    windows: WindowsNotificationDetails(),
  );

  static const NotificationDetails taskStartDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'task_start',
      'Task start',
      channelDescription: 'Task start notifications',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
    windows: WindowsNotificationDetails(),
  );

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) {
      _initialized = true;
      return;
    }

    tz_data.initializeTimeZones();
    final localTimeZone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTimeZone.identifier));
    await _plugin.initialize(settings: initializationSettings);
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
      notificationDetails: focusDetails,
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
    if (defaultTargetPlatform == TargetPlatform.windows) {
      await replaceWindowsReengagementReminders(
        firstAt: scheduled,
        cancel: (id) => _plugin.cancel(id: id),
        schedule: (reminder) => _plugin.zonedSchedule(
          id: reminder.id,
          title: title,
          body: body,
          scheduledDate: reminder.scheduledDate,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          notificationDetails: reengagementDetails,
          payload: 'reengagement.daily',
        ),
      );
      return;
    }
    await _plugin.zonedSchedule(
      id: reengagementNotificationId,
      title: title,
      body: body,
      scheduledDate: scheduled,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: reengagementDetails,
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
      notificationDetails: taskStartDetails,
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
    if (defaultTargetPlatform == TargetPlatform.windows) {
      await _cancelWindowsReengagementReminders();
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

  static List<({int id, tz.TZDateTime scheduledDate})>
  windowsReengagementReminders(tz.TZDateTime firstAt) {
    return List.generate(windowsReengagementReminderCount, (index) {
      return (
        id: windowsReengagementNotificationBaseId + index,
        scheduledDate: tz.TZDateTime(
          firstAt.location,
          firstAt.year,
          firstAt.month,
          firstAt.day + index,
          firstAt.hour,
          firstAt.minute,
          firstAt.second,
          firstAt.millisecond,
          firstAt.microsecond,
        ),
      );
    }, growable: false);
  }

  static Future<void> replaceWindowsReengagementReminders({
    required tz.TZDateTime firstAt,
    required Future<void> Function(int id) cancel,
    required Future<void> Function(
      ({int id, tz.TZDateTime scheduledDate}) reminder,
    )
    schedule,
  }) async {
    await cancelWindowsReengagementReminders(cancel);
    for (final reminder in windowsReengagementReminders(firstAt)) {
      await schedule(reminder);
    }
  }

  static Future<void> cancelWindowsReengagementReminders(
    Future<void> Function(int id) cancel,
  ) async {
    await cancel(reengagementNotificationId);
    for (var index = 0; index < windowsReengagementReminderCount; index++) {
      await cancel(windowsReengagementNotificationBaseId + index);
    }
  }

  Future<void> _cancelWindowsReengagementReminders() async {
    await cancelWindowsReengagementReminders((id) => _plugin.cancel(id: id));
  }
}
