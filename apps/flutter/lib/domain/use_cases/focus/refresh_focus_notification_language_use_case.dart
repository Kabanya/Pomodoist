import 'package:pomodoist/data/repositories/focus/focus_repository.dart';
import 'package:pomodoist/data/repositories/notifications/notification_repository.dart';
import 'package:pomodoist/utils/timer_engine.dart';

/// Refreshes localized notification copy without placing Focus policy in DI.
final class RefreshFocusNotificationLanguageUseCase {
  const RefreshFocusNotificationLanguageUseCase({
    required FocusRepository focus,
    required NotificationRepository notifications,
    required DateTime Function() now,
  }) : _focus = focus,
       _notifications = notifications,
       _now = now;

  final FocusRepository _focus;
  final NotificationRepository _notifications;
  final DateTime Function() _now;

  Future<void> call() async {
    await _notifications.refreshLanguage();
    final interval = await _focus.watchActiveInterval().first;
    if (interval == null || interval.status != 'running') return;
    final end = calculateExpectedEndAt(
      startedAt: interval.startedAt,
      plannedSeconds: interval.plannedSeconds,
      pausedTotalSeconds: interval.pausedTotalSeconds,
    );
    if (!end.isAfter(_now())) return;
    await _notifications.scheduleFocusIntervalEnd(
      expectedEndAt: end,
      intervalType: interval.type,
    );
  }
}
