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
import 'package:pomodoist/domain/models/settings/app_language.dart';
import 'package:pomodoist/ui/core/localization/app_locale.dart';
import 'package:pomodoist/domain/models/tasks/task_time.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:pomodoist/ui/core/localization/notification_copy.dart';
import 'package:pomodoist/data/services/audio/focus_sound_player.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
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
import 'package:pomodoist/domain/use_cases/quick_add/quick_add_use_case.dart';
import 'package:pomodoist/data/services/planning/quick_add_hint.dart';
import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';
import 'package:pomodoist/data/repositories/achievements/achievement_repository_impl.dart';
import 'package:pomodoist/data/repositories/productivity/productivity_repository_impl.dart';
import 'package:pomodoist/domain/models/productivity/achievement_models.dart';
import 'package:pomodoist/domain/models/productivity/productivity_models.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';
import 'package:pomodoist/data/repositories/kanban/kanban_repository_impl.dart';
import 'package:pomodoist/data/services/local/kanban_transition_coordinator.dart';
import 'package:pomodoist/domain/use_cases/tasks/csv_task_import_use_case.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:uuid/uuid.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => unawaited(db.close()));
  return db;
});

final appStartupProvider = FutureProvider<void>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  await db.ensureSeedData();
  await ref
      .read(taskRepositoryProvider)
      .materializeDueRecurringTasks()
      .then((result) => result.getOrThrow());
  unawaited(
    _initializeNotificationsBestEffort(
      ref.watch(notificationSchedulerProvider),
    ),
  );
});

Future<void> _initializeNotificationsBestEffort(
  NotificationScheduler scheduler,
) async {
  try {
    await scheduler.initialize();
  } catch (_) {}
}

final currentUserProvider = StreamProvider<UserRow?>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.users)..limit(1)).watchSingleOrNull();
});

final Provider<NotificationScheduler> notificationSchedulerProvider =
    Provider<NotificationScheduler>((ref) {
      final scheduler = NotificationScheduler(
        localizations: () => lookupAppLocalizations(
          resolveAppLocale(ref.read(appLanguageProvider)),
        ).notificationCopy,
      );
      ref.listen(appLanguageProvider, (_, _) {
        Future<void> refresh() async {
          await scheduler.refreshLanguage();
          if (!ref.mounted) return;
          final interval = await ref
              .read(focusRepositoryProvider)
              .watchActiveInterval()
              .first;
          if (!ref.mounted ||
              interval == null ||
              interval.status != 'running') {
            return;
          }
          final end = calculateExpectedEndAt(
            startedAt: interval.startedAt,
            plannedSeconds: interval.plannedSeconds,
            pausedTotalSeconds: interval.pausedTotalSeconds,
          );
          if (!end.isAfter(DateTime.now())) return;
          await scheduler.scheduleFocusIntervalEnd(
            expectedEndAt: end,
            title: 'pomodoist',
            body: scheduler.focusCompletedBody(interval.type),
          );
        }

        unawaited(refresh().catchError((Object _) {}));
      });
      return scheduler;
    });

final focusSoundPlayerProvider = Provider<FocusSoundPlayer>((ref) {
  final player = AssetFocusSoundPlayer();
  ref.onDispose(() => unawaited(player.dispose()));
  return player;
});

const _reengagementReminderHour = 20;
const _reengagementReminderMinute = 30;

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

final quickAddHintControllerProvider =
    NotifierProvider<QuickAddHintController, QuickAddHintState>(
      QuickAddHintController.new,
    );

final quickAddHintTextProvider = Provider<String?>((ref) {
  final state = ref.watch(quickAddHintControllerProvider);
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

class QuickAddHintController extends Notifier<QuickAddHintState> {
  late final QuickAddHintCoordinator _coordinator;
  var _hasActiveEntitlement = false;
  late String _locale;

  @override
  QuickAddHintState build() {
    _hasActiveEntitlement = ref
        .read(billingViewModelProvider)
        .hasActiveEntitlement;
    ref.listen<BillingState>(billingViewModelProvider, (_, next) {
      _hasActiveEntitlement = next.hasActiveEntitlement;
    });
    _locale = activeQuickAddHintLocale(ref.read(appLanguageProvider));
    ref.listen<AppLanguage>(appLanguageProvider, (_, next) {
      _locale = activeQuickAddHintLocale(next);
    });
    _coordinator = QuickAddHintCoordinator(
      history: ref.read(quickAddHintHistoryProvider),
      store: ref.read(quickAddHintStoreProvider),
      generator: ref.read(quickAddHintGeneratorProvider),
      locale: () => _locale,
      hasActiveEntitlement: () => _hasActiveEntitlement,
      onStateChanged: (value) {
        if (ref.mounted) {
          state = value;
        }
      },
    );
    unawaited(_coordinator.initialize());
    return _coordinator.state;
  }

  Future<void> recordUserTaskCreated() {
    return _coordinator.recordUserTaskCreated();
  }
}

final syncQueueRepositoryProvider = Provider<OutboxService>((ref) {
  return DriftOutboxService(ref.watch(appDatabaseProvider));
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
  return DriftTaskRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(syncQueueRepositoryProvider),
    kanbanTransitions: ref.watch(kanbanTransitionCoordinatorProvider),
    onUserTaskCreated: () {
      unawaited(
        ref
            .read(quickAddHintControllerProvider.notifier)
            .recordUserTaskCreated(),
      );
    },
  );
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

final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  return DriftProjectRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(syncQueueRepositoryProvider),
  );
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
    () => ref.read(sharedPreferencesProvider.future),
  );
});

