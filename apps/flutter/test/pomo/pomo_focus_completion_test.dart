import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/config/pomo_dependencies.dart' as composition;
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/focus/focus_preferences_repository_impl.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/data/services/notifications/notification_scheduler.dart';
import 'package:pomodoist/data/repositories/focus/focus_repository_impl.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/models/tasks/local_completion_event.dart';
import 'package:pomodoist/ui/pomo/view_models/pomo_controller.dart';
import 'package:pomodoist/routing/router.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Pomo focus commands', () {
    late AppDatabase db;
    late DriftFocusRepository repo;
    late StoredFocusPreferencesRepository preferences;
    late ProviderContainer container;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.ensureSeedData();
      repo = DriftFocusRepository(db, DriftOutboxService(db), Notifications());
      preferences = StoredFocusPreferencesRepository(
        PreferencesService(() async => null),
      );
      container = ProviderContainer(
        overrides: [
          ...composition.pomoOverrides,
          appDatabaseProvider.overrideWithValue(db),
          focusRepositoryProvider.overrideWithValue(repo),
          focusPreferencesRepositoryProvider.overrideWithValue(preferences),
          routerProvider.overrideWith(
            (_) => throw StateError(
              'Starting Focus must not open the main window',
            ),
          ),
        ],
      );
      container.listen(pomoFocusProvider, (_, _) {});
    });

    tearDown(() async {
      container.dispose();
      preferences.dispose();
      await db.close();
    });

    test(
      'idle play starts a running session with the selected preset',
      () async {
        final selected = (await repo.createPreset(
          const CreateFocusPresetInput(
            name: 'Short focus',
            workSeconds: 600,
            shortBreakSeconds: 120,
            longBreakSeconds: 300,
            intervalsBeforeLongBreak: 2,
          ),
        )).getOrThrow();
        (await preferences.setPresetId(selected)).getOrThrow();
        await container.read(activeFocusRunProvider.future);

        await container.read(pomoActionsProvider).toggleFocus();

        final run = await repo.watchActiveRun().first;
        final interval = await repo.watchActiveInterval().first;
        expect(run?.presetId, selected);
        expect(run?.taskId, isNull);
        expect(interval?.status, 'running');
        expect(interval?.plannedSeconds, 600);
      },
    );

    test(
      'play waits for an existing session and toggles without replacing it',
      () async {
        final runId = (await repo.startRun(
          const StartFocusRunInput(),
        )).getOrThrow();

        await container.read(pomoActionsProvider).toggleFocus();
        expect((await repo.watchActiveRun().first)?.id, runId);
        expect((await repo.watchActiveInterval().first)?.status, 'paused');

        await container.pump();
        await container.read(pomoActionsProvider).toggleFocus();
        expect((await repo.watchActiveRun().first)?.id, runId);
        expect((await repo.watchActiveInterval().first)?.status, 'running');
      },
    );

    for (final selected in [null, 'deleted-preset']) {
      test(
        'idle play falls back to the default for selection $selected',
        () async {
          (await preferences.setPresetId(selected)).getOrThrow();
          final preset = (await repo.watchPresets().first).firstWhere(
            (p) => p.isDefault,
          );

          await container.read(pomoActionsProvider).toggleFocus();

          expect((await repo.watchActiveRun().first)?.presetId, preset.id);
          expect((await repo.watchActiveInterval().first)?.status, 'running');
        },
      );
    }

    test('play starts a ready interval in the same session', () async {
      final runId = (await repo.startRun(
        const StartFocusRunInput(),
      )).getOrThrow();
      (await repo.completeActiveInterval(
        now: DateTime.now().add(const Duration(hours: 1)),
      )).getOrThrow();
      expect((await repo.watchActiveInterval().first)?.status, 'ready');

      await container.read(pomoActionsProvider).toggleFocus();

      expect((await repo.watchActiveRun().first)?.id, runId);
      expect((await repo.watchActiveInterval().first)?.status, 'running');
    });
  });

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
          .single;
      expect(work.pausedTotalSeconds, 1800);
      expect((work.completedAt ?? work.stoppedAt)?.toUtc(), end);
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
