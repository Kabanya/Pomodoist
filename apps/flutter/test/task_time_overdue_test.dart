import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/app/task_time.dart';
import 'package:pomodoist/core/time/clock.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';

void main() {
  group('taskTimeStateProvider all-day schedules', () {
    test('marks a past all-day date as overdue', () {
      final localNow = DateTime(2026, 9, 7, 12);
      final now = localNow.toUtc();
      final container = ProviderContainer(
        overrides: [
          activeFocusRunProvider.overrideWith((ref) => Stream.value(null)),
          clockProvider.overrideWithValue(FixedClock(now)),
          taskTimeTickerProvider.overrideWith((ref) => Stream.value(now)),
        ],
      );
      addTearDown(container.dispose);

      final task = _taskWithSchedule(
        TaskSchedule.allDay(DateTime(2026, 9, 6)),
        now: now,
      );

      expect(
        container.read(taskTimeStateProvider(task)),
        TaskTimeState.overdue,
      );
    });

    test('does not mark today without a time as overdue', () {
      final localNow = DateTime(2026, 9, 7, 12);
      final now = localNow.toUtc();
      final container = ProviderContainer(
        overrides: [
          activeFocusRunProvider.overrideWith((ref) => Stream.value(null)),
          clockProvider.overrideWithValue(FixedClock(now)),
          taskTimeTickerProvider.overrideWith((ref) => Stream.value(now)),
        ],
      );
      addTearDown(container.dispose);

      final task = _taskWithSchedule(
        TaskSchedule.allDay(DateTime(2026, 9, 7)),
        now: now,
      );

      expect(container.read(taskTimeStateProvider(task)), isNull);
    });
  });
}

TaskItem _taskWithSchedule(TaskSchedule schedule, {required DateTime now}) {
  return TaskItem(
    id: 'task',
    userId: 'user',
    content: 'Task',
    projectId: 'project',
    priority: 4,
    dueJson: schedule.toJsonString(),
    status: 'open',
    completedFocusIntervals: 0,
    totalFocusSeconds: 0,
    orderKey: '1',
    isDeleted: false,
    createdAt: now,
    updatedAt: now,
  );
}
