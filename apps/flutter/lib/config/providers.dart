import 'package:pomodoist/data/repositories/planning/quick_add_hint_repository.dart';
import 'package:pomodoist/data/repositories/planning/quick_add_hint_repository_impl.dart';
import 'package:pomodoist/domain/models/planning/quick_add_hint.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/domain/models/calendar/calendar_models.dart';
import 'package:pomodoist/data/repositories/calendar/drift_calendar_integration_repository.dart';
import 'package:pomodoist/data/repositories/kanban/kanban_repository.dart';
import 'package:pomodoist/data/repositories/labels/label_repository.dart';
import 'package:pomodoist/data/repositories/projects/project_repository.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository.dart';
import 'package:pomodoist/data/repositories/focus/focus_repository.dart';
import 'package:pomodoist/data/repositories/achievements/achievement_repository.dart';
import 'package:pomodoist/data/repositories/productivity/productivity_repository.dart';
import 'package:pomodoist/data/repositories/projects/project_repository_impl.dart';
import 'package:pomodoist/data/repositories/labels/label_repository_impl.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pomodoist/config/app_language.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/domain/models/settings/app_language.dart';
import 'package:pomodoist/ui/core/localization/app_locale.dart';
import 'package:pomodoist/domain/models/tasks/task_time.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:pomodoist/ui/core/localization/notification_copy.dart';
import 'package:pomodoist/data/services/audio/focus_sound_player.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/repositories/notifications/local_notification_repository.dart';
import 'package:pomodoist/data/repositories/notifications/notification_repository.dart';
import 'package:pomodoist/data/services/notifications/notification_scheduler.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/config/clock_provider.dart';
export 'package:pomodoist/config/clock_provider.dart' show clockProvider;
import 'package:pomodoist/utils/timer_engine.dart';
import 'package:pomodoist/data/repositories/focus/focus_repository_impl.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/config/billing_dependencies.dart';
import 'package:pomodoist/data/repositories/calendar/google_calendar_repository.dart';
import 'package:pomodoist/data/repositories/local/local_transaction.dart';
import 'package:pomodoist/domain/use_cases/quick_add/quick_add_use_case.dart';
import 'package:pomodoist/domain/use_cases/tasks/edit_task_title_use_case.dart';
import 'package:pomodoist/domain/use_cases/focus/complete_expired_focus_interval_use_case.dart';
import 'package:pomodoist/domain/use_cases/focus/refresh_focus_notification_language_use_case.dart';
import 'package:pomodoist/data/services/planning/quick_add_hint.dart';
import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';
import 'package:pomodoist/data/repositories/achievements/achievement_repository_impl.dart';
import 'package:pomodoist/data/repositories/productivity/productivity_repository_impl.dart';
import 'package:pomodoist/domain/models/productivity/achievement_models.dart';
import 'package:pomodoist/domain/models/productivity/productivity_models.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';
import 'package:pomodoist/data/repositories/kanban/kanban_repository_impl.dart';
import 'package:pomodoist/data/repositories/local/kanban_transition_coordinator.dart';
import 'package:pomodoist/domain/use_cases/tasks/csv_task_import_use_case.dart';
import 'package:pomodoist/data/services/collaboration/collaboration_api.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:uuid/uuid.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => unawaited(db.close()));
  return db;
});

final appStartupProvider = FutureProvider<void>((ref) async {
  ref.watch(focusAutoCompletionCoordinatorProvider);
  final db = ref.watch(appDatabaseProvider);
  await db.ensureSeedData();
  await ref
      .read(taskRepositoryProvider)
      .materializeDueRecurringTasks()
      .then((result) => result.getOrThrow());
  unawaited(
    _initializeNotificationsBestEffort(
      ref.watch(notificationRepositoryProvider),
    ),
  );
});

Future<void> _initializeNotificationsBestEffort(
  NotificationRepository notifications,
) async {
  try {
    await notifications.initialize();
  } catch (_) {}
}

