import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/core/sync/sync_queue_repository.dart';
import 'package:pomodoist/features/tasks/data/task_repository_impl.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';

void main() {
  test(
    'only manual task creation notifies the quick-add hint coordinator',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();
      var notifications = 0;
      final repository = DriftTaskRepository(
        db,
        DriftSyncQueueRepository(db),
        onUserTaskCreated: () async => notifications++,
      );

      await repository.createTask(
        const CreateTaskInput(content: 'Manual task'),
      );
      await repository.createTaskFromCalendar(
        RemoteCalendarTaskInput(
          content: 'Calendar task',
          schedule: TaskSchedule.allDay(DateTime(2026, 7, 9)),
          updatedAt: DateTime.utc(2026, 7, 9),
        ),
      );

      expect(notifications, 1);
    },
  );
}
