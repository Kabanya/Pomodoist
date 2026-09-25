import 'package:pomodoist/domain/models/notifications/notification_copy.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';

extension NotificationCopyLocalizations on AppLocalizations {
  NotificationCopy get notificationCopy => NotificationCopy(
    focusCompleted: notificationFocusCompleted,
    longBreakCompleted: notificationLongBreakCompleted,
    breakCompleted: notificationBreakCompleted,
    focusChannel: notificationFocusChannel,
    focusDescription: notificationFocusDescription,
    taskChannel: notificationTaskChannel,
    taskDescription: notificationTaskDescription,
    returnChannel: notificationReturnChannel,
    returnDescription: notificationReturnDescription,
    openApp: notificationOpenApp,
    taskStarting: notificationTaskStarting,
    returnMessages: [
      (title: notificationReturnTitle, body: notificationReturnBody),
      (title: notificationReturnTitle2, body: notificationReturnBody2),
      (title: notificationReturnTitle3, body: notificationReturnBody3),
      (title: notificationReturnTitle4, body: notificationReturnBody4),
      (title: notificationReturnTitle5, body: notificationReturnBody5),
    ],
  );
}
