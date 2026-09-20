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
    returnTitle: notificationReturnTitle,
    returnBody: notificationReturnBody,
  );
}
