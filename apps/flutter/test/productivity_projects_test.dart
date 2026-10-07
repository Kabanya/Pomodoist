import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/productivity/productivity_repository_impl.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/domain/models/productivity/productivity_models.dart';
import 'package:pomodoist/ui/productivity/view_models/productivity_view_models.dart';
import 'package:pomodoist/utils/clock.dart';

void main() {
  final today = DateTime(2026, 10, 6);
  ProductivitySummary evaluate(List<FocusIntervalRow> intervals) =>
      evaluateProductivitySummary(
        reportDate: today,
        tasks: [
          _task('task', 'new-project'),
          _task('deleted', 'p', deleted: true),
        ],
        projects: [_project('p'), _project('removed', deleted: true)],
        completions: const [],
        intervals: intervals,
        localize: (date) => date,
      );

  test('both periods conserve focus time and retain the recorded project', () {
    final summary = evaluate([
      _interval('today', today, project: 'p', task: 'task', pause: 300),
      _interval('first-day', DateTime(2026, 9, 30), project: 'p', task: 'task'),
      _interval('outside', DateTime(2026, 9, 29), project: 'p'),
      _interval('future', DateTime(2026, 10, 7), project: 'p'),
      _interval('break', today, project: 'p', type: 'shortBreak'),
      _interval('running', today, project: 'p', status: 'running'),
      _interval('deleted', today, project: 'p', deleted: true),
      _interval('free', today),
    ]);
    expect(summary.todayProjects.map((p) => p.totalFocusSeconds), [1500, 1200]);
    expect(summary.lastSevenDaysProjects.map((p) => p.totalFocusSeconds), [
      2700,
      1500,
    ]);
    final project = summary.lastSevenDaysProjects.first;
    expect(project.projectId, 'p');
    expect(project.tasks.single.taskId, 'task');
    expect(project.tasks.single.canOpen, isTrue);
    expect(project.completedFocusIntervals, 2);
    expect(summary.totalFocusSeconds, 2700);
    expect(
      summary.lastSevenDays.fold<int>(
        0,
        (sum, day) => sum + day.totalFocusSeconds,
      ),
      4200,
    );
  });

  test('missing links and deleted records keep separate historical groups', () {
    final summary = evaluate([
      _interval('removed', today, project: 'removed', task: 'deleted'),
      _interval('missing', today, project: 'missing', task: 'missing'),
      _interval('no-task', today, project: 'p'),
      _interval('no-project', today, task: 'task'),
    ]);
    final groups = {for (final p in summary.todayProjects) p.projectId: p};
    expect(groups.keys, containsAll([null, 'p', 'removed', 'missing']));
    expect(groups['removed']!.isUnavailable, isTrue);
    expect(groups['removed']!.name, 'removed');
    expect(groups['missing']!.name, isNull);
    expect(groups['removed']!.tasks.single.canOpen, isFalse);
    expect(groups['missing']!.tasks.single.canOpen, isFalse);
    expect(groups['p']!.tasks.single.taskId, isNull);
    expect(groups[null]!.tasks.single.taskId, 'task');
    expect(summary.totalFocusSeconds, 6000);
  });

  test(
    'local calendar boundaries and negative durations match daily totals',
    () {
      final summary = evaluateProductivitySummary(
        reportDate: today,
        tasks: const [],
        completions: const [],
        intervals: [
          _interval('today', DateTime.utc(2026, 10, 5, 22)),
          _interval('yesterday', DateTime.utc(2026, 10, 5, 20)),
          _interval('zero', DateTime.utc(2026, 10, 5, 23), pause: 2000),
        ],
        localize: (date) => date.add(const Duration(hours: 3)),
      );
      expect(summary.todayProjects.single.totalFocusSeconds, 1500);
      expect(summary.todayProjects.single.completedFocusIntervals, 2);
      expect(summary.lastSevenDaysProjects.single.totalFocusSeconds, 3000);
      expect(evaluate(const []).todayProjects, isEmpty);
    },
  );

  test('ties sort by project and task IDs, not input order', () {
    final summary = evaluate([
      _interval('b', today, project: 'b', task: 'z'),
      _interval('a', today, project: 'a', task: 'z'),
      _interval('a2', today, project: 'a', task: 'a'),
      _interval('b2', today, project: 'b', task: 'a'),
    ]);
    expect(summary.todayProjects.map((p) => p.projectId), ['a', 'b']);
    expect(summary.todayProjects.first.tasks.map((t) => t.taskId), ['a', 'z']);
  });

  test(
    'the live stream refreshes names, colors, intervals and the local day',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final clock = FixedClock(DateTime.now());
      final start = clock.now().toLocal();
      await db.into(db.projects).insert(_project('p'));
      await db.into(db.tasks).insert(_task('task', 'p'));
      await db
          .into(db.focusIntervals)
          .insert(
            _interval(
              'work',
              start,
              project: 'p',
              task: 'task',
              status: 'running',
            ),
          );
      final repository = DriftProductivityRepository(db, clock: clock);
      final iterator = StreamIterator(repository.watchTodaySummary());
      addTearDown(iterator.cancel);
      Future<ProductivitySummary> nextWhere(
        bool Function(ProductivitySummary) matches,
      ) async {
        while (await iterator.moveNext()) {
          if (matches(iterator.current)) return iterator.current;
        }
        throw StateError('Summary stream closed');
      }

      await nextWhere(
        (s) => s.todayProjects.isEmpty,
      ).timeout(const Duration(seconds: 5));
      await (db.update(db.focusIntervals)..where((r) => r.id.equals('work')))
          .write(const FocusIntervalsCompanion(status: Value('completed')));
      final completed = await nextWhere(
        (s) => s.todayProjects.isNotEmpty,
      ).timeout(const Duration(seconds: 5));
      expect(completed.todayProjects.single.name, 'p');
      await (db.update(db.projects)..where((r) => r.id.equals('p'))).write(
        const ProjectsCompanion(
          name: Value('Renamed'),
          color: Value('#36A269'),
        ),
      );
      final renamed = await nextWhere(
        (s) => s.todayProjects.single.name == 'Renamed',
      ).timeout(const Duration(seconds: 5));
      expect(renamed.todayProjects.single.color, '#36A269');
      await (db.update(db.tasks)..where((r) => r.id.equals('task'))).write(
        const TasksCompanion(
          content: Value('New title'),
          projectId: Value('moved'),
        ),
      );
      final moved = await nextWhere(
        (s) => s.todayProjects.single.tasks.single.name == 'New title',
      ).timeout(const Duration(seconds: 5));
      expect(moved.todayProjects.single.projectId, 'p');
      clock.value = DateTime(start.year, start.month, start.day + 1);
      await iterator.cancel();
      final nextDay = await repository.watchTodaySummary().first;
      expect(nextDay.todayProjects, isEmpty);
      expect(nextDay.lastSevenDaysProjects.single.totalFocusSeconds, 1500);
    },
  );

  test('project period resets expansion while summary updates retain it', () {
    final clock = FixedClock(today);
    final container = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(clock),
        focusTickerProvider.overrideWithValue(AsyncData(today)),
        productivitySummaryProvider.overrideWithValue(
          AsyncData(evaluate([_interval('p', today, project: 'p')])),
        ),
        achievementsProvider.overrideWithValue(const AsyncData([])),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(reportsViewModelProvider, (_, _) {});
    addTearDown(subscription.close);
    final viewModel = container.read(reportsViewModelProvider.notifier);
    viewModel.toggleProject('p');
    container.updateOverrides([
      clockProvider.overrideWithValue(clock),
      focusTickerProvider.overrideWithValue(AsyncData(today)),
      productivitySummaryProvider.overrideWithValue(
        AsyncData(
          evaluate([
            _interval('p', today, project: 'p'),
            _interval('p2', today, project: 'p'),
          ]),
        ),
      ),
      achievementsProvider.overrideWithValue(const AsyncData([])),
    ]);
    expect(container.read(reportsViewModelProvider).expandedProjectIds, {'p'});
    expect(
      container
          .read(reportsViewModelProvider)
          .summary
          .value!
          .todayProjects
          .single
          .completedFocusIntervals,
      2,
    );
    expect(
      container.read(reportsViewModelProvider).projectPeriod,
      ReportsProjectPeriod.lastSevenDays,
    );
    viewModel.setProjectPeriod(ReportsProjectPeriod.today);
    expect(
      container.read(reportsViewModelProvider).expandedProjectIds,
      isEmpty,
    );
    viewModel.toggleProject(null);
    viewModel.setProjectPeriod(ReportsProjectPeriod.today);
    expect(container.read(reportsViewModelProvider).expandedProjectIds, {null});
    viewModel.toggleProject(null);
    expect(
      container.read(reportsViewModelProvider).expandedProjectIds,
      isEmpty,
    );
  });
}

