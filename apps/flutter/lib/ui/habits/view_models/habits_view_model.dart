import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/habit_dependencies.dart';
import 'package:pomodoist/config/habit_notification_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/habits/habit_repository.dart';
import 'package:pomodoist/domain/models/habits/habit_models.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/notifications/habit_reminder_status.dart';
import 'package:pomodoist/utils/result.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/settings/preferences_repository.dart';

const habitsViewModeKey = 'habits.viewMode.v1';

class HabitDayRow {
  const HabitDayRow({
    required this.habit,
    required this.count,
    required this.target,
    required this.canAdd,
    required this.canUndo,
    required this.history,
    this.project,
    this.dayPeriod = HabitDayPeriod.anytime,
    this.periodTargets = const {},
    this.periodCounts = const {},
    this.periodHistory = const {},
    this.actionPeriod,
  });
  final Habit habit;
  final int count, target;
  final HabitDayPeriod dayPeriod;
  final Map<HabitDayPeriod, int> periodTargets, periodCounts;
  final Map<HabitDayPeriod, List<({DateTime day, int count, int? target})>>
  periodHistory;
  final HabitDayPeriod? actionPeriod;
  Map<HabitDayPeriod, int> get targets =>
      periodTargets.isEmpty ? {dayPeriod: target} : periodTargets;
  HabitDayRow forPeriod(HabitDayPeriod period) => HabitDayRow(
    habit: habit,
    count: periodCounts[period] ?? count,
    target: targets[period]!,
    canAdd: canAdd && (periodCounts[period] ?? count) < targets[period]!,
    canUndo: canUndo && (periodCounts[period] ?? count) > 0,
    history: periodHistory[period] ?? history,
    project: project,
    dayPeriod: period,
    actionPeriod: period,
    periodTargets: targets,
    periodCounts: periodCounts,
  );
  bool get complete => count >= target;
  final bool canAdd, canUndo;
  final ProjectItem? project;
  final List<({DateTime day, int count, int? target})> history;
}

class HabitsViewState {
  const HabitsViewState({
    required this.today,
    required this.selectedDay,
    required this.rows,
    required this.projects,
    required this.reminderStatus,
    required this.planned,
    required this.completed,
    required this.loading,
    required this.finished,
    required this.saving,
    this.habits = const [],
    this.loadError = false,
    this.actionError = false,
    this.viewMode = HabitViewMode.list,
    this.viewSettingsLoading = false,
    this.viewSaving = false,
    this.viewError = false,
  });
  final DateTime today, selectedDay;
  final List<Habit> habits;
  final List<HabitDayRow> rows;
  final List<ProjectItem> projects;
  final HabitReminderStatus reminderStatus;
  final int planned, completed;
  final bool loading, finished, saving, loadError, actionError;
  final HabitViewMode viewMode;
  final bool viewSettingsLoading, viewSaving, viewError;
  List<HabitDayRow> get remainingRows =>
      rows.where((r) => !r.complete).toList();
  List<HabitDayRow> get completedRows => rows.where((r) => r.complete).toList();
  List<({HabitDayPeriod period, List<HabitDayRow> rows})> get rhythmGroups => [
    for (final period in HabitDayPeriod.values.skip(1))
      if (rows.any((r) => r.targets.containsKey(period)))
        (
          period: period,
          rows: [
            ...rows
                .where((r) => r.targets.containsKey(period))
                .map((r) => r.forPeriod(period))
                .where((r) => !r.complete),
            ...rows
                .where((r) => r.targets.containsKey(period))
                .map((r) => r.forPeriod(period))
                .where((r) => r.complete),
          ],
        ),
  ];
  bool get futureDay => selectedDay.isAfter(today);
  DateTime get weekStart => DateTime(
    selectedDay.year,
    selectedDay.month,
    selectedDay.day - selectedDay.weekday + 1,
  );
}

final habitsViewModelProvider =
    NotifierProvider.autoDispose<HabitsViewModel, HabitsViewState>(
      HabitsViewModel.new,
    );

class HabitsViewModel extends Notifier<HabitsViewState> {
  late HabitRepository _repository;
  late PreferencesRepository _preferences;
  Future<void>? _settingsLoad;
  HabitViewMode _viewMode = HabitViewMode.list;
  bool _viewLoaded = false, _viewSaving = false, _viewError = false;
  DateTime? _selected, _lastToday;
  bool _finished = false, _saving = false, _actionError = false;
  @override
  HabitsViewState build() {
    _repository = ref.watch(habitRepositoryProvider);
    _preferences = ref.read(preferencesRepositoryProvider);
    _settingsLoad ??= Future.microtask(_loadViewMode);
    ref.listen(habitsProvider, (_, _) => _refresh());
    ref.listen(habitCheckInsProvider, (_, _) => _refresh());
    ref.listen(projectsProvider, (_, _) => _refresh());
    ref.listen(habitReminderStatusProvider, (_, _) => _refresh());
    final timer = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
    ref.onDispose(timer.cancel);
    return _compute();
  }

