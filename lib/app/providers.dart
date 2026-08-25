import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_language.dart';
import 'task_time.dart';
import '../l10n/app_localizations.dart';
import '../core/audio/focus_sound_player.dart';
import '../core/db/app_database.dart';
import '../core/notifications/notification_scheduler.dart';
import '../core/sync/device_identity.dart';
import '../core/sync/sync_queue_repository.dart';
import '../core/time/clock.dart';
import '../core/time/timer_engine.dart';
import '../features/focus/data/focus_repository_impl.dart';
import '../features/focus/domain/focus_models.dart';
import '../features/focus/presentation/focus_completion_celebration_controller.dart';
import '../features/focus/presentation/focus_view_mode.dart';
import '../features/billing/billing.dart';
import '../features/integrations/google_calendar/data/auth/google_calendar_auth_service.dart';
import '../features/integrations/google_calendar/data/google_calendar_api_client.dart';
import '../features/integrations/google_calendar/data/google_calendar_repository.dart';
import '../features/integrations/google_calendar/data/google_calendar_sync_controller.dart';
import '../features/integrations/google_calendar/data/google_calendar_sync_lifecycle.dart';
import '../features/planning/data/quick_add_service.dart';
import '../features/planning/data/quick_add_hint.dart';
import '../features/planning/domain/quick_add_parser.dart';
import '../features/productivity/data/achievement_repository_impl.dart';
import '../features/productivity/data/productivity_repository_impl.dart';
import '../features/productivity/domain/achievement_models.dart';
import '../features/productivity/domain/productivity_models.dart';
import '../features/productivity/presentation/achievement_announcement_controller.dart';
import '../features/tasks/data/task_repository_impl.dart';
import '../features/tasks/data/kanban_repository_impl.dart';
import '../features/tasks/data/kanban_transition_coordinator.dart';
import '../features/tasks/data/csv_task_import.dart';
import '../features/tasks/domain/task_models.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => unawaited(db.close()));
  return db;
});

final appStartupProvider = FutureProvider<void>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  await db.ensureSeedData();
  await ref.read(taskRepositoryProvider).materializeDueRecurringTasks();
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

final clockProvider = Provider<Clock>((ref) => const SystemClock());

final notificationSchedulerProvider = Provider<NotificationScheduler>(
  (ref) => NotificationScheduler(),
);

final focusSoundPlayerProvider = Provider<FocusSoundPlayer>((ref) {
  final player = AssetFocusSoundPlayer();
  ref.onDispose(() => unawaited(player.dispose()));
  return player;
});

const reengagementNotificationsEnabledPreferenceKey =
    'notifications.reengagement.enabled';
const quickAddDefaultTimedBlockMinutesPreferenceKey =
    'quickAdd.defaultTimedBlockMinutes';
const taskTimeDisplayModePreferenceKey = 'tasks.timeDisplayMode';
const timelineVisibleStartMinutesPreferenceKey = 'timeline.visibleStartMinutes';
const timelineVisibleEndMinutesPreferenceKey = 'timeline.visibleEndMinutes';
const timelineHourWidthPreferenceKey = 'timeline.hourWidth';
const timelineCollapsedProjectIdsPreferenceKey = 'timeline.collapsedProjectIds';
const defaultQuickAddTimedBlockMinutes = 30;
const minQuickAddTimedBlockMinutes = 1;
const maxQuickAddTimedBlockMinutes = 480;
const timelineSnapMinutes = 15;
const defaultTimelineVisibleStartMinutes = 0;
const defaultTimelineVisibleEndMinutes = 24 * 60;
const defaultTimelineHourWidth = 192;
const timelineHourWidthLevels = <int>[96, 144, 192, 288, 384];
const _reengagementReminderHour = 20;
const _reengagementReminderMinute = 30;

final reengagementNotificationsEnabledProvider =
    NotifierProvider<ReengagementNotificationsEnabledController, bool>(
      ReengagementNotificationsEnabledController.new,
    );

