import 'package:pomodoist/data/repositories/notifications/notification_repository.dart';
import 'package:pomodoist/data/services/notifications/notification_scheduler.dart';
import 'package:pomodoist/domain/models/notifications/notification_copy.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

const _reengagementReminderHour = 20;
const _reengagementReminderMinute = 30;

/// Wraps the platform scheduler and owns the notification policy that used to
/// live in composition: which task-start notifications are desired, when the
/// reengagement reminder fires, and which localized copy is used.
class LocalNotificationRepository implements NotificationRepository {
  LocalNotificationRepository(this._scheduler, this._copy);

  final NotificationScheduler _scheduler;
  final NotificationCopy Function() _copy;
  Future<void> _reengagementUpdate = Future<void>.value();
  int _reengagementRevision = 0;

  Future<void> _queueReengagementUpdate(Future<void> Function() update) {
    final previous = _reengagementUpdate;
    final revision = ++_reengagementRevision;
    final current = () async {
      try {
        await previous;
      } catch (_) {
        // A failed update must not prevent the next cancellation or refresh.
      }
      if (revision == _reengagementRevision) {
        await update();
      }
    }();
    _reengagementUpdate = current;
    return current;
  }

  @override
  Future<void> initialize() => _scheduler.initialize();

  @override
  Future<void> refreshLanguage() => _scheduler.refreshLanguage();

  @override
  Future<void> requestPermission() =>
      _scheduler.requestNotificationPermissions();

  @override
  Future<void> scheduleFocusIntervalEnd({
    required DateTime expectedEndAt,
    required String intervalType,
  }) {
    return _scheduler.scheduleFocusIntervalEnd(
      expectedEndAt: expectedEndAt,
      title: 'pomodoist',
      body: _scheduler.focusCompletedBody(intervalType),
    );
  }

  @override
  Future<void> cancelFocusIntervalEnd() => _scheduler.cancelFocusNotification();

  @override
  Future<void> syncTaskStartNotifications({
    required List<TaskItem> tasks,
    required DateTime now,
  }) async {
    final desired = <String, TaskItem>{};
    for (final task in tasks) {
      final schedule = task.schedule;
      if (task.isCompleted ||
          task.isDeleted ||
          schedule == null ||
          !schedule.isTimed ||
          !schedule.start!.toLocal().isAfter(now.toLocal())) {
        continue;
      }
      desired[task.id] = task;
    }

    final pending = await _scheduler.pendingTaskStartTaskIds();
    for (final taskId in pending.difference(desired.keys.toSet())) {
      await _scheduler.cancelTaskStart(taskId);
    }
    if (desired.isEmpty) {
      return;
    }

    await _scheduler.requestNotificationPermissions();
    final title = _copy().taskStarting;
    for (final task in desired.values) {
      await _scheduler.scheduleTaskStart(
        taskId: task.id,
        startAt: task.schedule!.start!,
        title: title,
        body: task.content,
      );
    }
  }

  @override
  Future<void> syncReengagementReminder({
    required bool enabled,
    required DateTime now,
    required bool hasProgressToday,
  }) => _queueReengagementUpdate(() async {
    if (!enabled) {
      await _scheduler.cancelReengagementReminder();
      return;
    }

    final copy = _copy();
    await _scheduler.requestNotificationPermissions();
    await _scheduler.scheduleReengagementReminder(
      firstAt: nextReengagementReminderAt(
        now: now,
        hasProgressToday: hasProgressToday,
      ),
      copy: copy,
    );
  });

  @override
  Future<void> cancelReengagementReminder() =>
      _queueReengagementUpdate(_scheduler.cancelReengagementReminder);
}

DateTime nextReengagementReminderAt({
  required DateTime now,
  required bool hasProgressToday,
}) {
  final local = now.toLocal();
  final todayReminder = DateTime(
    local.year,
    local.month,
    local.day,
    _reengagementReminderHour,
    _reengagementReminderMinute,
  );
  if (hasProgressToday || !local.isBefore(todayReminder)) {
    return DateTime(
      local.year,
      local.month,
      local.day + 1,
      _reengagementReminderHour,
      _reengagementReminderMinute,
    );
  }
  return todayReminder;
}