final Provider<NotificationScheduler> notificationSchedulerProvider =
    Provider<NotificationScheduler>((ref) {
      return NotificationScheduler(
        localizations: () => lookupAppLocalizations(
          resolveAppLocale(ref.read(appLanguageProvider)),
        ).notificationCopy,
      );
    });

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  final notifications = LocalNotificationRepository(
    ref.watch(notificationSchedulerProvider),
    () => lookupAppLocalizations(
      resolveAppLocale(ref.read(appLanguageProvider)),
    ).notificationCopy,
  );
  ref.listen(appLanguageProvider, (_, _) {
    unawaited(
      RefreshFocusNotificationLanguageUseCase(
        focus: ref.read(focusRepositoryProvider),
        notifications: notifications,
        now: ref.read(clockProvider).now,
      ).call().catchError((Object _) {}),
    );
  });
  return notifications;
});

final focusSoundPlayerProvider = Provider<FocusSoundPlayer>((ref) {
  final player = AssetFocusSoundPlayer();
  ref.onDispose(() => unawaited(player.dispose()));
  return player;
});

final quickAddParserProvider = Provider<QuickAddParser>(
  (ref) => QuickAddParser(
    defaultTimedBlockDuration: Duration(
      minutes: ref.watch(quickAddDefaultTimedBlockMinutesProvider),
    ),
  ),
);

const _deepSeekApiKey = String.fromEnvironment('DEEPSEEK_API_KEY');

final quickAddHintGeneratorProvider = Provider<QuickAddHintGenerator>((ref) {
  return DeepSeekQuickAddHintGenerator(apiKey: _deepSeekApiKey);
});

final quickAddHintHistoryProvider = Provider<QuickAddHintHistory>((ref) {
  return DriftQuickAddHintHistory(ref.watch(appDatabaseProvider));
});

final quickAddHintStoreProvider = Provider<QuickAddHintStore>((ref) {
  final preferences = ref.read(sharedPreferencesProvider.future);
  return SharedPreferencesQuickAddHintStore(() => preferences);
});

final quickAddHintRepositoryProvider = Provider<QuickAddHintRepository>((ref) {
  final repository = StoredQuickAddHintRepository(
    history: ref.watch(quickAddHintHistoryProvider),
    store: ref.watch(quickAddHintStoreProvider),
    generator: ref.watch(quickAddHintGeneratorProvider),
    locale: () => activeQuickAddHintLocale(ref.read(appLanguageProvider)),
    hasActiveEntitlement: () =>
        ref.read(billingRepositoryProvider).currentAccess.hasActiveEntitlement,
  );
  ref.onDispose(repository.dispose);
  unawaited(repository.initialize());
  return repository;
});

final quickAddHintStateProvider = Provider<QuickAddHintState>((ref) {
  final repository = ref.watch(quickAddHintRepositoryProvider);
  final subscription = repository.watch().listen((_) => ref.invalidateSelf());
  ref.onDispose(subscription.cancel);
  return repository.state;
});

final quickAddHintTextProvider = Provider<String?>((ref) {
  final state = ref.watch(quickAddHintStateProvider);
  final language = ref.watch(appLanguageProvider);
  final hint = state.hintForLocale(activeQuickAddHintLocale(language));
  if (hint != null) {
    return hint;
  }
  return state.starterConsumed
      ? quickAddHintEmptyFor(language)
      : quickAddHintFallbackFor(language);
});

final effectiveQuickAddHintProvider = Provider<String>((ref) {
  return ref.watch(quickAddHintTextProvider) ??
      quickAddHintFallbackFor(ref.watch(appLanguageProvider));
});

String activeQuickAddHintLocale(AppLanguage language) =>
    resolveAppLocale(language).toLanguageTag();

String quickAddHintFallbackFor(AppLanguage language) =>
    lookupAppLocalizations(resolveAppLocale(language)).quickAddHint;

String quickAddHintEmptyFor(AppLanguage language) =>
    lookupAppLocalizations(resolveAppLocale(language)).addTask;

final syncQueueRepositoryProvider = Provider<OutboxService>((ref) {
  return DriftOutboxService(ref.watch(appDatabaseProvider));
});

/// Carries the collaboration API so that deleting a shared root can go through
/// the server scope operation instead of a content command the server rejects.
final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  final account = ref.watch(accountClientProvider);
  return DriftProjectRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(syncQueueRepositoryProvider),
    collaboration: account == null
        ? null
        : CollaborationApi.account(account),
    synchronize: () async {
      await ref.read(accountSyncEngineProvider)?.syncNow();
    },
  );
});

