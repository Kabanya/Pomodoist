import 'package:pomodoist/data/services/notifications/notification_scheduler.dart';
import 'package:pomodoist/domain/models/notifications/notification_copy.dart';

/// Double for [NotificationScheduler] that records what the app scheduled.
///
/// Nothing reaches a platform channel: [initialize] is inert, task-start
/// scheduling only succeeds silently, and the only recorded call is
/// [cancelReengagementReminder].
class FakeNotificationScheduler extends NotificationScheduler {
  /// Number of [cancelReengagementReminder] calls.
  int cancelReengagementCount = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> cancelReengagementReminder() async {
    cancelReengagementCount++;
  }

  @override
  Future<Set<String>> pendingTaskStartTaskIds() async => const {};

  @override
  Future<void> scheduleTaskStart({
    required String taskId,
    required DateTime startAt,
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> cancelTaskStart(String taskId) async {}
}

/// Double for [NotificationScheduler] covering the return-reminder surface.
///
/// Every scheduling call stores its arguments, permission requests are counted,
/// and [pendingTaskStarts] is the answer of [pendingTaskStartTaskIds], so a test
/// can simulate already-queued task-start notifications.
class FakeReengagementNotificationScheduler extends NotificationScheduler {
  /// Number of [cancelReengagementReminder] calls.
  int cancelReengagementCount = 0;

  /// Number of [requestNotificationPermissions] calls.
  int permissionRequestCount = 0;

  /// `firstAt` of the last [scheduleReengagementReminder] call.
  DateTime? scheduledReengagementAt;

  /// `title` of the last [scheduleReengagementReminder] call.
  String? scheduledReengagementTitle;

  /// `startAt` of every [scheduleTaskStart] call, keyed by task id.
  final Map<String, DateTime> scheduledTaskStarts = {};

  /// Task ids passed to [cancelTaskStart], in call order.
  final List<String> canceledTaskStarts = [];

  /// Answer of [pendingTaskStartTaskIds].
  Set<String> pendingTaskStarts = const {};

  @override
  Future<void> initialize() async {}

  @override
  Future<void> requestNotificationPermissions() async {
    permissionRequestCount++;
  }

  @override
  Future<void> scheduleReengagementReminder({
    required DateTime firstAt,
    required NotificationCopy copy,
  }) async {
    scheduledReengagementAt = firstAt;
    scheduledReengagementTitle = copy.returnMessageFor(firstAt).title;
  }

  @override
  Future<void> cancelReengagementReminder() async {
    cancelReengagementCount++;
  }

  @override
  Future<void> scheduleTaskStart({
    required String taskId,
    required DateTime startAt,
    required String title,
    required String body,
  }) async {
    scheduledTaskStarts[taskId] = startAt;
  }

  @override
  Future<void> cancelTaskStart(String taskId) async {
    canceledTaskStarts.add(taskId);
  }

  @override
  Future<Set<String>> pendingTaskStartTaskIds() async => pendingTaskStarts;
}
