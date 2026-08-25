import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/task_time.dart';
import 'package:pomodoist/app/theme/app_theme.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';

void main() {
  final schedule = TaskSchedule.timed(
    start: DateTime.utc(2026, 7, 5, 14),
    end: DateTime.utc(2026, 7, 5, 14, 30),
  );

  test('task time state gives completed and active focus priority', () {
    expect(
      classifyTaskTimeState(
        isCompleted: true,
        taskId: 'task',
        activeFocusTaskId: 'task',
        schedule: schedule,
        now: DateTime.utc(2026, 7, 5, 13),
      ),
      TaskTimeState.completed,
    );
    expect(
      classifyTaskTimeState(
        isCompleted: false,
        taskId: 'task',
        activeFocusTaskId: 'task',
        schedule: schedule,
        now: DateTime.utc(2026, 7, 5, 13),
      ),
      TaskTimeState.focused,
    );
  });

  test('task time state includes start and excludes end', () {
    expect(
      classifyTaskTimeState(
        isCompleted: false,
        taskId: 'task',
        schedule: schedule,
        now: DateTime.utc(2026, 7, 5, 13, 59, 59),
      ),
      TaskTimeState.future,
    );
    expect(
      classifyTaskTimeState(
        isCompleted: false,
        taskId: 'task',
        schedule: schedule,
        now: DateTime.utc(2026, 7, 5, 14),
      ),
      TaskTimeState.current,
    );
    expect(
      classifyTaskTimeState(
        isCompleted: false,
        taskId: 'task',
        schedule: schedule,
        now: DateTime.utc(2026, 7, 5, 14, 30),
      ),
      TaskTimeState.overdue,
    );
  });

  test('display mode parsing falls back to smart', () {
    expect(
      TaskTimeDisplayMode.fromStorageValue('range'),
      TaskTimeDisplayMode.range,
    );
    expect(
      TaskTimeDisplayMode.fromStorageValue('startOnly'),
      TaskTimeDisplayMode.startOnly,
    );
    expect(
      TaskTimeDisplayMode.fromStorageValue('unknown'),
      TaskTimeDisplayMode.smart,
    );
  });

  test('palette maps each time state to its semantic color', () {
    final colors = AppTheme.light().extension<AppThemePalette>()!;

    expect(colors.taskTimeColor(TaskTimeState.future), colors.info);
    expect(colors.taskTimeColor(TaskTimeState.focused), colors.success);
    expect(colors.taskTimeColor(TaskTimeState.current), colors.warning);
    expect(colors.taskTimeColor(TaskTimeState.overdue), colors.accent);
    expect(colors.taskTimeColor(TaskTimeState.completed), colors.mutedText);
  });
}
