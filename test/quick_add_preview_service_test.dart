import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/core/sync/sync_queue_repository.dart';
import 'package:pomodoist/features/planning/data/quick_add_service.dart';
import 'package:pomodoist/features/planning/domain/quick_add_parser.dart';
import 'package:pomodoist/features/tasks/data/task_repository_impl.dart';

void main() {
  test(
    'preview and saved task share the clock, duration and inherited context',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();
      final queue = DriftSyncQueueRepository(db);
      final tasks = DriftTaskRepository(db, queue);
      final projects = DriftProjectRepository(db, queue);
      final projectId = await projects.createProject('Release');
      final now = DateTime(2035, 12, 31, 23, 59);
      const parser = QuickAddParser(
        defaultTimedBlockDuration: Duration(minutes: 45),
      );
      final service = QuickAddService(
        parser: parser,
        taskRepository: tasks,
        projectRepository: projects,
        now: () => now,
      );
      for (final source in ['Ship tomorrow 23:30 p2', 'Ship 23:30']) {
        final inheritedDate = DateTime(2036, 2, 3);
        final preview = parser
            .analyze(source, now: now, defaultDate: inheritedDate)
            .parsed;
        final id = await service.createTask(
          source,
          projectId: projectId,
          priority: 3,
          defaultDate: inheritedDate,
        );
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
