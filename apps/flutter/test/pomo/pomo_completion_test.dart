import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/data/repositories/local/kanban_transition_coordinator.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';
import 'package:pomodoist/data/repositories/kanban/kanban_repository_impl.dart';
import 'package:pomodoist/domain/models/tasks/local_completion_event.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

void main() {
  test(
    'events follow commits, not rollback, repeated completion or reads',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();
      final queue = DriftOutboxService(db);
      final events = <LocalCompletionEvent>[];
      final coordinator = KanbanTransitionCoordinator(
        db,
        queue,
        onCompleted: events.add,
      );
      final tasks = DriftTaskRepository(
        db,
        queue,
        kanbanTransitions: coordinator,
      );
      final kanban = DriftKanbanRepository(
        db,
        syncQueue: queue,
        kanbanTransitions: coordinator,
      );
      final id = (await tasks.createTask(
        CreateTaskInput(content: 'Pomo test'),
      )).getOrThrow();
      await expectLater(
        ownerBoundTransaction(db, queue, () async {
          await coordinator.completeSubtreeInTransaction(
            id,
            timestamp: DateTime.now(),
          );
          expect(events, isEmpty);
          throw StateError('rollback');
        }),
        throwsStateError,
      );
      expect(events, isEmpty);
      (await tasks.completeTask(id)).getOrThrow();
      expect(events, hasLength(1));
      expect(events.single.entityId, id);
      (await tasks.completeTask(id)).getOrThrow();
      await tasks.watchTask(id).first;
      expect(events, hasLength(1));
      (await tasks.uncompleteTask(id)).getOrThrow();
      (await kanban.moveTask(id, statusId: kanbanStatusDoneId)).getOrThrow();
      expect(events, hasLength(2));
      expect(events[0].operationId, isNot(events[1].operationId));
    },
  );
}
