import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/db/app_database.dart';
import '../domain/achievement_models.dart';

const achievementBaselinePreferenceKey = 'achievements.baseline.v1';
const announcedAchievementsPreferenceKey = 'achievements.announcedIds.v1';

class DriftAchievementRepository implements AchievementRepository {
  DriftAchievementRepository(this._db, this._prefsProvider);

  final AppDatabase _db;
  final Future<SharedPreferences?> Function() _prefsProvider;

  @override
  Stream<List<AchievementItem>> watchAchievements() {
    late final StreamController<List<AchievementItem>> controller;
    StreamSubscription<List<TaskCompletionRow>>? completionSubscription;
    StreamSubscription<List<FocusIntervalRow>>? intervalSubscription;

    Future<void> emit() async {
      if (!controller.isClosed) {
        controller.add(await calculateAchievements(_db));
      }
    }

    controller = StreamController<List<AchievementItem>>(
      onListen: () {
        completionSubscription = _db
            .select(_db.taskCompletions)
            .watch()
            .listen((_) => emit());
        intervalSubscription =
            (_db.select(_db.focusIntervals)
                  ..where((interval) => interval.isDeleted.equals(false)))
                .watch()
                .listen((_) => emit());
        emit();
      },
      onCancel: () async {
        await completionSubscription?.cancel();
        await intervalSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<List<AchievementItem>> takePendingAnnouncements(
    List<AchievementItem> items,
  ) async {
    final prefs = await _prefsProvider();
    if (prefs == null) {
      return const [];
    }

    final unlockedIds = items
        .where((item) => item.unlocked)
        .map((item) => item.id)
        .toSet();
    final announcedIds =
        prefs.getStringList(announcedAchievementsPreferenceKey)?.toSet() ??
        <String>{};

    if (!(prefs.getBool(achievementBaselinePreferenceKey) ?? false)) {
      await prefs.setStringList(
        announcedAchievementsPreferenceKey,
        unlockedIds.toList()..sort(),
      );
      await prefs.setBool(achievementBaselinePreferenceKey, true);
      return const [];
    }

    final pending = items
        .where((item) => item.unlocked && !announcedIds.contains(item.id))
        .toList();
    if (pending.isEmpty) {
      return const [];
    }

    final nextAnnounced = {...announcedIds, ...pending.map((item) => item.id)};
    await prefs.setStringList(
      announcedAchievementsPreferenceKey,
      nextAnnounced.toList()..sort(),
    );
    return pending;
  }
}

Future<List<AchievementItem>> calculateAchievements(AppDatabase db) async {
  final completions = await db.select(db.taskCompletions).get();
  final intervals = await (db.select(
    db.focusIntervals,
  )..where((interval) => interval.isDeleted.equals(false))).get();
  return evaluateAchievements(completions: completions, intervals: intervals);
}

List<AchievementItem> evaluateAchievements({
  required List<TaskCompletionRow> completions,
  required List<FocusIntervalRow> intervals,
  DateTime Function(DateTime value)? localize,
}) {
  final toLocal = localize ?? (DateTime value) => value.toLocal();
  final completedWork = intervals
      .where(
        (interval) =>
            !interval.isDeleted &&
            interval.type == 'work' &&
            interval.status == 'completed',
      )
      .toList();
  final stoppedIntervals = intervals
      .where((interval) => !interval.isDeleted && interval.status == 'stopped')
      .toList();

  return [
    for (final definition in _focusMilestones)
      definition.toItem(progress: completedWork.length),
    for (final definition in _taskMilestones)
      definition.toItem(progress: completions.length),
    _comboDayNotWasted(completions, completedWork, toLocal),
    _comboFocusPlusCheck(completions, completedWork, toLocal),
    _comboNoFuss(completedWork, stoppedIntervals, toLocal),
    _comboCleanEntry(completions, completedWork),
    _comboTomatoClosedQuestion(completions, completedWork, toLocal),
  ];
}

AchievementItem _comboDayNotWasted(
  List<TaskCompletionRow> completions,
  List<FocusIntervalRow> completedWork,
  DateTime Function(DateTime value) localize,
) {
  final completionDays = _countCompletionsByDay(completions, localize);
  final workDays = _countWorkByDay(completedWork, localize);
  final unlocked = completionDays.keys.any(
    (day) => completionDays[day]! >= 1 && (workDays[day] ?? 0) >= 1,
  );
  return _comboDefinitions[0].toItem(progress: unlocked ? 1 : 0);
}

AchievementItem _comboFocusPlusCheck(
  List<TaskCompletionRow> completions,
  List<FocusIntervalRow> completedWork,
  DateTime Function(DateTime value) localize,
) {
  final completionDays = _countCompletionsByDay(completions, localize);
  final workDays = _countWorkByDay(completedWork, localize);
  final unlocked = completionDays.keys.any(
    (day) => completionDays[day]! >= 3 && (workDays[day] ?? 0) >= 3,
  );
  return _comboDefinitions[1].toItem(progress: unlocked ? 1 : 0);
}

AchievementItem _comboNoFuss(
  List<FocusIntervalRow> completedWork,
  List<FocusIntervalRow> stoppedIntervals,
  DateTime Function(DateTime value) localize,
) {
  final workDays = _countWorkByDay(completedWork, localize);
  final stoppedDays = _countStoppedByDay(stoppedIntervals, localize);
  final unlocked = workDays.keys.any(
    (day) => workDays[day]! >= 5 && (stoppedDays[day] ?? 0) == 0,
  );
  return _comboDefinitions[2].toItem(progress: unlocked ? 1 : 0);
}

AchievementItem _comboCleanEntry(
  List<TaskCompletionRow> completions,
  List<FocusIntervalRow> completedWork,
) {
  final workByTask = _workByTask(completedWork);
  final unlocked = completions.any((completion) {
    final taskWork =
        workByTask[completion.taskId] ?? const <FocusIntervalRow>[];
    return taskWork.any(
      (interval) =>
          _workFinishedAt(interval).isBefore(completion.completedAt) ||
          _workFinishedAt(interval).isAtSameMomentAs(completion.completedAt),
    );
  });
  return _comboDefinitions[3].toItem(progress: unlocked ? 1 : 0);
}

AchievementItem _comboTomatoClosedQuestion(
  List<TaskCompletionRow> completions,
  List<FocusIntervalRow> completedWork,
  DateTime Function(DateTime value) localize,
) {
  final workByTask = _workByTask(completedWork);
  final unlocked = completions.any((completion) {
    final completionDay = _localDayKey(completion.completedAt, localize);
    final taskWork =
        workByTask[completion.taskId] ?? const <FocusIntervalRow>[];
    return taskWork.any(
      (interval) => _localDayKey(interval.startedAt, localize) == completionDay,
    );
  });
  return _comboDefinitions[4].toItem(progress: unlocked ? 1 : 0);
}

Map<String, int> _countCompletionsByDay(
  List<TaskCompletionRow> completions,
  DateTime Function(DateTime value) localize,
) {
  final result = <String, int>{};
  for (final completion in completions) {
    result.update(
      _localDayKey(completion.completedAt, localize),
      (value) => value + 1,
      ifAbsent: () => 1,
    );
  }
  return result;
}

Map<String, int> _countWorkByDay(
  List<FocusIntervalRow> intervals,
  DateTime Function(DateTime value) localize,
) {
  final result = <String, int>{};
  for (final interval in intervals) {
    result.update(
      _localDayKey(interval.startedAt, localize),
      (value) => value + 1,
      ifAbsent: () => 1,
    );
  }
  return result;
}

Map<String, int> _countStoppedByDay(
  List<FocusIntervalRow> intervals,
  DateTime Function(DateTime value) localize,
) {
  final result = <String, int>{};
  for (final interval in intervals) {
    result.update(
      _localDayKey(interval.startedAt, localize),
      (value) => value + 1,
      ifAbsent: () => 1,
    );
  }
  return result;
}

Map<String, List<FocusIntervalRow>> _workByTask(
  List<FocusIntervalRow> intervals,
) {
  final result = <String, List<FocusIntervalRow>>{};
  for (final interval in intervals) {
    final taskId = interval.taskId;
    if (taskId == null) {
      continue;
    }
    result.putIfAbsent(taskId, () => []).add(interval);
  }
  return result;
}

DateTime _workFinishedAt(FocusIntervalRow interval) {
  return interval.completedAt ?? interval.startedAt;
}

String _localDayKey(
  DateTime value,
  DateTime Function(DateTime value) localize,
) {
  final local = localize(value);
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

class _AchievementDefinition {
  const _AchievementDefinition({
    required this.id,
    required this.group,
    required this.presentation,
    required this.target,
  });

  final String id;
  final AchievementGroup group;
  final AchievementPresentation presentation;
  final int target;

  AchievementItem toItem({required int progress}) {
    return AchievementItem(
      id: id,
      group: group,
      presentation: presentation,
      progress: progress.clamp(0, target).toInt(),
      target: target,
    );
  }
}

const _focusMilestones = [
  _AchievementDefinition(
    id: 'focus_1',
    group: AchievementGroup.focus,
    presentation: AchievementPresentation.globalBanner,
    target: 1,
  ),
  _AchievementDefinition(
    id: 'focus_5',
    group: AchievementGroup.focus,
    presentation: AchievementPresentation.globalBanner,
    target: 5,
  ),
  _AchievementDefinition(
    id: 'focus_10',
    group: AchievementGroup.focus,
    presentation: AchievementPresentation.globalBanner,
    target: 10,
  ),
  _AchievementDefinition(
    id: 'focus_25',
    group: AchievementGroup.focus,
    presentation: AchievementPresentation.globalBanner,
    target: 25,
  ),
  _AchievementDefinition(
    id: 'focus_50',
    group: AchievementGroup.focus,
    presentation: AchievementPresentation.globalBanner,
    target: 50,
  ),
  _AchievementDefinition(
    id: 'focus_100',
    group: AchievementGroup.focus,
    presentation: AchievementPresentation.globalBanner,
    target: 100,
  ),
  _AchievementDefinition(
    id: 'focus_250',
    group: AchievementGroup.focus,
    presentation: AchievementPresentation.globalBanner,
    target: 250,
  ),
  _AchievementDefinition(
    id: 'focus_500',
    group: AchievementGroup.focus,
    presentation: AchievementPresentation.globalBanner,
    target: 500,
  ),
  _AchievementDefinition(
    id: 'focus_1000',
    group: AchievementGroup.focus,
    presentation: AchievementPresentation.globalBanner,
    target: 1000,
  ),
  _AchievementDefinition(
    id: 'focus_5000',
    group: AchievementGroup.focus,
    presentation: AchievementPresentation.globalBanner,
    target: 5000,
  ),
  _AchievementDefinition(
    id: 'focus_10000',
    group: AchievementGroup.focus,
    presentation: AchievementPresentation.globalBanner,
    target: 10000,
  ),
  _AchievementDefinition(
    id: 'focus_50000',
    group: AchievementGroup.focus,
    presentation: AchievementPresentation.globalBanner,
    target: 50000,
  ),
  _AchievementDefinition(
    id: 'focus_100000',
    group: AchievementGroup.focus,
    presentation: AchievementPresentation.globalBanner,
    target: 100000,
  ),
  _AchievementDefinition(
    id: 'focus_1000000',
    group: AchievementGroup.focus,
    presentation: AchievementPresentation.globalBanner,
    target: 1000000,
  ),
];

const _taskMilestones = [
  _AchievementDefinition(
    id: 'task_1',
    group: AchievementGroup.task,
    presentation: AchievementPresentation.globalBanner,
    target: 1,
  ),
  _AchievementDefinition(
    id: 'task_5',
    group: AchievementGroup.task,
    presentation: AchievementPresentation.globalBanner,
    target: 5,
  ),
  _AchievementDefinition(
    id: 'task_10',
    group: AchievementGroup.task,
    presentation: AchievementPresentation.globalBanner,
    target: 10,
  ),
  _AchievementDefinition(
    id: 'task_25',
    group: AchievementGroup.task,
    presentation: AchievementPresentation.globalBanner,
    target: 25,
  ),
  _AchievementDefinition(
    id: 'task_50',
    group: AchievementGroup.task,
    presentation: AchievementPresentation.globalBanner,
    target: 50,
  ),
  _AchievementDefinition(
    id: 'task_100',
    group: AchievementGroup.task,
    presentation: AchievementPresentation.globalBanner,
    target: 100,
  ),
  _AchievementDefinition(
    id: 'task_250',
    group: AchievementGroup.task,
    presentation: AchievementPresentation.globalBanner,
    target: 250,
  ),
  _AchievementDefinition(
    id: 'task_500',
    group: AchievementGroup.task,
    presentation: AchievementPresentation.globalBanner,
    target: 500,
  ),
  _AchievementDefinition(
    id: 'task_1000',
    group: AchievementGroup.task,
    presentation: AchievementPresentation.globalBanner,
    target: 1000,
  ),
  _AchievementDefinition(
    id: 'task_5000',
    group: AchievementGroup.task,
    presentation: AchievementPresentation.globalBanner,
    target: 5000,
  ),
  _AchievementDefinition(
    id: 'task_10000',
    group: AchievementGroup.task,
    presentation: AchievementPresentation.globalBanner,
    target: 10000,
  ),
  _AchievementDefinition(
    id: 'task_50000',
    group: AchievementGroup.task,
    presentation: AchievementPresentation.globalBanner,
    target: 50000,
  ),
  _AchievementDefinition(
    id: 'task_100000',
    group: AchievementGroup.task,
    presentation: AchievementPresentation.globalBanner,
    target: 100000,
  ),
  _AchievementDefinition(
    id: 'task_1000000',
    group: AchievementGroup.task,
    presentation: AchievementPresentation.globalBanner,
    target: 1000000,
  ),
];

const _comboDefinitions = [
  _AchievementDefinition(
    id: 'combo_day_not_wasted',
    group: AchievementGroup.combo,
    presentation: AchievementPresentation.bottomPlaque,
    target: 1,
  ),
  _AchievementDefinition(
    id: 'combo_focus_plus_check',
    group: AchievementGroup.combo,
    presentation: AchievementPresentation.bottomPlaque,
    target: 1,
  ),
  _AchievementDefinition(
    id: 'combo_no_fuss',
    group: AchievementGroup.combo,
    presentation: AchievementPresentation.bottomPlaque,
    target: 1,
  ),
  _AchievementDefinition(
    id: 'combo_clean_entry',
    group: AchievementGroup.combo,
    presentation: AchievementPresentation.bottomPlaque,
    target: 1,
  ),
  _AchievementDefinition(
    id: 'combo_tomato_closed_question',
    group: AchievementGroup.combo,
    presentation: AchievementPresentation.bottomPlaque,
    target: 1,
  ),
];
