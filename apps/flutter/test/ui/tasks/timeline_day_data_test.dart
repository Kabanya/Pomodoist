import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/ui/tasks/view_models/timeline_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/view_models/timeline_day_data.dart';

void main() {
  final day = DateTime(2026, 9, 20);
  const visibleHours = TimelineVisibleHours(
    startMinutes: 9 * 60,
    endMinutes: 17 * 60,
  );

  test('day projection uses live rows over retained animation snapshots', () {
    final retained = _task('same', schedule: _timed(2026, 9, 20, 10));
    final live = _task('same', schedule: _timed(2026, 9, 20, 11));
    final container = ProviderContainer(
      overrides: [
        timelineViewModelProvider.overrideWith(
          () => _TimelineSnapshot((
            now: day,
            tasks: AsyncData([live]),
            projects: const AsyncData([]),
            visibleHours: visibleHours,
            hourWidth: 60,
            collapsed: const {},
            temporary: const {},
          )),
        ),
      ],
    );
    addTearDown(container.dispose);
    final projection = container.read(
      timelineDayPresentationProvider((day: day, retained: [retained])),
    );
    expect(projection.data.visibleTimed.single, same(live));
    expect(projection.tasksById['same'], same(live));
    expect(() => projection.tasksById.clear(), throwsUnsupportedError);
  });

  group('buildTimelineDayData', () {
    test('splits the selected day and orders each section', () {
      final data = buildTimelineDayData(
        [
          _task('all-day', schedule: TaskSchedule.allDay(day), dayOrder: 1),
          _task('ten', schedule: _timed(2026, 9, 20, 10)),
          _task('nine-thirty', schedule: _timed(2026, 9, 20, 9, minute: 30)),
          _task('before', schedule: _timed(2026, 9, 20, 8)),
          _task('after', schedule: _timed(2026, 9, 20, 17)),
          _task('done', schedule: _timed(2026, 9, 20, 10), status: 'completed'),
          _task('other-day', schedule: _timed(2026, 9, 21, 10)),
          _task('unscheduled'),
        ],
        day: day,
        visibleHours: visibleHours,
      );

      expect(data.allDay.map((task) => task.id), ['all-day']);
      expect(data.visibleTimed.map((task) => task.id), ['nine-thirty', 'ten']);
      expect(data.beforeHours.map((task) => task.id), ['before']);
      expect(data.afterHours.map((task) => task.id), ['after']);
      expect(data.timedByProject.keys, {'project'});
      expect(data.timedByProject['project']!.map((task) => task.id), [
        'nine-thirty',
        'ten',
      ]);
    });

    test('uses the local display date at same-day timezone boundaries', () {
      final data = buildTimelineDayData(
        [
          _task('late', schedule: _timed(2026, 9, 20, 23, minute: 59)),
          _task('next-day', schedule: _timed(2026, 9, 21, 0)),
          _task('all-day', schedule: TaskSchedule.allDay(day)),
        ],
        day: day,
        visibleHours: const TimelineVisibleHours(
          startMinutes: 0,
          endMinutes: 24 * 60,
        ),
      );

      final included = {
        for (final task in [
          ...data.allDay,
          ...data.visibleTimed,
          ...data.beforeHours,
          ...data.afterHours,
        ])
          task.id,
      };
      expect(included, {'late', 'all-day'});
      expect(data.visibleTimed.single.id, 'late');
    });

    test('keeps recurring occurrences grouped by their occurrence day', () {
      final data = buildTimelineDayData(
        [
          _task(
            'series',
            schedule: TaskSchedule.allDay(day, recurrenceSeriesId: 'series-1'),
          ),
        ],
        day: day,
        visibleHours: visibleHours,
      );

      expect(data.allDay.single.id, 'series');
      expect(data.allDay.single.schedule!.isRecurringOccurrence, isTrue);
    });

    test('groups tasks by project id even when the project is missing', () {
      final data = buildTimelineDayData(
        [
          _task('known', schedule: _timed(2026, 9, 20, 10)),
          _task(
            'orphan',
            schedule: _timed(2026, 9, 20, 11),
            projectId: 'ghost',
          ),
        ],
        day: day,
        visibleHours: visibleHours,
      );

      expect(data.timedByProject.keys.toSet(), {'project', 'ghost'});
      expect(data.timedByProject['ghost']!.single.id, 'orphan');
      expect(data.visibleTimed.map((task) => task.id), ['known', 'orphan']);
    });

    test(
      'orders equal start times by day order, order key, then input order',
      () {
        final tasks = [
          _task('null-order', schedule: _timed(2026, 9, 20, 10)),
          _task('late-day', schedule: _timed(2026, 9, 20, 10), dayOrder: 2),
          _task(
            'order-b',
            schedule: _timed(2026, 9, 20, 10),
            dayOrder: 1,
            orderKey: 'b',
          ),
          _task(
            'order-a',
            schedule: _timed(2026, 9, 20, 10),
            dayOrder: 1,
            orderKey: 'a',
          ),
          _task(
            'tie-b',
            schedule: _timed(2026, 9, 20, 10),
            dayOrder: 1,
            orderKey: 'same',
          ),
          _task(
            'tie-a',
            schedule: _timed(2026, 9, 20, 10),
            dayOrder: 1,
            orderKey: 'same',
          ),
        ];
        final data = buildTimelineDayData(
          tasks,
          day: day,
          visibleHours: visibleHours,
        );

        expect(data.visibleTimed.map((task) => task.id), [
          'order-a',
          'order-b',
          'tie-b',
          'tie-a',
          'late-day',
          'null-order',
        ]);

        final repeated = buildTimelineDayData(
          tasks,
          day: day,
          visibleHours: visibleHours,
        );
        expect(
          repeated.visibleTimed.map((task) => task.id),
          data.visibleTimed.map((task) => task.id),
        );
      },
    );

    test('exposes unmodifiable task lists and project groups', () {
      final data = buildTimelineDayData(
        [_task('known', schedule: _timed(2026, 9, 20, 10))],
        day: day,
        visibleHours: visibleHours,
      );

      expect(
        () => data.visibleTimed.add(data.visibleTimed.first),
        throwsUnsupportedError,
      );
      expect(
        () => data.timedByProject['project']!.add(data.visibleTimed.first),
        throwsUnsupportedError,
      );
    });
  });
}

TaskItem _task(
  String id, {
  TaskSchedule? schedule,
  String projectId = 'project',
  int? dayOrder,
  String? orderKey,
  String status = 'open',
}) {
  final now = DateTime.utc(2026);
  return TaskItem(
    id: id,
    userId: 'user',
    content: id,
    projectId: projectId,
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

TaskSchedule _timed(int year, int month, int day, int hour, {int minute = 0}) {
  final start = DateTime(year, month, day, hour, minute);
  return TaskSchedule.timed(
    start: start,
    end: start.add(const Duration(minutes: 30)),
  );
}

class _TimelineSnapshot extends TimelineViewModel {
  _TimelineSnapshot(this.snapshot);
  final TimelineState snapshot;
  @override
  TimelineState build() => snapshot;
}
