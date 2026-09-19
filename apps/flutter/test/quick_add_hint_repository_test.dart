import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

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
        DriftOutboxService(db),
        onUserTaskCreated: () async => notifications++,
      );

      await repository
          .createTask(const CreateTaskInput(content: 'Manual task'))
          .then((result) => result.getOrThrow());
      await repository
          .createTaskFromCalendar(
            RemoteCalendarTaskInput(
              content: 'Calendar task',
              schedule: TaskSchedule.allDay(DateTime(2026, 7, 9)),
              updatedAt: DateTime.utc(2026, 7, 9),
            ),
          )
          .then((result) => result.getOrThrow());

      expect(notifications, 1);
    },
  );
}