final csvTaskImporterProvider = Provider<CsvTaskImportUseCase>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return CsvTaskImportUseCase(
    projects: ref.watch(projectRepositoryProvider),
    labels: ref.watch(labelRepositoryProvider),
    kanban: ref.watch(kanbanRepositoryProvider),
    tasks: ref.watch(taskRepositoryProvider),
    runAtomically: db.transaction,
    ensureSeedData: db.ensureSeedData,
    newId: const Uuid().v4,
  );
});

final kanbanTransitionCoordinatorProvider =
    Provider<KanbanTransitionCoordinator>((ref) {
      return KanbanTransitionCoordinator(
        ref.watch(appDatabaseProvider),
        ref.watch(syncQueueRepositoryProvider),
      );
    });

final driftTaskRepositoryProvider = Provider<DriftTaskRepository>((ref) {
  final repository = DriftTaskRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(syncQueueRepositoryProvider),
    kanbanTransitions: ref.watch(kanbanTransitionCoordinatorProvider),
  );
  return repository;
});

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return ref.watch(driftTaskRepositoryProvider);
});

final kanbanRepositoryProvider = Provider<KanbanRepository>((ref) {
  return DriftKanbanRepository(
    ref.watch(appDatabaseProvider),
    syncQueue: ref.watch(syncQueueRepositoryProvider),
    kanbanTransitions: ref.watch(kanbanTransitionCoordinatorProvider),
  );
});

final kanbanBoardProvider = StreamProvider<KanbanBoardSnapshot>((ref) {
  return ref.watch(kanbanRepositoryProvider).watchBoard();
});

final labelRepositoryProvider = Provider<LabelRepository>((ref) {
  return DriftLabelRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(syncQueueRepositoryProvider),
  );
});

final focusRepositoryProvider = Provider<FocusRepository>((ref) {
  ref.read(focusCompletionCelebrationEnabledProvider);
  return DriftFocusRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(syncQueueRepositoryProvider),
    ref.watch(notificationSchedulerProvider),
    soundPlayer: ref.watch(focusSoundPlayerProvider),
    kanbanTransitions: ref.watch(kanbanTransitionCoordinatorProvider),
    onRunCompleted: (event) {
      if (ref.read(focusCompletionCelebrationEnabledProvider)) {
        ref.read(focusCompletionRepositoryProvider).present(event);
      }
    },
  );
});

final focusPresetsProvider = StreamProvider<List<FocusPresetItem>>((ref) {
  return ref.watch(focusRepositoryProvider).watchPresets();
});

final productivityRepositoryProvider = Provider<ProductivityRepository>((ref) {
  return DriftProductivityRepository(ref.watch(appDatabaseProvider));
});

final achievementRepositoryProvider = Provider<AchievementRepository>((ref) {
  return DriftAchievementRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(preferencesServiceProvider),
  );
});

final achievementsProvider = StreamProvider<List<AchievementItem>>((ref) {
  return ref.watch(achievementRepositoryProvider).watchAchievements();
});

final quickAddUseCaseProvider = Provider<QuickAddUseCase>((ref) {
  return QuickAddUseCase(
    now: ref.watch(clockProvider).now,
    parser: ref.watch(quickAddParserProvider),
    taskRepository: ref.watch(taskRepositoryProvider),
    projectRepository: ref.watch(projectRepositoryProvider),
    focusRepository: ref.watch(focusRepositoryProvider),
    selectedFocusPresetId: () => ref.read(lastFocusPresetIdProvider),
    hints: ref.watch(quickAddHintRepositoryProvider),
  );
});

final editTaskTitleUseCaseProvider = Provider<EditTaskTitleUseCase>((ref) {
  return EditTaskTitleUseCase(
    parser: ref.watch(quickAddParserProvider),
    taskRepository: ref.watch(taskRepositoryProvider),
    projectRepository: ref.watch(projectRepositoryProvider),
  );
});

final localTransactionProvider = Provider<RunLocalTransaction>((ref) {
  return ref.watch(appDatabaseProvider).transaction;
});

