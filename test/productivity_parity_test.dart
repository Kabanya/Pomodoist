import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/features/productivity/data/achievement_repository_impl.dart';
import 'package:pomodoist/features/productivity/data/productivity_repository_impl.dart';
import 'package:timezone/data/latest.dart' as time_zone_data;
import 'package:timezone/timezone.dart' as time_zone;

void main() {
  setUpAll(time_zone_data.initializeTimeZones);

  test('production evaluators match the shared IANA-zone fixtures', () {
    final fixture = _fixture();

    for (final fixtureCase in fixture) {
      final zone = fixtureCase['timeZone'] as String;
      final location = zone == 'UTC'
          ? time_zone.UTC
          : time_zone.getLocation(zone);
      DateTime localize(DateTime value) =>
          time_zone.TZDateTime.from(value, location);
      final expected = fixtureCase['expected'] as Map<String, dynamic>;
      final summary = evaluateProductivitySummary(
        reportDate: DateTime.parse(fixtureCase['reportDate'] as String),
        tasks: _tasks(fixtureCase),
        completions: _completions(fixtureCase),
        intervals: _intervals(fixtureCase),
        localize: localize,
      );
      final items = evaluateAchievements(
        completions: _completions(fixtureCase),
        intervals: _intervals(fixtureCase),
        localize: localize,
      );
      final daily = expected['daily'] as Map<String, dynamic>;
      final allTime = expected['allTime'] as Map<String, dynamic>;
      final expectedDays = (expected['lastSevenDays'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final achievementInputs =
          expected['achievementInputs'] as Map<String, dynamic>;
      final comboFlags =
          achievementInputs['comboFlags'] as Map<String, dynamic>;

      expect(
        [
          summary.completedTasks,
          summary.completedFocusIntervals,
          summary.totalFocusSeconds,
          summary.plannedFocusIntervals,
          summary.openTasks,
          summary.allTimeCompletedTasks,
          summary.allTimeCompletedFocusIntervals,
        ],
        [
          daily['completedTasks'],
          daily['completedFocusIntervals'],
          daily['totalFocusSeconds'],
          expected['plannedFocusIntervals'],
          expected['openTasks'],
          allTime['completedTasks'],
          allTime['completedFocusIntervals'],
        ],
        reason: '${fixtureCase['name']}: summary',
      );
      expect(summary.lastSevenDays, hasLength(expectedDays.length));
      for (var index = 0; index < expectedDays.length; index++) {
        final actualDay = summary.lastSevenDays[index];
        final expectedDay = expectedDays[index];
        expect(
          [
            _dateKey(actualDay.localDate),
            actualDay.completedTasks,
            actualDay.completedFocusIntervals,
            actualDay.totalFocusSeconds,
          ],
          [
            expectedDay['date'],
            expectedDay['completedTasks'],
            expectedDay['completedFocusIntervals'],
            expectedDay['totalFocusSeconds'],
          ],
          reason: '${fixtureCase['name']}: lastSevenDays[$index]',
        );
      }

      for (final entry in _comboIds.entries) {
        expect(
          items.singleWhere((item) => item.id == entry.value).unlocked,
          comboFlags[entry.key],
          reason: '${fixtureCase['name']}: ${entry.key}',
        );
      }

      final expectedUnlockedIds = _expectedUnlockedIds(achievementInputs);
      final unlockedItems = items.where((item) => item.unlocked).toList();
      expect(
        unlockedItems.map((item) => item.id).toSet(),
        expectedUnlockedIds,
        reason: '${fixtureCase['name']}: unlocked achievement IDs',
      );
      for (final item in unlockedItems) {
        expect(item.titleFor('ru'), isNotEmpty);
        expect(item.subtitleFor('ru'), isNotEmpty);
        expect(item.titleFor('en'), isNotEmpty);
        expect(item.subtitleFor('en'), isNotEmpty);
      }
    }
  });

  test('repository keeps system-local daily behavior by default', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final today = DateTime.now();
    final localNoon = DateTime(today.year, today.month, today.day, 12).toUtc();
    await db
        .into(db.taskCompletions)
        .insert(
          TaskCompletionsCompanion.insert(
            id: 'completion',
            taskId: 'task',
            userId: localUserId,
            completedAt: localNoon,
            createdAt: localNoon,
          ),
        );
    await db
        .into(db.focusIntervals)
        .insert(
          FocusIntervalsCompanion.insert(
            id: 'work',
            runId: 'run',
            type: 'work',
            status: 'completed',
            plannedSeconds: 600,
            startedAt: localNoon,
            completedAt: Value(localNoon.add(const Duration(minutes: 10))),
            sequenceNumber: 1,
            createdAt: localNoon,
            updatedAt: localNoon,
          ),
        );

    await DriftProductivityRepository(db).recalculateDailyStats(today);

    final row = await db.select(db.focusDailyStats).getSingle();
    expect(
      [row.completedTasks, row.completedFocusIntervals, row.totalFocusSeconds],
      [1, 1, 600],
    );
  });

  test('last seven days use calendar dates across a DST change', () {
    final berlin = time_zone.getLocation('Europe/Berlin');
    final days = lastSevenProductivityDays(
      time_zone.TZDateTime(berlin, 2026, 3, 30),
    );

    expect(days.map(_dateKey), [
      '2026-03-24',
      '2026-03-25',
      '2026-03-26',
      '2026-03-27',
      '2026-03-28',
      '2026-03-29',
      '2026-03-30',
    ]);
    expect(days.every((day) => day.hour == 0), isTrue);
  });
}

const _fixturePath = 'test/fixtures/pomodoist_productivity_parity.json';

const _comboIds = <String, String>{
  'dayNotWasted': 'combo_day_not_wasted',
  'focusPlusCheck': 'combo_focus_plus_check',
  'noFuss': 'combo_no_fuss',
  'cleanEntry': 'combo_clean_entry',
  'tomatoClosed': 'combo_tomato_closed_question',
};

const _focusMilestones = <int, String>{
  1: 'focus_1',
  5: 'focus_5',
  10: 'focus_10',
  25: 'focus_25',
  50: 'focus_50',
  100: 'focus_100',
  250: 'focus_250',
  500: 'focus_500',
  1000: 'focus_1000',
  5000: 'focus_5000',
  10000: 'focus_10000',
  50000: 'focus_50000',
  100000: 'focus_100000',
  1000000: 'focus_1000000',
};

const _taskMilestones = <int, String>{
  1: 'task_1',
  5: 'task_5',
  10: 'task_10',
  25: 'task_25',
  50: 'task_50',
  100: 'task_100',
  250: 'task_250',
  500: 'task_500',
  1000: 'task_1000',
  5000: 'task_5000',
  10000: 'task_10000',
  50000: 'task_50000',
  100000: 'task_100000',
  1000000: 'task_1000000',
};

List<Map<String, dynamic>> _fixture() {
  final json =
      jsonDecode(File(_fixturePath).readAsStringSync()) as Map<String, dynamic>;
  return (json['cases'] as List<dynamic>).cast<Map<String, dynamic>>();
}

List<TaskRow> _tasks(Map<String, dynamic> fixtureCase) {
  return [
    for (final row
        in (fixtureCase['tasks'] as List<dynamic>).cast<Map<String, dynamic>>())
      TaskRow(
        id: row['id'] as String,
        userId: fixtureCase['userId'] as String,
        content: row['content'] as String,
        projectId: row['projectId'] as String,
        priority: 4,
        dueJson: row['dueJson'] as String?,
        status: row['status'] as String,
        estimatedFocusIntervals: row['estimatedFocusIntervals'] as int?,
        completedFocusIntervals: 0,
        totalFocusSeconds: 0,
        orderKey: row['id'] as String,
        isCollapsed: false,
        isDeleted: false,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
  ];
}

List<TaskCompletionRow> _completions(Map<String, dynamic> fixtureCase) {
  return [
    for (final row
        in (fixtureCase['taskCompletions'] as List<dynamic>)
            .cast<Map<String, dynamic>>())
      TaskCompletionRow(
        id: row['id'] as String,
        taskId: row['taskId'] as String,
        userId: fixtureCase['userId'] as String,
        completedAt: DateTime.parse(row['completedAt'] as String),
        createdAt: DateTime.parse(row['completedAt'] as String),
      ),
  ];
}

Set<String> _expectedUnlockedIds(Map<String, dynamic> achievementInputs) {
  final completedTasks = achievementInputs['completedTasks'] as int;
  final completedWork = achievementInputs['completedWorkIntervals'] as int;
  final comboFlags = achievementInputs['comboFlags'] as Map<String, dynamic>;
  return {
    for (final entry in _focusMilestones.entries)
      if (completedWork >= entry.key) entry.value,
    for (final entry in _taskMilestones.entries)
      if (completedTasks >= entry.key) entry.value,
    for (final entry in _comboIds.entries)
      if (comboFlags[entry.key] as bool) entry.value,
  };
}

String _dateKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

List<FocusIntervalRow> _intervals(Map<String, dynamic> fixtureCase) {
  return [
    for (final row
        in (fixtureCase['focusIntervals'] as List<dynamic>)
            .cast<Map<String, dynamic>>())
      FocusIntervalRow(
        id: row['id'] as String,
        runId: 'run-${row['id']}',
        taskId: row['taskId'] as String?,
        type: row['type'] as String,
        status: row['status'] as String,
        plannedSeconds: 1500,
        startedAt: DateTime.parse(row['startedAt'] as String),
        pausedTotalSeconds: row['pausedTotalSeconds'] as int,
        completedAt: row['completedAt'] == null
            ? null
            : DateTime.parse(row['completedAt'] as String),
        stoppedAt: row['stoppedAt'] == null
            ? null
            : DateTime.parse(row['stoppedAt'] as String),
        sequenceNumber: 1,
        createdAt: DateTime.parse(row['startedAt'] as String),
        updatedAt: DateTime.parse(row['startedAt'] as String),
        isDeleted: row['isDeleted'] as bool,
      ),
  ];
}
