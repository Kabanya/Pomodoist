import 'package:pomodoist/data/repositories/projects/project_repository_impl.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/domain/use_cases/quick_add/quick_add_use_case.dart';
import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';

void main() {
  test(
    'preview and saved task share the clock, duration and inherited context',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();
      final queue = DriftOutboxService(db);
      final tasks = DriftTaskRepository(db, queue);
      final projects = DriftProjectRepository(db, queue);
      final projectId = await projects
          .createProject('Release')
          .then((result) => result.getOrThrow());
      final now = DateTime(2035, 12, 31, 23, 59);
      const parser = QuickAddParser(
        defaultTimedBlockDuration: Duration(minutes: 45),
      );
      final service = QuickAddUseCase(
        parser: parser,
        taskRepository: tasks,
        projectRepository: projects,
        now: () => now,
      );
      for (final source in [
        'Ship tomorrow 23:30 p2',
        'Ship 23:30',
        'Ship №Release tomorrow 23:30',
      ]) {
        final inheritedDate = DateTime(2036, 2, 3);
        final preview = parser
            .analyze(source, now: now, defaultDate: inheritedDate)
            .parsed;
        final id = await service
            .createTask(
              source,
              projectId: preview.project == null ? projectId : inboxProjectId,
              priority: 3,
              defaultDate: inheritedDate,
            )
            .then((result) => result.getOrThrow());
        final saved = (await tasks.watchTask(id).first)!;
        expect(saved.content, preview.content);
        expect(saved.projectId, projectId);
        expect(saved.priority, preview.priority ?? 3);
        expect(saved.schedule!.start, preview.schedule!.start);
        expect(saved.schedule!.end, preview.schedule!.end);
        expect(saved.schedule!.duration, const Duration(minutes: 45));
      }
    },
  );
}