final tasksByQueryProvider = StreamProvider.family<List<TaskItem>, TaskQuery>((
  ref,
  query,
) {
  return ref.watch(taskRepositoryProvider).watchTasks(query);
});

final taskProvider = StreamProvider.family<TaskItem?, String>((ref, id) {
  return ref.watch(taskRepositoryProvider).watchTask(id);
});

final recurringTaskMaterializationProvider = Provider<void>((ref) {
  Future<void> run() async {
    try {
      await ref
          .read(taskRepositoryProvider)
          .materializeDueRecurringTasks()
          .then((result) => result.getOrThrow());
    } catch (_) {}
  }

  unawaited(run());
  final timer = Timer.periodic(
    const Duration(minutes: 1),
    (_) => unawaited(run()),
  );
  ref.onDispose(timer.cancel);
});

final taskStartNotificationCoordinatorProvider = Provider<void>((ref) {
  final tasks = ref.watch(tasksByQueryProvider(const TaskQuery.all())).value;
  if (tasks == null) {
    return;
  }
  // Rebuild on language change so rescheduled notifications use new copy.
  ref.watch(appLanguageProvider);
  unawaited(
    _syncTaskStartNotificationsBestEffort(
      tasks: tasks,
      now: ref.watch(clockProvider).now(),
      notifications: ref.watch(notificationRepositoryProvider),
    ),
  );
});

Future<void> _syncTaskStartNotificationsBestEffort({
  required List<TaskItem> tasks,
  required DateTime now,
  required NotificationRepository notifications,
}) async {
  try {
    await notifications.syncTaskStartNotifications(tasks: tasks, now: now);
  } catch (_) {}
}

final projectsProvider = StreamProvider<List<ProjectItem>>((ref) {
  return ref.watch(projectRepositoryProvider).watchProjects();
});

final labelsProvider = StreamProvider<List<LabelItem>>((ref) {
  return ref.watch(labelRepositoryProvider).watchLabels();
});

final activeFocusRunProvider = StreamProvider<FocusRunItem?>((ref) {
  return ref.watch(focusRepositoryProvider).watchActiveRun();
});

final activeFocusIntervalProvider = StreamProvider<FocusIntervalItem?>((ref) {
  return ref.watch(focusRepositoryProvider).watchActiveInterval();
});

// Only replace the global player after both streams describe the same session.
final todayFocusStripVisibleProvider = Provider<bool>((ref) {
  final runId = ref.watch(
    activeFocusRunProvider.select((value) => value.value?.id),
  );
  final intervalRunId = ref.watch(
    activeFocusIntervalProvider.select((value) => value.value?.runId),
  );
  final hasRemaining = ref.watch(
    activeFocusRemainingProvider.select((value) => value != null),
  );
  return runId != null && runId == intervalRunId && hasRemaining;
});

final focusIntervalsForRunProvider =
    StreamProvider.family<List<FocusIntervalItem>, String>((ref, runId) {
      return ref.watch(focusRepositoryProvider).watchIntervalsForRun(runId);
    });

final focusTickerProvider = StreamProvider<DateTime>((ref) {
  final clock = ref.watch(clockProvider);
  late final StreamController<DateTime> controller;
  Timer? timer;
  controller = StreamController<DateTime>(
    onListen: () {
      controller.add(clock.now());
      timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => controller.add(clock.now()),
      );
    },
    onCancel: () => timer?.cancel(),
  );
  ref.onDispose(() {
    timer?.cancel();
    unawaited(controller.close());
  });
  return controller.stream;
});

final taskTimeTickerProvider = focusTickerProvider;

final completeExpiredFocusIntervalUseCaseProvider =
    Provider<CompleteExpiredFocusIntervalUseCase>(
      (ref) => CompleteExpiredFocusIntervalUseCase(
        ref.watch(focusRepositoryProvider),
      ),
    );

final focusAutoCompletionCoordinatorProvider = Provider<void>((ref) {
  ref.listen(focusTickerProvider, (_, tick) {
    final now = tick.value;
    if (now == null) return;
    unawaited(
      ref
          .read(completeExpiredFocusIntervalUseCaseProvider)
          .call(ref.read(activeFocusIntervalProvider).value, now)
          .catchError((Object _) {}),
    );
  }, fireImmediately: true);
});