final quickAddDefaultTimedBlockMinutesProvider =
    NotifierProvider<QuickAddDefaultTimedBlockMinutesController, int>(
      QuickAddDefaultTimedBlockMinutesController.new,
    );

final taskTimeDisplayModeProvider =
    NotifierProvider<TaskTimeDisplayModeController, TaskTimeDisplayMode>(
      TaskTimeDisplayModeController.new,
    );

final timelineVisibleHoursProvider =
    NotifierProvider<TimelineVisibleHoursController, TimelineVisibleHours>(
      TimelineVisibleHoursController.new,
    );

final timelineHourWidthProvider =
    NotifierProvider<TimelineHourWidthController, int>(
      TimelineHourWidthController.new,
    );

final timelineCollapsedProjectIdsProvider =
    NotifierProvider<TimelineCollapsedProjectIdsController, Set<String>>(
      TimelineCollapsedProjectIdsController.new,
    );

final timelineTemporarilyVisibleProjectIdsProvider =
    NotifierProvider<TimelineTemporaryProjectIdsController, Set<String>>(
      TimelineTemporaryProjectIdsController.new,
    );

final quickAddParserProvider = Provider<QuickAddParser>((ref) {
  return QuickAddParser(
    defaultTimedBlockDuration: Duration(
      minutes: ref.watch(quickAddDefaultTimedBlockMinutesProvider),
    ),
  );
});

class ReengagementNotificationsEnabledController extends Notifier<bool> {
  bool _loaded = false;
  bool _hasLocalSelection = false;

  @override
  bool build() {
    if (!_loaded) {
      _loaded = true;
      unawaited(_loadStoredValue());
    }
    return true;
  }

  Future<void> setEnabled(bool enabled) async {
    _hasLocalSelection = true;
    state = enabled;
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs?.setBool(
      reengagementNotificationsEnabledPreferenceKey,
      enabled,
    );
    if (!enabled) {
      await ref
          .read(notificationSchedulerProvider)
          .cancelReengagementReminder();
    }
  }

  Future<void> _loadStoredValue() async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    final stored =
        prefs?.getBool(reengagementNotificationsEnabledPreferenceKey) ?? true;
    if (!ref.mounted || _hasLocalSelection) {
      return;
    }
    state = stored;
    if (!stored) {
      await ref
          .read(notificationSchedulerProvider)
          .cancelReengagementReminder();
    }
  }
}

class QuickAddDefaultTimedBlockMinutesController extends Notifier<int> {
  bool _loaded = false;
  bool _hasLocalSelection = false;

  @override
  int build() {
    if (!_loaded) {
      _loaded = true;
      unawaited(_loadStoredValue());
    }
    return defaultQuickAddTimedBlockMinutes;
  }

  Future<void> setMinutes(int minutes) async {
    final normalized = _validMinutes(minutes);
    if (normalized == null) {
      return;
    }
    _hasLocalSelection = true;
    state = normalized;
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs?.setInt(
      quickAddDefaultTimedBlockMinutesPreferenceKey,
      normalized,
    );
  }

  Future<void> _loadStoredValue() async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    final stored = _validMinutes(
      prefs?.getInt(quickAddDefaultTimedBlockMinutesPreferenceKey),
    );
    if (ref.mounted && !_hasLocalSelection) {
      state = stored ?? defaultQuickAddTimedBlockMinutes;
    }
  }

  int? _validMinutes(int? value) {
    if (value == null ||
        value < minQuickAddTimedBlockMinutes ||
        value > maxQuickAddTimedBlockMinutes) {
      return null;
    }
    return value;
  }
}

class TaskTimeDisplayModeController extends Notifier<TaskTimeDisplayMode> {
  bool _loaded = false;
  bool _hasLocalSelection = false;

  @override
  TaskTimeDisplayMode build() {
    if (!_loaded) {
      _loaded = true;
      unawaited(_loadStoredMode());
    }
    return TaskTimeDisplayMode.smart;
  }

