import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/focus/focus_repository_impl.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/data/services/notifications/notification_scheduler.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'adjustment preserves time and pause, and only changes this interval',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final notifications = _Notifications();
      final repository = DriftFocusRepository(
        db,
        DriftOutboxService(db),
        notifications,
      );
      final start = DateTime.utc(2026, 11, 3, 10);
      await db.ensureSeedData();
      (await repository.startRun(
        const StartFocusRunInput(),
        now: start,
      )).getOrThrow();
      Future<FocusIntervalItem> current() async =>
          (await repository.watchActiveInterval().first)!;
      final original = await current();

      (await repository.adjustActiveIntervalDuration(
        original.id,
        300,
        now: start.add(const Duration(minutes: 1)),
      )).getOrThrow();
      expect((await current()).plannedSeconds, original.plannedSeconds + 300);
      expect((await current()).startedAt, original.startedAt);
      expect(
        notifications.deadline?.toUtc(),
        start.add(const Duration(minutes: 30)),
      );

      (await repository.completeActiveInterval(
        now: start.add(const Duration(minutes: 25)),
        expiredIntervalId: original.id,
      )).getOrThrow();
      expect((await current()).id, original.id);

      final pause = start.add(const Duration(minutes: 3));
      (await repository.pauseActiveInterval(now: pause)).getOrThrow();
      (await repository.adjustActiveIntervalDuration(
        original.id,
        -300,
        now: start.add(const Duration(minutes: 31)),
      )).getOrThrow();
      expect((await current()).plannedSeconds, original.plannedSeconds);
      expect((await current()).pausedAt?.toUtc(), pause);
      expect((await current()).status, 'paused');
      expect(notifications.deadline, isNull);

      final resume = start.add(const Duration(minutes: 32));
      (await repository.resumeActiveInterval(now: resume)).getOrThrow();
      expect(
        notifications.deadline?.toUtc(),
        resume.add(const Duration(minutes: 22)),
      );
      await expectLater(
        () async => (await repository.adjustActiveIntervalDuration(
          original.id,
          -300,
          now: resume.add(const Duration(minutes: 18)),
        )).getOrThrow(),
        throwsStateError,
      );
      (await repository.completeActiveInterval(now: resume)).getOrThrow();
      final next = await current();
      expect(next.id, isNot(original.id));
      expect(next.plannedSeconds, 300);
      await expectLater(
        () async => (await repository.adjustActiveIntervalDuration(
          original.id,
          300,
          now: resume,
        )).getOrThrow(),
        throwsStateError,
      );
      expect((await current()).plannedSeconds, 300);
    },
  );
}

class _Notifications extends NotificationScheduler {
  DateTime? deadline;

  @override
  Future<void> cancelFocusNotification() async => deadline = null;

  @override
  Future<void> scheduleFocusIntervalEnd({
    required DateTime expectedEndAt,
    required String title,
    required String body,
  }) async => deadline = expectedEndAt;
}
