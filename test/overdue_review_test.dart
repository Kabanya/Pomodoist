import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/app/task_time.dart';
import 'package:pomodoist/core/time/clock.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';
import 'package:pomodoist/features/tasks/presentation/task_scheduling.dart';
import 'package:pomodoist/features/tasks/presentation/widgets/task_selection_region.dart';

void main() {
  final midnight = DateTime(2026, 9, 10);
  final timed = TaskSchedule.timed(
    start: DateTime(2026, 9, 9, 23, 30),
    end: DateTime(2026, 9, 10, 0, 30),
  );

  test('all-day becomes overdue at local midnight; timed waits for end', () {
    final allDay = task('all-day', TaskSchedule.allDay(DateTime(2026, 9, 9)));
    expect(
      isTaskOverdue(allDay, midnight.subtract(const Duration(microseconds: 1))),
      isFalse,
    );
    expect(isTaskOverdue(allDay, midnight.toUtc()), isTrue);
    expect(isTaskOverdue(task('timed', timed), midnight), isFalse);
    expect(
      isTaskOverdue(
        task('timed', timed),
        timed.end!.subtract(const Duration(microseconds: 1)),
      ),
      isFalse,
    );
    expect(isTaskOverdue(task('timed', timed), timed.end!), isTrue);
    expect(
      taskTimeStateForTask(
        task: task('timed', timed),
        now: timed.end!,
        activeFocusTaskId: 'timed',
      ),
      TaskTimeState.focused,
    );
    expect(isTaskOverdue(task('timed', timed), timed.end!), isTrue);
  });

  test(
    'completed, deleted and unscheduled tasks never enter overdue review',
    () {
      expect(
        isTaskOverdue(
          task('completed', timed, completed: true),
          midnight.add(const Duration(days: 1)),
        ),
        isFalse,
      );
      expect(
        isTaskOverdue(
          task('deleted', timed, deleted: true),
          midnight.add(const Duration(days: 1)),
        ),
        isFalse,
      );
      expect(isTaskOverdue(task('unscheduled', null), midnight), isFalse);
      expect(
        isTaskOverdue(task('future', TaskSchedule.allDay(midnight)), midnight),
        isFalse,
      );
    },
  );

  test(
    'shared overdue source follows task and clock events without hiding errors',
    () async {
      final tasks = StreamController<List<TaskItem>>();
      final ticks = StreamController<DateTime>();
      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(FixedClock(midnight)),
          taskTimeTickerProvider.overrideWith((ref) => ticks.stream),
          tasksByQueryProvider(
            const TaskQuery.all(),
          ).overrideWith((ref) => tasks.stream),
        ],
      );
      final subscription = container.listen(overdueTasksProvider, (_, _) {});
      addTearDown(() async {
        subscription.close();
        container.dispose();
        await tasks.close();
        await ticks.close();
      });
      expect(container.read(overdueTasksProvider).isLoading, isTrue);
      final items = [
        task('a', TaskSchedule.allDay(DateTime(2026, 9, 9))),
        task('b', timed),
      ];
      tasks.add(items);
      await container.read(tasksByQueryProvider(const TaskQuery.all()).future);
      expect(container.read(overdueTasksProvider).value!.map((t) => t.id), [
        'a',
      ]);
      ticks.add(timed.end!);
      await container.read(taskTimeTickerProvider.future);
      expect(container.read(overdueTasksProvider).value!.map((t) => t.id), [
        'a',
        'b',
      ]);
      tasks.addError(StateError('offline'));
      await Future<void>.delayed(Duration.zero);
      final failed = container.read(overdueTasksProvider);
      expect(failed.hasError, isTrue);
      expect(failed, isNot(isA<AsyncData<List<TaskItem>>>()));
      tasks.add([]);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(overdueTasksProvider).value, isEmpty);
    },
  );

  test(
    'date-only move preserves local time, cross-midnight duration and recurrence',
    () {
      const recurrence = TaskRecurrence(
        interval: 2,
        unit: TaskRecurrenceUnit.week,
        seriesId: 'series',
      );
      final existing = timed.withRecurrence(recurrence);
      final patch = taskDuePatch(
        task('task', existing),
        TaskDueResult.schedule(TaskSchedule.allDay(DateTime(2026, 9, 12))),
      );
      final moved = patch.schedule!;
      expect(moved.start!.toLocal(), DateTime(2026, 9, 12, 23, 30));
      expect(moved.end!.toLocal(), DateTime(2026, 9, 13, 0, 30));
      expect(moved.duration, timed.duration);
      expect(moved.recurrence!.toJson(), recurrence.toJson());
      final occurrence = taskDuePatch(
        task('occurrence', timed.withRecurrenceSeriesId('series')),
        TaskDueResult.schedule(TaskSchedule.allDay(DateTime(2026, 9, 12))),
      );
      expect(occurrence.schedule!.recurrenceSeriesId, 'series');
      final stillPast = taskDuePatch(
        task('past', timed),
        TaskDueResult.schedule(TaskSchedule.allDay(DateTime(2026, 9, 8))),
      );
      expect(isTaskOverdue(task('past', stillPast.schedule), midnight), isTrue);
    },
  );

  test(
    'cancel does not write; partial failure retains only failed selection',
    () async {
      final items = [task('a', timed), task('b', timed), task('c', timed)];
      final selection = TaskSelectionController(
        showDue: (_) async {},
        showProject: (_) async {},
        showLabels: (_) async {},
        showPriority: (_) async {},
        showMore: (_) async {},
        duplicate: (_) async {},
        delete: (_) async {},
      );
      addTearDown(selection.dispose);
      selection.updateVisible(items);
      expect(selection.selectedIds, isEmpty);
      selection.retainOnly(items.map((t) => t.id));
      final writes = <String>[];
      Future<void> update(String id, UpdateTaskPatch patch) async {
        writes.add(id);
        if (id == 'b') throw StateError('failed');
      }

      await applyTaskDueResult(items, null, updateTask: update);
      expect(writes, isEmpty);
      expect(selection.selectedIds, {'a', 'b', 'c'});
      final failed = await applyTaskDueResult(
        items,
        TaskDueResult.schedule(TaskSchedule.allDay(midnight)),
        updateTask: update,
      );
      selection.retainOnly(failed);
      expect(writes, ['a', 'b', 'c']);
      expect(selection.selectedIds, {'b'});
      expect(selection.active, isTrue);
      expect(
        taskDuePatch(items.first, const TaskDueResult.clear()).clearSchedule,
        isTrue,
      );
    },
  );
}

TaskItem task(
  String id,
  TaskSchedule? schedule, {
  bool completed = false,
  bool deleted = false,
}) => TaskItem(
  id: id,
  userId: 'user',
  content: id,
  projectId: 'project',
  priority: 4,
  status: completed ? 'completed' : 'open',
  completedFocusIntervals: 0,
  totalFocusSeconds: 0,
  orderKey: id,
  isDeleted: deleted,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  dueJson: schedule?.toJsonString(),
);
