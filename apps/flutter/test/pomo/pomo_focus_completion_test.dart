import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/data/services/notifications/notification_scheduler.dart';
import 'package:pomodoist/data/repositories/focus/focus_repository_impl.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/models/tasks/local_completion_event.dart';
import 'package:pomodoist/domain/models/pomo/pomo_focus.dart';

class Notifications extends NotificationScheduler {
  @override
  Future<void> initialize() async {}
  @override
  Future<void> cancelFocusNotification() async {}
  @override
  Future<void> scheduleFocusIntervalEnd({
    required DateTime expectedEndAt,
    required String title,
    required String body,
  }) async {}
}

void main() {
  for (final finish in ['complete', 'stop', 'skip']) {
    test('$finish does not count the open pause as work', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();
      final repo = DriftFocusRepository(
        db,
        DriftOutboxService(db),
        Notifications(),
      );
      final start = DateTime.utc(2026, 10, 18);
      final run = (await repo.startRun(
        const StartFocusRunInput(),
        now: start,
      )).getOrThrow();
      (await repo.pauseActiveInterval(
        now: start.add(const Duration(minutes: 1)),
      )).getOrThrow();
      final end = start.add(const Duration(minutes: 31));
      if (finish == 'complete') {
        (await repo.completeActiveInterval(now: end)).getOrThrow();
      }
      if (finish == 'stop') {
        (await repo.stopActiveRun(
          reason: StopFocusReason.stopped,
          now: end,
        )).getOrThrow();
      }
      if (finish == 'skip') {
        (await repo.skipActiveInterval(now: end)).getOrThrow();
      }
      final work = (await repo.watchIntervalsForRun(run).first)
          .where((i) => i.type == 'work')
          .toList();
      expect(pomoWorkSinceBreak(work, end), const Duration(minutes: 1));
    });
  }

  test(
    'only committed work completion emits; reading, ready and break do not',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();
      final events = <LocalCompletionEvent>[];
      final repo = DriftFocusRepository(
        db,
        DriftOutboxService(db),
        Notifications(),
        onIntervalCompleted: events.add,
      );
      final run = (await repo.startRun(
        const StartFocusRunInput(targetWorkIntervals: 1),
      )).getOrThrow();
      final active = await repo.watchActiveInterval().first;
      if (active?.status == 'ready') {
        (await repo.startReadyInterval()).getOrThrow();
      }
      (await repo.completeActiveInterval(
        now: DateTime.now().add(const Duration(hours: 2)),
      )).getOrThrow();
      expect(events, hasLength(1));
      expect(events.single.isTask, false);
      await repo.watchIntervalsForRun(run).first;
      expect(events, hasLength(1));
      (await repo.completeActiveInterval()).getOrThrow();
      expect(events, hasLength(1));
      (await repo.startReadyInterval()).getOrThrow();
      (await repo.completeActiveInterval(
        now: DateTime.now().add(const Duration(hours: 3)),
      )).getOrThrow();
      expect(events, hasLength(1));
    },
  );
}
