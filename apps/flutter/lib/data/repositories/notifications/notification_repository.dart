import 'package:pomodoist/domain/models/tasks/task_models.dart';

/// Domain-facing notification operations. Scheduling copy is resolved by the
/// implementation from an injected localization source; callers pass domain
/// requests only.
abstract interface class NotificationRepository {
  Future<void> initialize();
  Future<void> refreshLanguage();
  Future<void> requestPermission();
  Future<void> scheduleFocusIntervalEnd({
    required DateTime expectedEndAt,
    required String intervalType,
  });
  Future<void> cancelFocusIntervalEnd();
  Future<void> syncTaskStartNotifications({
    required List<TaskItem> tasks,
    required DateTime now,
  });
  Future<void> syncReengagementReminder({
    required bool enabled,
    required DateTime now,
    required bool hasProgressToday,
  });
  Future<void> cancelReengagementReminder();
}
