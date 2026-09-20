import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/view_models/upcoming_day_groups.dart';

void main() {
  group('buildUpcomingDayGroups', () {
    test('groups scheduled tasks into chronological local days', () {
      final groups = buildUpcomingDayGroups([
        _task('later', schedule: _allDay(2026, 7, 12)),
        _task('unscheduled'),
        _task('earlier', schedule: _allDay(2026, 7, 10)),
      ]);

      expect(groups.map((group) => group.date), [
        DateTime(2026, 7, 10),
        DateTime(2026, 7, 12),
      ]);
      expect(groups.map((group) => group.rows.single.task.id), [
        'earlier',
        'later',
      ]);
    });

    test('sorts siblings by day order, order key, then id', () {
      final groups = buildUpcomingDayGroups([
        _task('null-order', schedule: _allDay(2026, 7, 10), orderKey: 'a'),
        _task(
          'day-two',
          schedule: _allDay(2026, 7, 10),
          dayOrder: 2,
          orderKey: 'a',
        ),
        _task(
          'tie-b',
          schedule: _allDay(2026, 7, 10),
          dayOrder: 1,
          orderKey: 'same',
        ),
        _task(
          'tie-a',
          schedule: _allDay(2026, 7, 10),
          dayOrder: 1,
          orderKey: 'same',
        ),
      ]);

      expect(groups.single.rows.map((row) => row.task.id), [
        'tie-a',
        'tie-b',
        'day-two',
        'null-order',
      ]);
    });

    test('does not reorder timed and all-day siblings by time', () {
      final groups = buildUpcomingDayGroups([
        _task('early', schedule: _timed(2026, 7, 10, 8), dayOrder: 3),
        _task('all-day', schedule: _allDay(2026, 7, 10), dayOrder: 2),
        _task('late', schedule: _timed(2026, 7, 10, 18), dayOrder: 1),
      ]);

      expect(groups.single.rows.map((row) => row.task.id), [
        'late',
        'all-day',
        'early',
      ]);
    });

    test(
      'shows completed root trees before open root trees without splitting children',
      () {
        final groups = buildUpcomingDayGroups([
          _task('open-parent', dayOrder: 1, schedule: _allDay(2026, 7, 10)),
          _task(
            'done-child',
            parentId: 'open-parent',
            status: 'completed',
            schedule: _allDay(2026, 7, 10),
          ),
          _task(
            'done-root',
            dayOrder: 2,
            status: 'completed',
            schedule: _allDay(2026, 7, 10),
          ),
        ]);

        expect(
          groups.single.rows.map((row) => (row.task.id, row.depth)).toList(),
          [('done-root', 0), ('open-parent', 0), ('done-child', 1)],
        );
      },
    );

    test('orders completed and open tasks by local display day', () {
      final groups = buildUpcomingDayGroups([
        _task(
          'past-completed',
          status: 'completed',
          schedule: _allDay(2026, 7, 9),
        ),
        _task('today-open', schedule: _timed(2026, 7, 10, 8)),
        _task(
          'future-completed',
          status: 'completed',
          schedule: _allDay(2026, 7, 11),
        ),
      ]);

      expect(groups.map((group) => group.date), [
        DateTime(2026, 7, 9),
        DateTime(2026, 7, 10),
        DateTime(2026, 7, 11),
      ]);
      expect(groups.map((group) => group.rows.single.task.id), [
        'past-completed',
        'today-open',
        'future-completed',
      ]);
    });

    test('preserves nesting when parent and child share a day', () {
      final groups = buildUpcomingDayGroups([
        _task('child', parentId: 'parent', schedule: _allDay(2026, 7, 10)),
        _task('parent', schedule: _allDay(2026, 7, 10)),
        _task('grandchild', parentId: 'child', schedule: _allDay(2026, 7, 10)),
      ]);

      expect(
        groups.single.rows.map((row) => (row.task.id, row.depth)).toList(),
        [('parent', 0), ('child', 1), ('grandchild', 2)],
      );
    });

    test('promotes a child scheduled on another day to a root', () {
      final groups = buildUpcomingDayGroups([
        _task('parent', schedule: _allDay(2026, 7, 10)),
        _task('child', parentId: 'parent', schedule: _allDay(2026, 7, 11)),
      ]);

      expect(groups[0].rows.single.depth, 0);
      expect(groups[1].rows.single.task.id, 'child');
      expect(groups[1].rows.single.depth, 0);
    });

    test('inserts an empty selected day in chronological position', () {
      final groups = buildUpcomingDayGroups([
        _task('before', schedule: _allDay(2026, 7, 10)),
        _task('after', schedule: _allDay(2026, 7, 12)),
      ], selectedDate: DateTime(2026, 7, 11, 18, 30));

      expect(groups.map((group) => group.date), [
        DateTime(2026, 7, 10),
        DateTime(2026, 7, 11),
        DateTime(2026, 7, 12),
      ]);
      expect(groups[1].rows, isEmpty);
      expect(groups[1].isSynthetic, isTrue);
      expect(groups[0].isSynthetic, isFalse);
    });

    test(
      'hides days before visibleFromDate and retains an empty selection',
      () {
        final groups = buildUpcomingDayGroups(
          [
            _task('before', schedule: _allDay(2026, 7, 10)),
            _task('after', schedule: _allDay(2026, 7, 12)),
          ],
          selectedDate: DateTime(2026, 7, 11, 18, 30),
          visibleFromDate: DateTime(2026, 7, 11),
        );

        expect(groups.map((group) => group.date), [
          DateTime(2026, 7, 11),
          DateTime(2026, 7, 12),
        ]);
        expect(groups.first.rows, isEmpty);
        expect(groups.first.isSynthetic, isTrue);
        expect(groups.last.rows.single.task.id, 'after');
      },
    );

    test('keeps every task when malformed parent links contain cycles', () {
      final groups = buildUpcomingDayGroups([
        _task(
          'b',
          parentId: 'a',
          schedule: _allDay(2026, 7, 10),
          orderKey: 'b',
        ),
        _task(
          'a',
          parentId: 'b',
          schedule: _allDay(2026, 7, 10),
          orderKey: 'a',
        ),
        _task(
          'self',
          parentId: 'self',
          schedule: _allDay(2026, 7, 10),
          orderKey: 'c',
        ),
      ]);

      final rows = groups.single.rows;
      expect(rows.map((row) => row.task.id).toSet(), {'a', 'b', 'self'});
      expect(rows, hasLength(3));
      expect(rows.first.depth, 0);
    });

    test('promotes a task with a missing parent to a root', () {
      final groups = buildUpcomingDayGroups([
        _task('orphan', parentId: 'missing', schedule: _allDay(2026, 7, 10)),
        _task('root', schedule: _allDay(2026, 7, 10)),
      ]);

      expect(
        groups.single.rows.map((row) => (row.task.id, row.depth)).toList(),
        [('orphan', 0), ('root', 0)],
      );
    });

    test('groups timed tasks by their local display day at timezone edges', () {
      final groups = buildUpcomingDayGroups([
        _task('late', schedule: _timed(2026, 7, 10, 23, minute: 45)),
        _task('next-day', schedule: _timed(2026, 7, 11, 0, minute: 15)),
      ]);

      expect(groups.map((group) => group.date), [
        DateTime(2026, 7, 10),
        DateTime(2026, 7, 11),
      ]);
      expect(groups[0].rows.single.task.id, 'late');
      expect(groups[1].rows.single.task.id, 'next-day');
    });

    test('keeps completed tasks on their scheduled local day', () {
      final groups = buildUpcomingDayGroups([
        _task(
          'done',
          status: 'completed',
          dayOrder: 2,
          schedule: _allDay(2026, 7, 10),
        ),
        _task('open', dayOrder: 1, schedule: _allDay(2026, 7, 10)),
      ]);

      expect(groups, hasLength(1));
      expect(groups.single.date, DateTime(2026, 7, 10));
      expect(groups.single.rows.map((row) => row.task.id), ['done', 'open']);
    });

    test('groups recurring occurrences by their occurrence day', () {
      final groups = buildUpcomingDayGroups([
        _task(
          'series',
          schedule: TaskSchedule.allDay(
            DateTime(2026, 7, 10),
            recurrenceSeriesId: 'series-1',
          ),
        ),
      ]);

      expect(groups.single.date, DateTime(2026, 7, 10));
      expect(
        groups.single.rows.single.task.schedule!.isRecurringOccurrence,
        isTrue,
      );
    });

    test('stable ordering is identical across repeated builds', () {
      final tasks = [
        _task('b', schedule: _allDay(2026, 7, 10), orderKey: 'same'),
        _task('a', schedule: _allDay(2026, 7, 10), orderKey: 'same'),
        _task('c', schedule: _allDay(2026, 7, 10), dayOrder: 0),
      ];
      final first = buildUpcomingDayGroups(tasks);
      final second = buildUpcomingDayGroups(tasks);

      expect(
        first.single.rows.map((row) => row.task.id).toList(),
        second.single.rows.map((row) => row.task.id).toList(),
      );
      expect(first.single.rows.map((row) => row.task.id), ['c', 'a', 'b']);
    });

    test('selected empty day remains available for task creation', () {
      final day = DateTime(2026, 9, 20);
      final groups = buildUpcomingDayGroups(const [], selectedDate: day);
      expect(groups, hasLength(1));
      expect(groups.single.date, day);
      expect(groups.single.isSynthetic, isTrue);
      expect(groups.single.rows, isEmpty);
    });
  });
}

TaskItem _task(
  String id, {
  TaskSchedule? schedule,
  String? parentId,
  int? dayOrder,
  String? orderKey,
  String status = 'open',
}) {
  final now = DateTime.utc(2026);
  return TaskItem(
    id: id,
    userId: 'user',
    content: id,
    projectId: 'project',
    parentId: parentId,
    priority: 4,
    dueJson: schedule?.toJsonString(),
    status: status,
    completedFocusIntervals: 0,
    totalFocusSeconds: 0,
    orderKey: orderKey ?? id,
    dayOrder: dayOrder,
    isDeleted: false,
    createdAt: now,
    updatedAt: now,
  );
}

TaskSchedule _allDay(int year, int month, int day) =>
    TaskSchedule.allDay(DateTime(year, month, day));

TaskSchedule _timed(int year, int month, int day, int hour, {int minute = 0}) {
  final start = DateTime(year, month, day, hour, minute);
  return TaskSchedule.timed(
    start: start,
    end: start.add(const Duration(minutes: 30)),
  );
}