final achievementsProvider = StreamProvider<List<AchievementItem>>((ref) {
  return ref.watch(achievementRepositoryProvider).watchAchievements();
});

final quickAddServiceProvider = Provider<QuickAddUseCase>((ref) {
  return QuickAddUseCase(
    now: ref.watch(clockProvider).now,
    parser: ref.watch(quickAddParserProvider),
    taskRepository: ref.watch(taskRepositoryProvider),
    projectRepository: ref.watch(projectRepositoryProvider),
    focusPresetProvider: () => _selectedFocusPreset(ref),
  );
});

Future<FocusPresetItem?> _selectedFocusPreset(Ref ref) async {
  final selectedId = ref.read(lastFocusPresetIdProvider);
  final db = ref.read(appDatabaseProvider);
  final rows = await db.select(db.focusPresets).get();
  return selectedFocusPresetOrDefault([
    for (final row in rows)
      if (!row.isDeleted) _mapFocusPreset(row),
  ], selectedId);
}

FocusPresetItem _mapFocusPreset(FocusPresetRow row) => FocusPresetItem(
  id: row.id,
  userId: row.userId,
  name: row.name,
  workSeconds: row.workSeconds,
  shortBreakSeconds: row.shortBreakSeconds,
  longBreakSeconds: row.longBreakSeconds,
  intervalsBeforeLongBreak: row.intervalsBeforeLongBreak,
  autoStartBreaks: row.autoStartBreaks,
  autoStartWork: row.autoStartWork,
  allowPause: row.allowPause,
  strictMode: row.strictMode,
  isDefault: row.isDefault,
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
);

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
  unawaited(
    _syncTaskStartNotificationsBestEffort(
      tasks: tasks,
      now: ref.watch(clockProvider).now(),
      language: ref.watch(appLanguageProvider),
      scheduler: ref.watch(notificationSchedulerProvider),
    ),
  );
});

Future<void> _syncTaskStartNotificationsBestEffort({
  required List<TaskItem> tasks,
  required DateTime now,
  required AppLanguage language,
  required NotificationScheduler scheduler,
}) async {
  try {
    await syncTaskStartNotifications(
      tasks: tasks,
      now: now,
      language: language,
      scheduler: scheduler,
    );
  } catch (_) {}
}

Future<void> syncTaskStartNotifications({
  required List<TaskItem> tasks,
  required DateTime now,
  required AppLanguage language,
  required NotificationScheduler scheduler,
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

  final pending = await scheduler.pendingTaskStartTaskIds();
  for (final taskId in pending.difference(desired.keys.toSet())) {
    await scheduler.cancelTaskStart(taskId);
  }
  if (desired.isEmpty) {
    return;
  }

  await scheduler.requestNotificationPermissions();
  final copy = _taskStartNotificationCopy(language);
  for (final task in desired.values) {
    await scheduler.scheduleTaskStart(
      taskId: task.id,
      startAt: task.schedule!.start!,
      title: copy.title,
      body: task.content,
    );
  }
}

_TaskStartNotificationCopy _taskStartNotificationCopy(AppLanguage language) {
  return _TaskStartNotificationCopy(
    title: lookupAppLocalizations(
      resolveAppLocale(language),
    ).notificationTaskStarting,
  );
}

class _TaskStartNotificationCopy {
  const _TaskStartNotificationCopy({required this.title});

  final String title;
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
  if (interval.status == 'running' && remaining == Duration.zero) {
    unawaited(
      ref
          .read(focusRepositoryProvider)
          .completeActiveInterval()
          .then((result) => result.getOrThrow()),
    );
  }
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

  final scheduler = ref.watch(notificationSchedulerProvider);
  final clock = ref.watch(clockProvider);
  final language = ref.watch(appLanguageProvider);
  unawaited(
    syncReengagementReminder(
      enabled: enabled,
      summary: summary,
      now: clock.now(),
      language: language,
      scheduler: scheduler,
    ),
  );
});

Future<void> syncReengagementReminder({
  required bool enabled,
  required ProductivitySummary summary,
  required DateTime now,
  required AppLanguage language,
  required NotificationScheduler scheduler,
}) async {
  if (!enabled) {
    await scheduler.cancelReengagementReminder();
    return;
  }

  final copy = _reengagementNotificationCopy(language);
  await scheduler.requestNotificationPermissions();
  await scheduler.scheduleReengagementReminder(
    firstAt: nextReengagementReminderAt(
      now: now,
      hasProgressToday: summary.completedTasks > 0,
    ),
    title: copy.title,
    body: copy.body,
  );
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

_ReengagementNotificationCopy _reengagementNotificationCopy(
  AppLanguage language,
) {
  final l10n = lookupAppLocalizations(resolveAppLocale(language));
  return _ReengagementNotificationCopy(
    title: l10n.notificationReturnTitle,
    body: l10n.notificationReturnBody,
  );
}

class _ReengagementNotificationCopy {
  const _ReengagementNotificationCopy({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;
}

final pendingSyncCommandsProvider = StreamProvider<List<SyncCommandRow>>((ref) {
  return ref.watch(syncQueueRepositoryProvider).watchPending();
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
