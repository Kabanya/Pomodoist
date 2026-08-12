import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';
import 'package:pomodoist/features/tasks/presentation/widgets/upcoming_day_groups.dart';

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

TaskSchedule _timed(int year, int month, int day, int hour) =>
    TaskSchedule.timed(
      start: DateTime(year, month, day, hour),
      end: DateTime(year, month, day, hour, 30),
    );
