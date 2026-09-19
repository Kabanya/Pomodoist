import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:pomodoist/domain/models/notifications/notification_copy.dart';

import 'package:pomodoist/data/services/notifications/android_alarm_policy.dart';

class NotificationScheduler {
  NotificationScheduler({
    FlutterLocalNotificationsPlugin? plugin,
    NotificationCopy Function()? localizations,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _localizations = localizations ?? NotificationCopy.english;

  final NotificationCopy Function() _localizations;

  String focusCompletedBody(String type) => switch (type) {
    'work' => _localizations().focusCompleted,
    'longBreak' => _localizations().longBreakCompleted,
    _ => _localizations().breakCompleted,
  };

  NotificationDetails localizedDetails(NotificationDetails base) {
    final copy = _localizations();
    final channel = base.android!;
    final (name, description) = switch (channel.channelId) {
      'focus' => (copy.focusChannel, copy.focusDescription),
      'task_start' => (copy.taskChannel, copy.taskDescription),
      _ => (copy.returnChannel, copy.returnDescription),
    };
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channel.channelId,
        name,
        channelDescription: description,
        importance: channel.importance,
        priority: channel.priority,
      ),
      iOS: base.iOS,
      macOS: base.macOS,
      windows: base.windows,
    );
  }

  static const int focusNotificationId = 42;
  static const int reengagementNotificationId = 43;
  static const int reengagementNotificationBaseId = 43000;
  // ponytail: keep 30 days queued; refill on app activity instead of background jobs.
  static const int reengagementReminderCount = 30;
  static const String taskStartPayloadPrefix = 'task.start:';

  static const InitializationSettings initializationSettings =
      InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(),
        macOS: DarwinInitializationSettings(),
        linux: LinuxInitializationSettings(defaultActionName: 'Open Pomodoist'),
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

  Future<void> refreshLanguage() async {
    if (kIsWeb) return;
    await initialize();
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      for (final details in [
        focusDetails,
        taskStartDetails,
        reengagementDetails,
      ]) {
        final channel = localizedDetails(details).android!;
        await android?.createNotificationChannel(
          AndroidNotificationChannel(
            channel.channelId,
            channel.channelName,
            description: channel.channelDescription,
            importance: channel.importance,
          ),
        );
      }
    }
    if (defaultTargetPlatform == TargetPlatform.linux) {
      _initialized = false;
      await initialize();
    }
  }

  Future<void> initialize() async {
    if (_initialized || kIsWeb) {
      _initialized = true;
      return;
    }

    tz_data.initializeTimeZones();
    final localTimeZone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTimeZone.identifier));
    await _plugin.initialize(
      settings: InitializationSettings(
        android: initializationSettings.android,
        iOS: initializationSettings.iOS,
        macOS: initializationSettings.macOS,
        windows: initializationSettings.windows,
        linux: LinuxInitializationSettings(
          defaultActionName: _localizations().openApp,
        ),
      ),
    );
    _initialized = true;
  }

  Future<void> _scheduleTimeSensitive(
    Future<void> Function(AndroidScheduleMode mode) schedule,
  ) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
      return;
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await scheduleAndroidAlarm(
      canScheduleExact: () async => android?.canScheduleExactNotifications(),
      schedule: schedule,
    );
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
    await _scheduleTimeSensitive(
      (mode) => _plugin.zonedSchedule(
        id: focusNotificationId,
        title: title,
        body: body,
        scheduledDate: scheduled,
        androidScheduleMode: mode,
        notificationDetails: localizedDetails(focusDetails),
        payload: 'focus.interval.end',
      ),
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
    // Use dated requests: Apple's time-only repeats ignore a tomorrow start.
    await replaceReengagementReminders(
      firstAt: scheduled,
      cancel: (id) => _plugin.cancel(id: id),
      schedule: (reminder) => _plugin.zonedSchedule(
        id: reminder.id,
        title: title,
        body: body,
        scheduledDate: reminder.scheduledDate,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        notificationDetails: localizedDetails(reengagementDetails),
        payload: 'reengagement.daily',
      ),
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
    await _scheduleTimeSensitive(
      (mode) => _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduled,
        androidScheduleMode: mode,
        notificationDetails: localizedDetails(taskStartDetails),
        payload: '$taskStartPayloadPrefix$taskId',
      ),
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
    await cancelReengagementReminders((id) => _plugin.cancel(id: id));
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

  static List<({int id, tz.TZDateTime scheduledDate})> reengagementReminders(
    tz.TZDateTime firstAt,
  ) {
    return List.generate(reengagementReminderCount, (index) {
      return (
        id: reengagementNotificationBaseId + index,
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

  static Future<void> replaceReengagementReminders({
    required tz.TZDateTime firstAt,
    required Future<void> Function(int id) cancel,
    required Future<void> Function(
      ({int id, tz.TZDateTime scheduledDate}) reminder,
    )
    schedule,
  }) async {
    await cancelReengagementReminders(cancel);
    for (final reminder in reengagementReminders(firstAt)) {
      await schedule(reminder);
    }
  }

  static Future<void> cancelReengagementReminders(
    Future<void> Function(int id) cancel,
  ) async {
    await cancel(reengagementNotificationId);
    for (var index = 0; index < reengagementReminderCount; index++) {
      await cancel(reengagementNotificationBaseId + index);
    }
  }
}
