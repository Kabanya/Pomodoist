import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/core/audio/focus_sound_player.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/core/notifications/notification_scheduler.dart';
import 'package:pomodoist/core/sync/sync_queue_repository.dart';
import 'package:pomodoist/features/focus/domain/focus_models.dart';
import 'package:pomodoist/features/focus/presentation/focus_completion_celebration_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  test('a completed run is presented at most once', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(
      focusRunCompletionControllerProvider.notifier,
    );
    final first = _completion(runId: 'run-1', completedWorkIntervals: 4);
    final duplicate = _completion(runId: 'run-1', completedWorkIntervals: 99);

    controller.present(first);
    controller.present(duplicate);

    expect(container.read(focusRunCompletionControllerProvider), same(first));

    controller.dismiss();
    controller.present(duplicate);

    expect(container.read(focusRunCompletionControllerProvider), isNull);
  });

  test(
    'focus repository provider forwards completed runs to controller',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.ensureSeedData();
      addTearDown(db.close);
      final syncQueue = DriftSyncQueueRepository(db);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncQueueRepositoryProvider.overrideWithValue(syncQueue),
          notificationSchedulerProvider.overrideWithValue(
            _NoopNotificationScheduler(),
          ),
          focusSoundPlayerProvider.overrideWithValue(_NoopFocusSoundPlayer()),
        ],
      );
      addTearDown(container.dispose);
      final repository = container.read(focusRepositoryProvider);
      final runId = await repository.startRun(
        const StartFocusRunInput(targetWorkIntervals: 1),
      );
      await repository.completeActiveInterval();
      await repository.startReadyInterval();

      await repository.completeActiveInterval();

      expect(
        container.read(focusRunCompletionControllerProvider)?.runId,
        runId,
      );
    },
  );

  test('disabled celebration ignores completed repository runs', () async {
    SharedPreferences.setMockInitialValues({
      'focus.completionCelebration.enabled': false,
    });
    final db = AppDatabase(NativeDatabase.memory());
    await db.ensureSeedData();
    addTearDown(db.close);
    final syncQueue = DriftSyncQueueRepository(db);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        syncQueueRepositoryProvider.overrideWithValue(syncQueue),
        notificationSchedulerProvider.overrideWithValue(
          _NoopNotificationScheduler(),
        ),
        focusSoundPlayerProvider.overrideWithValue(_NoopFocusSoundPlayer()),
      ],
    );
    addTearDown(container.dispose);
    final repository = container.read(focusRepositoryProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await repository.startRun(const StartFocusRunInput(targetWorkIntervals: 1));
    await repository.completeActiveInterval();
    await repository.startReadyInterval();

    await repository.completeActiveInterval();

    expect(container.read(focusRunCompletionControllerProvider), isNull);
  });
}

FocusRunCompletionEvent _completion({
  required String runId,
  required int completedWorkIntervals,
}) {
  return FocusRunCompletionEvent(
    runId: runId,
    taskId: 'task-1',
    taskTitle: 'Ship celebration',
    completedWorkIntervals: completedWorkIntervals,
    targetWorkIntervals: 4,
    completedAt: DateTime.utc(2026, 8, 19, 12),
  );
}

class _NoopNotificationScheduler extends NotificationScheduler {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> scheduleFocusIntervalEnd({
    required DateTime expectedEndAt,
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> cancelFocusNotification() async {}
}

class _NoopFocusSoundPlayer implements FocusSoundPlayer {
  @override
  Future<void> play(FocusSoundCue cue) async {}

  @override
  Future<void> dispose() async {}
}