TaskRow _task(String id, String project, {bool deleted = false}) => TaskRow(
  id: id,
  userId: localUserId,
  content: id,
  projectId: project,
  assigneeIdsJson: '[]',
  priority: 4,
  status: 'open',
  completedFocusIntervals: 0,
  totalFocusSeconds: 0,
  orderKey: id,
  isCollapsed: false,
  isDeleted: deleted,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

ProjectRow _project(String id, {bool deleted = false}) => ProjectRow(
  id: id,
  userId: localUserId,
  name: id,
  color: '#E44332',
  viewStyle: 'list',
  isFavorite: false,
  isArchived: false,
  isDeleted: deleted,
  orderKey: id,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

FocusIntervalRow _interval(
  String id,
  DateTime start, {
  String? project,
  String? task,
  int pause = 0,
  String type = 'work',
  String status = 'completed',
  bool deleted = false,
}) => FocusIntervalRow(
  id: id,
  runId: id,
  projectId: project,
  taskId: task,
  type: type,
  status: status,
  plannedSeconds: 1500,
  startedAt: start,
  completedAt: start.add(const Duration(seconds: 1500)),
  pausedTotalSeconds: pause,
  sequenceNumber: 1,
  isDeleted: deleted,
  createdAt: start,
  updatedAt: start,
);