  Future<void> setMode(TaskTimeDisplayMode mode) async {
    _hasLocalSelection = true;
    state = mode;
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs?.setString(taskTimeDisplayModePreferenceKey, mode.storageValue);
  }

  Future<void> _loadStoredMode() async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    final mode = TaskTimeDisplayMode.fromStorageValue(
      prefs?.getString(taskTimeDisplayModePreferenceKey),
    );
    if (ref.mounted && !_hasLocalSelection) {
      state = mode;
    }
  }
}

class TimelineVisibleHours {
  const TimelineVisibleHours({
    required this.startMinutes,
    required this.endMinutes,
  });

  final int startMinutes;
  final int endMinutes;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TimelineVisibleHours &&
            other.startMinutes == startMinutes &&
            other.endMinutes == endMinutes;
  }

  @override
  int get hashCode => Object.hash(startMinutes, endMinutes);
}

class TimelineVisibleHoursController extends Notifier<TimelineVisibleHours> {
  bool _loaded = false;
  bool _hasLocalSelection = false;

  @override
  TimelineVisibleHours build() {
    if (!_loaded) {
      _loaded = true;
      unawaited(_loadStoredValue());
    }
    return const TimelineVisibleHours(
      startMinutes: defaultTimelineVisibleStartMinutes,
      endMinutes: defaultTimelineVisibleEndMinutes,
    );
  }

  Future<void> setVisibleHours(int startMinutes, int endMinutes) async {
    final normalized = _validHours(startMinutes, endMinutes);
    if (normalized == null) {
      return;
    }
    _hasLocalSelection = true;
    state = normalized;
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs?.setInt(
      timelineVisibleStartMinutesPreferenceKey,
      normalized.startMinutes,
    );
    await prefs?.setInt(
      timelineVisibleEndMinutesPreferenceKey,
      normalized.endMinutes,
    );
  }

  Future<void> _loadStoredValue() async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    final stored = _validHours(
      prefs?.getInt(timelineVisibleStartMinutesPreferenceKey),
      prefs?.getInt(timelineVisibleEndMinutesPreferenceKey),
    );
    if (ref.mounted && !_hasLocalSelection && stored != null) {
      state = stored;
    }
  }

  TimelineVisibleHours? _validHours(int? startMinutes, int? endMinutes) {
    if (startMinutes == null ||
        endMinutes == null ||
        startMinutes < 0 ||
        endMinutes > defaultTimelineVisibleEndMinutes ||
        startMinutes >= endMinutes ||
        startMinutes % timelineSnapMinutes != 0 ||
        endMinutes % timelineSnapMinutes != 0) {
      return null;
    }
    return TimelineVisibleHours(
      startMinutes: startMinutes,
      endMinutes: endMinutes,
    );
  }
}

class TimelineHourWidthController extends Notifier<int> {
  bool _loaded = false;
  bool _hasLocalSelection = false;

  @override
  int build() {
    if (!_loaded) {
      _loaded = true;
      unawaited(_loadStoredValue());
    }
    return defaultTimelineHourWidth;
  }

  Future<void> zoomIn() => _setAdjacent(1);

  Future<void> zoomOut() => _setAdjacent(-1);

  Future<void> _setAdjacent(int delta) {
    final index = timelineHourWidthLevels.indexOf(state);
    final nextIndex = (index + delta).clamp(
      0,
      timelineHourWidthLevels.length - 1,
    );
    return setHourWidth(timelineHourWidthLevels[nextIndex]);
  }

  Future<void> setHourWidth(int value) async {
    if (value == state || !timelineHourWidthLevels.contains(value)) {
      return;
    }
    _hasLocalSelection = true;
    state = value;
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs?.setInt(timelineHourWidthPreferenceKey, state);
  }

  Future<void> _loadStoredValue() async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    final stored = prefs?.getInt(timelineHourWidthPreferenceKey);
    if (ref.mounted &&
        !_hasLocalSelection &&
        timelineHourWidthLevels.contains(stored)) {
      state = stored!;
    }
  }
}

