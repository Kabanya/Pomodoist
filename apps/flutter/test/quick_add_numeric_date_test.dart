import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/projects/project_repository_impl.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/domain/models/planning/numeric_date_parser.dart';
import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/use_cases/quick_add/quick_add_use_case.dart';

void main() {
  test(
    'saved schedules match parsing and invalid dates suppress inherited schedules',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();
      final outbox = DriftOutboxService(db);
      final tasks = DriftTaskRepository(db, outbox);
      for (final (order, token, expected) in [
        (
          NumericDateOrder.dayMonthYear,
          '25.11.27',
          DateTime(2027, 11, 25, 9, 30),
        ),
        (
          NumericDateOrder.monthDayYear,
          '11/25/27',
          DateTime(2027, 11, 25, 9, 30),
        ),
        (
          NumericDateOrder.yearMonthDay,
          '25.11.27',
          DateTime(2025, 11, 27, 9, 30),
        ),
        (NumericDateOrder.dayMonthYear, '25.11.2', null),
      ]) {
        final parser = QuickAddParser(dateOrder: order);
        final useCase = QuickAddUseCase(
          parser: parser,
          taskRepository: tasks,
          projectRepository: DriftProjectRepository(db, outbox),
          now: () => DateTime(2026, 11, 6),
        );
        final id = (await useCase.createTask(
          'Report $token 09:30',
          defaultDate: DateTime(2026, 11, 6),
          defaultSchedule: TaskSchedule.allDay(DateTime(2026, 11, 6)),
        )).getOrThrow();
        final task = (await tasks.watchTask(id).first)!;
        if (expected == null) {
          expect(task.content, contains(token));
          expect(task.schedule, isNull);
        } else {
          expect(task.content, 'Report');
          expect(task.schedule!.start!.toLocal(), expected);
        }
      }
    },
  );
}
