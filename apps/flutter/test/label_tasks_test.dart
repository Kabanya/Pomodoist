import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/planning/data/task_decomposer.dart';
import 'package:pomodoist/features/tasks/presentation/widgets/quick_add_bar.dart';
import 'package:pomodoist/features/tasks/presentation/widgets/label_icon.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/core/sync/sync_queue_repository.dart';
import 'package:pomodoist/features/tasks/data/task_repository_impl.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';
import 'package:pomodoist/features/planning/data/quick_add_service.dart';
import 'package:pomodoist/features/planning/domain/quick_add_parser.dart';

void main() {
  late AppDatabase db;
  late DriftTaskRepository tasks;
  late DriftLabelRepository labels;
  late DriftSyncQueueRepository queue;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.ensureSeedData();
    queue = DriftSyncQueueRepository(db);
    tasks = DriftTaskRepository(db, queue);
    labels = DriftLabelRepository(db, queue);
  });
  tearDown(() => db.close());

  test(
    'label query reacts to links, completion and deletion across projects',
    () async {
      final id = await labels.createLabel('Review');
      final project = await DriftProjectRepository(
        db,
        queue,
      ).createProject('Work');
      final first = await tasks.createTask(
        const CreateTaskInput(content: 'First'),
      );
      final second = await tasks.createTask(
        CreateTaskInput(
          content: 'Second',
          projectId: project,
          labelNames: ['Review'],
        ),
      );
      final stream = StreamIterator(
        tasks.watchTasks(TaskQuery(kind: TaskQueryKind.label, labelId: id)),
      );
      addTearDown(stream.cancel);
      Future<void> expectIds(Set<String> expected) async {
        do {
          expect(
            await stream.moveNext().timeout(const Duration(seconds: 5)),
            isTrue,
          );
        } while (stream.current
                .map((t) => t.id)
                .toSet()
                .difference(expected)
                .isNotEmpty ||
            expected
                .difference(stream.current.map((t) => t.id).toSet())
                .isNotEmpty);
        expect(stream.current.map((t) => t.id).toSet(), expected);
      }

      await expectIds({second});
      await db
          .into(db.taskLabels)
          .insert(
            TaskLabelsCompanion.insert(
              taskId: first,
              labelId: id,
              createdAt: DateTime.now(),
            ),
          );
      await expectIds({first, second});
      await (db.delete(
        db.taskLabels,
      )..where((r) => r.taskId.equals(first) & r.labelId.equals(id))).go();
      await expectIds({second});
      await tasks.completeTask(second);
      await expectIds({});
      await tasks.uncompleteTask(second);
      await expectIds({second});
      await labels.deleteLabel(id);
      await expectIds({});
    },
  );

  test(
    'quick add keeps context label by ID with explicit labels and project',
    () async {
      final id = await labels.createLabel('Review');
      final service = QuickAddService(
        parser: const QuickAddParser(),
        taskRepository: tasks,
        projectRepository: DriftProjectRepository(db, queue),
      );
      final task = await service.createTask(
        'Check #Work @Review @Extra',
        labelId: id,
      );
      final links =
          await (db.select(db.taskLabels)..where(
                (r) => r.taskId.equals(task) & r.kind.equals(labelKindUser),
              ))
              .get();
      expect(links, hasLength(2));
      expect(links.map((r) => r.labelId), contains(id));
      expect(
        (await tasks.watchTask(task).first)!.projectId,
        isNot(inboxProjectId),
      );
      await labels.deleteLabel(id);
      await expectLater(
        service.createTask('Must not create', labelId: id),
        throwsStateError,
      );
      expect(await db.select(db.tasks).get(), hasLength(1));
    },
  );

  test(
    'voice drafts and subtasks inherit the label without losing metadata',
    () async {
      final id = await labels.createLabel('Review');
      final service = QuickAddService(
        parser: const QuickAddParser(),
        taskRepository: tasks,
        projectRepository: DriftProjectRepository(db, queue),
      );
      final created = await createVoiceQuickAddTasks(service, const [
        DecomposedTaskDraft(
          quickAdd: 'Parent #Work @Extra',
          subtasks: [DecomposedTaskDraft(quickAdd: 'Child @Review')],
        ),
        DecomposedTaskDraft(quickAdd: 'Another'),
      ], labelId: id);
      final tagged = await tasks
          .watchTasks(TaskQuery(kind: TaskQueryKind.label, labelId: id))
          .first;
      expect(tagged.map((t) => t.id).toSet(), created.toSet());
      final parent = tagged.singleWhere((t) => t.content == 'Parent');
      final child = tagged.singleWhere((t) => t.content == 'Child');
      expect(child.parentId, parent.id);
      expect(child.projectId, parent.projectId);
      expect(
        tagged.singleWhere((t) => t.content == 'Another').projectId,
        inboxProjectId,
      );
      expect(
        await (db.select(db.taskLabels)..where(
              (r) => r.taskId.equals(parent.id) & r.kind.equals(labelKindUser),
            ))
            .get(),
        hasLength(2),
      );
    },
  );

  test('unknown synchronized icons use the default label symbol', () {
    expect(labelIconData('future-icon'), labelIconData(null));
    expect(labelIconData('bookmark'), isNot(labelIconData(null)));
  });

  test(
    'label icons persist and enqueue updates without editing Kanban',
    () async {
      final id = await labels.createLabel('Review', icon: 'bookmark');
      expect((await labels.findByName('Review'))!.icon, 'bookmark');
      await labels.updateLabelIcon(id, 'bolt');
      expect((await labels.findByName('Review'))!.icon, 'bolt');
      expect(
        (await queue.watchPending().first).where(
          (c) => c.type == 'label.update',
        ),
        hasLength(1),
      );
      final status = await (db.select(
        db.labels,
      )..where((r) => r.kind.equals(labelKindKanbanStatus))).get();
      await expectLater(
        labels.updateLabelIcon(status.first.id, 'bolt'),
        throwsStateError,
      );
      await expectLater(
        labels.updateLabelIcon(id, 'folder'),
        throwsArgumentError,
      );
    },
  );
}
