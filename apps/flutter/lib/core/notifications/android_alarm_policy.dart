import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Prefer exact task/focus reminders only when the user already granted access.
/// Never opens a settings screen during startup or background rescheduling.
Future<void> scheduleAndroidAlarm({
  required Future<bool?> Function() canScheduleExact,
  required Future<void> Function(AndroidScheduleMode mode) schedule,
}) async {
  var exact = false;
  try {
    exact = await canScheduleExact() ?? false;
  } on PlatformException {
    // Capability checks can fail independently of ordinary notification access.
  }
  final mode = exact
      ? AndroidScheduleMode.exactAllowWhileIdle
      : AndroidScheduleMode.inexactAllowWhileIdle;
  try {
    await schedule(mode);
  } on PlatformException catch (error) {
    if (!exact || error.code != 'exact_alarms_not_permitted') {
      rethrow;
    }
    // Access may be revoked after the capability check. Do not lose the reminder.
    await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
  }
}