  HabitsViewState _compute() {
    final today = habitDate(ref.read(clockProvider).now().toLocal());
    if (_selected == null || _selected == _lastToday) _selected = today;
    _lastToday = today;
    final habits = ref.read(habitsProvider),
        checks = ref.read(habitCheckInsProvider),
        projects = ref.read(projectsProvider);
    final personal = (projects.value ?? const <ProjectItem>[])
        .where((p) => p.scopeId == null && !p.isArchived && !p.isDeleted)
        .toList();
    final byId = {for (final p in personal) p.id: p};
    final scheduled = (habits.value ?? const <Habit>[])
        .where((h) => h.isScheduledOn(_selected!))
        .toList();
    final checkIns = checks.value ?? const <HabitCheckIn>[];
    final checksByDay = <(String, DateTime), List<HabitCheckIn>>{};
    for (final check in checkIns) {
      if (!check.isDeleted) {
        (checksByDay[(check.habitId, check.day)] ??= []).add(check);
      }
    }
    Map<HabitDayPeriod, int> countsFor(Habit h, DateTime day) =>
        habitPeriodCounts(h, day, checksByDay[(h.id, day)] ?? const []);
    int totalFor(Habit h, DateTime day) =>
        countsFor(h, day).values.fold(0, (a, b) => a + b);
    final complete = scheduled
        .where(
          (h) =>
              totalFor(h, _selected!) >=
              h.scheduleFor(_selected!)!.targetPerDay,
        )
        .length;
    final visible = (habits.value ?? const <Habit>[]).where(
      (h) =>
          !h.isDeleted &&
          h.isFinishedOn(today) == _finished &&
          (_finished || h.isScheduledOn(_selected!)),
    );
    final rows = visible.map((h) {
      final periodCounts = countsFor(h, _selected!);
      final count = periodCounts.values.fold(0, (a, b) => a + b);
      final schedule = h.scheduleFor(_selected!) ?? h.scheduleHistory.last;
      final target = schedule.targetPerDay;
      final targets = schedule.targetsFor(h.reminderMinutes);
      final days = List.generate(
        5,
        (i) =>
            DateTime(_selected!.year, _selected!.month, _selected!.day - 4 + i),
      );
      final historyCounts = {for (final day in days) day: countsFor(h, day)};
      final periodHistory =
          <HabitDayPeriod, List<({DateTime day, int count, int? target})>>{
            for (final period in targets.keys)
              period: [
                for (final day in days)
                  (
                    day: day,
                    count: day.isAfter(today) || !h.isScheduledOn(day)
                        ? 0
                        : historyCounts[day]![period] ?? 0,
                    target: h.isScheduledOn(day)
                        ? h
                              .scheduleFor(day)!
                              .targetsFor(h.reminderMinutes)[period]
                        : null,
                  ),
              ],
          };
      return HabitDayRow(
        habit: h,
        count: count,
        target: target,
        dayPeriod: targets.keys.first,
        periodTargets: targets,
        periodCounts: periodCounts,
        periodHistory: periodHistory,
        history: [
          for (final day in days)
            (
              day: day,
              count: day.isAfter(today) || !h.isScheduledOn(day)
                  ? 0
                  : historyCounts[day]!.values.fold(0, (a, b) => a + b),
              target: h.isScheduledOn(day)
                  ? h.scheduleFor(day)!.targetPerDay
                  : null,
            ),
        ],
        project: byId[h.projectId],
        canAdd:
            !_selected!.isAfter(today) &&
            h.isScheduledOn(_selected!) &&
            count < target,
        canUndo: !_selected!.isAfter(today) && count > 0,
      );
    }).toList();
    return HabitsViewState(
      today: today,
      selectedDay: _selected!,
      habits: List.unmodifiable(habits.value ?? const <Habit>[]),
      rows: List.unmodifiable(rows),
      projects: List.unmodifiable(personal),
      reminderStatus: ref.read(habitReminderStatusProvider),
      planned: scheduled.length,
      completed: complete,
      loading: habits.isLoading || checks.isLoading || projects.isLoading,
      loadError: habits.hasError || checks.hasError || projects.hasError,
      finished: _finished,
      saving: _saving,
      actionError: _actionError,
      viewMode: _viewMode,
      viewSettingsLoading: !_viewLoaded,
      viewSaving: _viewSaving,
      viewError: _viewError,
    );
  }