class TimelineCollapsedProjectIdsController extends Notifier<Set<String>> {
  bool _loaded = false;
  bool _hasLocalSelection = false;

  @override
  Set<String> build() {
    if (!_loaded) {
      _loaded = true;
      unawaited(_loadStoredValue());
    }
    return const <String>{};
  }

  Future<void> toggle(String projectId) async {
    _hasLocalSelection = true;
    final next = {...state};
    if (!next.remove(projectId)) {
      next.add(projectId);
    }
    state = Set.unmodifiable(next);
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs?.setStringList(
      timelineCollapsedProjectIdsPreferenceKey,
      next.toList()..sort(),
    );
  }

  Future<void> _loadStoredValue() async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    final stored = prefs?.getStringList(
      timelineCollapsedProjectIdsPreferenceKey,
    );
    if (ref.mounted && !_hasLocalSelection && stored != null) {
      state = Set.unmodifiable(stored);
    }
  }
}

class TimelineTemporaryProjectIdsController extends Notifier<Set<String>> {
  @override
  Set<String> build() => const <String>{};

  void toggle(String projectId) {
    final next = {...state};
    if (!next.remove(projectId)) {
      next.add(projectId);
    }
    state = Set.unmodifiable(next);
  }
}

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

String activeQuickAddHintLocale(AppLanguage language) {
  return (language.locale ?? PlatformDispatcher.instance.locale)
      .toLanguageTag();
}

String quickAddHintFallbackFor(AppLanguage language) {
  final requested = language.locale ?? PlatformDispatcher.instance.locale;
  final locale = AppLocalizations.supportedLocales.firstWhere(
    (candidate) => candidate.languageCode == requested.languageCode,
    orElse: () => const Locale('en'),
  );
  return lookupAppLocalizations(locale).quickAddHint;
}

String quickAddHintEmptyFor(AppLanguage language) {
  final requested = language.locale ?? PlatformDispatcher.instance.locale;
  final locale = AppLocalizations.supportedLocales.firstWhere(
    (candidate) => candidate.languageCode == requested.languageCode,
    orElse: () => const Locale('en'),
  );
  return lookupAppLocalizations(locale).addTask;
}

class QuickAddHintController extends Notifier<QuickAddHintState> {
  late final QuickAddHintCoordinator _coordinator;
  var _hasActiveEntitlement = false;
  late String _locale;

