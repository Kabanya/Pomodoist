import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/view_models/calendar_view_model.dart';

TaskItem item(String id, TaskSchedule? schedule, {bool canEdit = true}) =>
    TaskItem(
      id: id,
      canEdit: canEdit,
      userId: 'u',
      content: id,
      projectId: 'p',
      priority: 1,
      status: 'pending',
      completedFocusIntervals: 0,
      totalFocusSeconds: 0,
      orderKey: id,
      isDeleted: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      dueJson: schedule?.toJsonString(),
    );

void main() {
  test(
    'calendar selection includes visible editable tasks once across all modes',
    () {
      final cross = item(
        'cross',
        TaskSchedule.timed(
          start: DateTime(2026, 9, 25, 23),
          end: DateTime(2026, 9, 27),
        ),
      );
      final allDay = item('day', TaskSchedule.allDay(DateTime(2026, 9, 25)));
      final unscheduled = item('unscheduled', null);
      final readOnly = item('read-only', null, canEdit: false);
      final elsewhere = item('elsewhere', TaskSchedule.allDay(DateTime(2027)));
      for (final mode in CalendarMode.values) {
        final view = buildCalendarPresentation(
          [cross, allDay, unscheduled, readOnly, elsewhere],
          const [],
          DateTime(2026, 9, 25),
          mode,
          firstWeekday: DateTime.monday,
        );
        expect(view.selectableTasks.map((task) => task.id).toSet(), {
          'cross',
          'day',
          'unscheduled',
        });
        expect(view.selectableTasks.length, 3);
      }
    },
  );

  test('sub-minute events retain a visible positive segment', () {
    final view = buildCalendarPresentation(
      [
        item(
          'short',
          TaskSchedule.timed(
            start: DateTime(2026, 9, 25, 10, 0, 10),
            end: DateTime(2026, 9, 25, 10, 0, 40),
          ),
        ),
      ],
      const [],
      DateTime(2026, 9, 25),
      CalendarMode.day,
      firstWeekday: DateTime.monday,
    );
    expect(view.days.single.events.single.startMinutes, 600);
    expect(view.days.single.events.single.endMinutes, 601);
  });

  test('cross-midnight event is clipped on both days with exclusive end', () {
    final crossing = item(
      'cross',
      TaskSchedule.timed(
        start: DateTime(2026, 9, 25, 23),
        end: DateTime(2026, 9, 27),
      ),
    );
    final view = buildCalendarPresentation(
      [crossing],
      const [],
      DateTime(2026, 9, 26),
      CalendarMode.week,
      firstWeekday: DateTime.monday,
    );
    final friday = view.days.firstWhere((d) => d.date.day == 25);
    final saturday = view.days.firstWhere((d) => d.date.day == 26);
    final sunday = view.days.firstWhere((d) => d.date.day == 27);
    expect(friday.events.single.startMinutes, 1380);
    expect(friday.events.single.endMinutes, 1440);
    expect(saturday.events.single.startMinutes, 0);
    expect(saturday.events.single.endMinutes, 1440);
    expect(sunday.events, isEmpty);
  });

  test('overlap lanes share width while touching intervals reuse a lane', () {
    final tasks = [
      item(
        'a',
        TaskSchedule.timed(
          start: DateTime(2026, 9, 25, 9),
          end: DateTime(2026, 9, 25, 11),
        ),
      ),
      item(
        'b',
        TaskSchedule.timed(
          start: DateTime(2026, 9, 25, 10),
          end: DateTime(2026, 9, 25, 12),
        ),
      ),
      item(
        'c',
        TaskSchedule.timed(
          start: DateTime(2026, 9, 25, 12),
          end: DateTime(2026, 9, 25, 13),
        ),
      ),
    ];
    final day = buildCalendarPresentation(
      tasks,
      const [],
      DateTime(2026, 9, 25),
      CalendarMode.day,
      firstWeekday: DateTime.monday,
    ).days.single;
    expect(day.events.map((e) => e.lane).toList(), [0, 1, 0]);
    expect(day.events.map((e) => e.laneCount).toList(), [2, 2, 1]);
  });

  test(
    'month includes 42 dates and project filter keeps only selected tasks',
    () {
      final view = buildCalendarPresentation(
        [
          item('one', TaskSchedule.allDay(DateTime(2026, 9, 1))),
          item('loose', null),
        ],
        const [],
        DateTime(2026, 9, 25),
        CalendarMode.month,
        firstWeekday: DateTime.monday,
        projectId: 'other',
      );
      expect(view.days.length, 42);
      expect(view.days.first.date, DateTime(2026, 8, 31));
      expect(view.unscheduled, isEmpty);
      expect(view.days.expand((d) => d.tasks), isEmpty);
    },
  );

  test('routine keeps continuations visible outside start-time periods', () {
    final original = item(
      'started',
      TaskSchedule.timed(
        start: DateTime(2026, 9, 25, 10),
        end: DateTime(2026, 9, 26, 10),
      ),
    );
    final sameDay = item(
      'outside',
      TaskSchedule.timed(
        start: DateTime(2026, 9, 26, 20),
        end: DateTime(2026, 9, 26, 21),
      ),
    );
    final view = buildCalendarPresentation(
      [original, sameDay],
      const [],
      DateTime(2026, 9, 26),
      CalendarMode.routine,
      firstWeekday: DateTime.monday,
    );
    final settings = CalendarSettings(
      periods: [
        CalendarPeriod(name: 'Morning', startMinutes: 540, endMinutes: 720),
      ],
    );
    final saturday = groupCalendarRoutineDays(
      view,
      settings,
    ).firstWhere((d) => d.day.date.day == 26);
    expect(saturday.periods.single, isEmpty);
    expect(saturday.outside.map((task) => task.id), ['started', 'outside']);
  });
}