final overdueTasksProvider = Provider.autoDispose<AsyncValue<List<TaskItem>>>((
  ref,
) {
  final tasks = ref.watch(tasksByQueryProvider(const TaskQuery.all()));
  final now =
      ref.watch(taskTimeTickerProvider).value ?? ref.read(clockProvider).now();
  return tasks.whenData(
    (items) => items.where((task) => isTaskOverdue(task, now)).toList(),
  );
});

final taskTimeStateProvider = Provider.autoDispose
    .family<TaskTimeState?, TaskItem>((ref, task) {
      final schedule = task.schedule;
      if (schedule == null || task.isCompleted) {
        return task.isCompleted && schedule?.isTimed == true
            ? TaskTimeState.completed
            : null;
      }

      final clock = ref.read(clockProvider);
      if (schedule.isAllDay) {
        final localNow = clock.now().toLocal();
        final today = DateTime(localNow.year, localNow.month, localNow.day);
        return schedule.date!.isBefore(today) ? TaskTimeState.overdue : null;
      }

      final activeFocusTaskId = ref.watch(
        activeFocusRunProvider.select((run) => run.value?.taskId),
      );
      return ref.watch(
        taskTimeTickerProvider.select(
          (ticker) => taskTimeStateForTask(
            task: task,
            now: ticker.value ?? clock.now(),
            activeFocusTaskId: activeFocusTaskId,
          ),
        ),
      );
    });

final activeFocusRemainingProvider = Provider<Duration?>((ref) {
  final interval = ref.watch(activeFocusIntervalProvider).value;
  if (interval == null) {
    return null;
  }
  if (interval.status == 'ready') {
    return Duration(seconds: interval.plannedSeconds);
  }
  final now = ref.watch(focusTickerProvider).value;
  if (now == null) {
    return null;
  }
  final remaining = calculateRemaining(
    now: now,
    startedAt: interval.startedAt,
    plannedSeconds: interval.plannedSeconds,
    pausedTotalSeconds: interval.pausedTotalSeconds,
    pausedAt: interval.pausedAt,
  );
  return remaining;
});

final productivitySummaryProvider = StreamProvider<ProductivitySummary>((ref) {
  final clock = ref.watch(clockProvider);
  // Refresh the daily stream at midnight even when no database row changes.
  ref.watch(
    focusTickerProvider.select((tick) {
      final now = (tick.value ?? clock.now()).toLocal();
      return DateTime(now.year, now.month, now.day);
    }),
  );
  return ref.watch(productivityRepositoryProvider).watchTodaySummary();
});

final reengagementNotificationCoordinatorProvider = Provider<void>((ref) {
  final enabled = ref.watch(reengagementNotificationsEnabledProvider);
  final summary = ref.watch(productivitySummaryProvider).value;
  if (summary == null) {
    return;
  }
  // Rebuild on language change so the reminder is rescheduled with new copy.
  ref.watch(appLanguageProvider);

  final notifications = ref.watch(notificationRepositoryProvider);
  final clock = ref.watch(clockProvider);
  unawaited(
    notifications.syncReengagementReminder(
      enabled: enabled,
      now: clock.now(),
      hasProgressToday: summary.completedTasks > 0,
    ),
  );
});

final pendingSyncCommandCountProvider = StreamProvider<int>((ref) {
  return ref
      .watch(syncQueueRepositoryProvider)
      .watchPending()
      .map((commands) => commands.length);
});

final calendarIntegrationRepositoryProvider =
    Provider<CalendarIntegrationRepository>((ref) {
      return DriftCalendarIntegrationRepository(ref.watch(appDatabaseProvider));
    });

final googleCalendarConnectionProvider =
    StreamProvider<GoogleCalendarConnection?>((ref) {
      return ref.watch(calendarIntegrationRepositoryProvider).watchConnection();
    });

final googleCalendarLinkProvider =
    StreamProvider.family<GoogleCalendarEventLink?, String>((ref, taskId) {
      return ref
          .watch(calendarIntegrationRepositoryProvider)
          .watchLinkForTask(taskId);
    });