  Future<void> _loadViewMode() async {
    if (!ref.mounted) return;
    try {
      final values = (await _preferences.read([
        habitsViewModeKey,
      ])).getOrThrow();
      if (!ref.mounted) return;
      _viewMode =
          HabitViewMode.values
              .where((mode) => mode.name == values[habitsViewModeKey])
              .firstOrNull ??
          HabitViewMode.list;
      _viewError = false;
    } catch (_) {
      if (!ref.mounted) return;
      _viewError = true;
    } finally {
      if (ref.mounted) {
        _viewLoaded = true;
        _refresh();
      }
    }
  }

  Future<void> setViewMode(HabitViewMode mode) async {
    if (_viewSaving) return;
    _viewSaving = true;
    _refresh();
    try {
      await _settingsLoad;
      (await _preferences.write({habitsViewModeKey: mode.name})).getOrThrow();
      if (!ref.mounted) return;
      _viewMode = mode;
      _viewError = false;
    } catch (_) {
      if (!ref.mounted) return;
      _viewError = true;
    } finally {
      if (ref.mounted) {
        _viewSaving = false;
        _refresh();
      }
    }
  }

  Future<void> retryViewMode() {
    if (_viewSaving || !_viewLoaded) return Future.value();
    _viewLoaded = false;
    _refresh();
    return _settingsLoad = _loadViewMode();
  }

  void _refresh() {
    if (ref.mounted) state = _compute();
  }

  void selectDay(DateTime day) {
    _selected = habitDate(day);
    _refresh();
  }

  void selectToday() {
    selectDay(ref.read(clockProvider).now().toLocal());
  }

  void moveWeek(int delta) {
    selectDay(
      DateTime(
        state.selectedDay.year,
        state.selectedDay.month,
        state.selectedDay.day + delta * 7,
      ),
    );
  }

  void showFinished(bool value) {
    _finished = value;
    _refresh();
  }

  void retry() {
    ref.invalidate(habitsProvider);
    ref.invalidate(habitCheckInsProvider);
    ref.invalidate(projectsProvider);
  }

  Future<bool> _run(Future<Result<Object?>> Function() operation) async {
    if (_saving) return false;
    _saving = true;
    _actionError = false;
    _refresh();
    try {
      (await operation()).getOrThrow();
      return true;
    } catch (_) {
      _actionError = true;
      return false;
    } finally {
      _saving = false;
      _refresh();
    }
  }

  Future<bool> save({
    String? id,
    required String title,
    required DateTime startDate,
    DateTime? endDate,
    required List<int> weekdays,
    required String target,
    String? icon,
    String? projectId,
    int? reminderMinutes,
    HabitDayPeriod dayPeriod = HabitDayPeriod.automatic,
    Map<HabitDayPeriod, int> periodTargets = const {},
  }) => _run(() async {
    final draft = HabitDraft(
      title: title,
      startDate: startDate,
      endDate: endDate,
      weekdays: weekdays,
      targetPerDay: int.tryParse(target) ?? 0,
      icon: icon,
      projectId: projectId,
      reminderMinutes: reminderMinutes,
      dayPeriod: dayPeriod,
      periodTargets: periodTargets,
    );
    final now = ref.read(clockProvider).now();
    if (id == null) return _repository.createHabit(draft, now: now);
    return _repository.updateHabit(id, draft, now: now);
  });
  Future<bool> addCheckIn(String id, {HabitDayPeriod? period}) {
    final day = state.selectedDay;
    return _run(
      () => _repository.addCheckIn(
        id,
        day,
        period: period,
        now: ref.read(clockProvider).now(),
      ),
    );
  }

  Future<bool> undoCheckIn(String id, {HabitDayPeriod? period}) {
    final day = state.selectedDay;
    return _run(
      () => _repository.undoCheckIn(
        id,
        day,
        period: period,
        now: ref.read(clockProvider).now(),
      ),
    );
  }

  Future<bool> updateIcon(String id, String? icon) => _run(
    () => _repository.updateIcon(id, icon, now: ref.read(clockProvider).now()),
  );
  Future<bool> deleteHabit(String id) => _run(
    () => _repository.deleteHabit(id, now: ref.read(clockProvider).now()),
  );
  Future<void> retryReminders() =>
      ref.read(habitReminderStatusProvider.notifier).refresh();
}