  @override
  QuickAddHintState build() {
    _hasActiveEntitlement = ref
        .read(billingControllerProvider)
        .hasActiveEntitlement;
    ref.listen<BillingState>(billingControllerProvider, (_, next) {
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

final syncQueueRepositoryProvider = Provider<SyncQueueRepository>((ref) {
  return DriftSyncQueueRepository(ref.watch(appDatabaseProvider));
});

final csvTaskImporterProvider = Provider<CsvTaskImporter>((ref) {
  return CsvTaskImporter(
    ref.watch(appDatabaseProvider),
    ref.watch(syncQueueRepositoryProvider),
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
        ref.read(focusRunCompletionControllerProvider.notifier).present(event);
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

final achievementAnnouncementControllerProvider =
    NotifierProvider<
      AchievementAnnouncementController,
      AchievementAnnouncementState
    >(AchievementAnnouncementController.new);

final quickAddServiceProvider = Provider<QuickAddService>((ref) {
  return QuickAddService(
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
      await ref.read(taskRepositoryProvider).materializeDueRecurringTasks();
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
  final russian =
      language == AppLanguage.ru ||
      (language == AppLanguage.system &&
          PlatformDispatcher.instance.locale.languageCode == 'ru');
  return russian
      ? const _TaskStartNotificationCopy(title: 'Время задачи')
      : const _TaskStartNotificationCopy(title: 'Task starting');
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

final focusIntervalsForRunProvider =
    StreamProvider.family<List<FocusIntervalItem>, String>((ref, runId) {
      return ref.watch(focusRepositoryProvider).watchIntervalsForRun(runId);
    });

final focusTickerProvider = StreamProvider<DateTime>((ref) {
  late final StreamController<DateTime> controller;
  Timer? timer;
  controller = StreamController<DateTime>(
    onListen: () {
      controller.add(DateTime.now().toUtc());
      timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => controller.add(DateTime.now().toUtc()),
      );
    },
    onCancel: () => timer?.cancel(),
  );
  return controller.stream;
});

final taskTimeTickerProvider = StreamProvider<DateTime>((ref) {
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
    unawaited(ref.read(focusRepositoryProvider).completeActiveInterval());
  }
  return remaining;
});

final productivitySummaryProvider = StreamProvider<ProductivitySummary>((ref) {
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
      hasProgressToday:
          summary.completedTasks > 0 || summary.completedFocusIntervals > 0,
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
    return todayReminder.add(const Duration(days: 1));
  }
  return todayReminder;
}

_ReengagementNotificationCopy _reengagementNotificationCopy(
  AppLanguage language,
) {
  final russian =
      language == AppLanguage.ru ||
      (language == AppLanguage.system &&
          PlatformDispatcher.instance.locale.languageCode == 'ru');
  if (russian) {
    return const _ReengagementNotificationCopy(
      title: 'Помидор скучает',
      body: 'Один фокус или одна галочка — и день уже не зря.',
    );
  }
  return const _ReengagementNotificationCopy(
    title: 'Your tomato misses you',
    body: 'One focus or one checkmark is enough to save the day.',
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

final googleCalendarAuthServiceProvider = Provider((ref) {
  return createGoogleCalendarAuthService();
});

final googleCalendarApiClientProvider = Provider<GoogleCalendarApiClient>((
  ref,
) {
  final auth = ref.watch(googleCalendarAuthServiceProvider);
  return DioGoogleCalendarApiClient(
    accessTokenProvider: ({bool interactive = false}) =>
        auth.accessToken(interactive: interactive),
  );
});

final calendarIntegrationRepositoryProvider =
    Provider<CalendarIntegrationRepository>((ref) {
      return DriftCalendarIntegrationRepository(
        ref.watch(appDatabaseProvider),
        syncQueue: ref.watch(syncQueueRepositoryProvider),
      );
    });

final googleCalendarSyncControllerProvider =
    Provider<GoogleCalendarSyncController>((ref) {
      return GoogleCalendarSyncController(
        db: ref.watch(appDatabaseProvider),
        taskRepository: ref.watch(driftTaskRepositoryProvider),
        integrationRepository: ref.watch(calendarIntegrationRepositoryProvider),
        authService: ref.watch(googleCalendarAuthServiceProvider),
        apiClient: ref.watch(googleCalendarApiClientProvider),
        deviceId: () => pomodoistDeviceId(ref.read(appDatabaseProvider)),
      );
    });

final googleCalendarSyncLifecycleProvider =
    Provider<GoogleCalendarSyncLifecycle>((ref) {
      final lifecycle = GoogleCalendarSyncLifecycle(
        integrationRepository: ref.watch(calendarIntegrationRepositoryProvider),
        syncQueueRepository: ref.watch(syncQueueRepositoryProvider),
        syncController: ref.watch(googleCalendarSyncControllerProvider),
      )..start();
      ref.onDispose(lifecycle.dispose);
      return lifecycle;
    });

final googleCalendarConnectionProvider =
    StreamProvider<GoogleCalendarConnectionRow?>((ref) {
      return ref.watch(calendarIntegrationRepositoryProvider).watchConnection();
    });

final googleCalendarLinkProvider =
    StreamProvider.family<GoogleCalendarEventLinkRow?, String>((ref, taskId) {
      return ref
          .watch(calendarIntegrationRepositoryProvider)
          .watchLinkForTask(taskId);
    });
