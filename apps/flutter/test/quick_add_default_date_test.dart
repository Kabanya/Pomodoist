import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/projects/project_repository_impl.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';
import 'package:pomodoist/domain/use_cases/quick_add/quick_add_use_case.dart';

void main() {
  for (final (input, defaultDate, expected) in [
    ('Report', DateTime(2026, 11, 6), DateTime(2026, 11, 6)),
    ('Report', DateTime(2026, 11, 13), DateTime(2026, 11, 13)),
    ('Report 2026-11-20', DateTime(2026, 11, 13), DateTime(2026, 11, 20)),
    ('Report', null, null),
    ('Сегодня Report', null, DateTime(2026, 11, 6)),
    ('2026-11-13 Report', null, DateTime(2026, 11, 13)),
  ]) {
    test('saves $input with default $defaultDate as an all-day task', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();
      final outbox = DriftOutboxService(db);
      final repository = DriftTaskRepository(db, outbox);
      final useCase = QuickAddUseCase(
        parser: const QuickAddParser(),
        taskRepository: repository,
        projectRepository: DriftProjectRepository(db, outbox),
        now: () => DateTime(2026, 11, 6, 17, 45),
      );
      final id = (await useCase.createTask(
        input,
        defaultDate: defaultDate,
      )).getOrThrow();
      for (final dateOnly in ['Сегодня ', '2026-11-13 ']) {
        await expectLater(
          () async => (await useCase.createTask(dateOnly)).getOrThrow(),
          throwsArgumentError,
        );
      }
      expect(await db.select(db.tasks).get(), hasLength(1));
      final task = await repository.watchTask(id).first;
      expect(task, isNotNull);
      expect(task!.content, 'Report');
      expect(task.schedule?.displayDate, expected);
      if (expected != null) {
        expect(task.schedule!.isAllDay, isTrue);
        expect(task.schedule!.start, isNull);
      } else {
        expect(task.schedule, isNull);
      }
    });
  }

  test('localized explicit date overrides a conflicting default date', () {
    final parsed = const QuickAddParser().parse(
      'Подготовить отчёт завтра 08:15',
      now: DateTime(2026, 5, 1, 12),
      defaultDate: DateTime(2026, 5, 9),
    );

    expect(parsed.dueDate, DateTime(2026, 5, 2));
    expect(parsed.schedule!.start!.toLocal(), DateTime(2026, 5, 2, 8, 15));
  });
}
