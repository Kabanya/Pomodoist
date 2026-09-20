import 'package:pomodoist/domain/models/planning/task_decomposition.dart';
import 'package:pomodoist/data/repositories/projects/project_repository_impl.dart';
import 'package:pomodoist/data/repositories/labels/label_repository_impl.dart';
import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/tasks/widgets/label_icon.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/use_cases/quick_add/quick_add_use_case.dart';
import 'package:pomodoist/domain/use_cases/quick_add/voice_quick_add_use_case.dart';
import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';

void main() {
  late AppDatabase db;
  late DriftTaskRepository tasks;
  late DriftLabelRepository labels;
  late DriftOutboxService queue;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.ensureSeedData();
    queue = DriftOutboxService(db);
    tasks = DriftTaskRepository(db, queue);
    labels = DriftLabelRepository(db, queue);
  });
  tearDown(() => db.close());

  test(
    'label query reacts to links, completion and deletion across projects',
    () async {
      final id = await labels
          .createLabel('Review')
          .then((result) => result.getOrThrow());
      final project = await DriftProjectRepository(
        db,
        queue,
      ).createProject('Work').then((result) => result.getOrThrow());
      final first = await tasks
          .createTask(CreateTaskInput(content: 'First'))
          .then((result) => result.getOrThrow());
      final second = await tasks
          .createTask(
            CreateTaskInput(
              content: 'Second',
              projectId: project,
              labelNames: ['Review'],
            ),
          )
          .then((result) => result.getOrThrow());
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
      await tasks.completeTask(second).then((result) => result.getOrThrow());
      await expectIds({});
      await tasks.uncompleteTask(second).then((result) => result.getOrThrow());
      await expectIds({second});
      await labels.deleteLabel(id).then((result) => result.getOrThrow());
      await expectIds({});
    },
  );

  test(
    'quick add keeps context label by ID with explicit labels and project',
    () async {
      final id = await labels
          .createLabel('Review')
          .then((result) => result.getOrThrow());
      final service = QuickAddUseCase(
        parser: const QuickAddParser(),
        taskRepository: tasks,
        projectRepository: DriftProjectRepository(db, queue),
      );
      final task = await service
          .createTask('Check #Work @Review @Extra', labelId: id)
          .then((result) => result.getOrThrow());
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
      await labels.deleteLabel(id).then((result) => result.getOrThrow());
      await expectLater(
        service
            .createTask('Must not create', labelId: id)
            .then((result) => result.getOrThrow()),
        throwsStateError,
      );
      expect(await db.select(db.tasks).get(), hasLength(1));
    },
  );

  test(
    'voice drafts and subtasks inherit the label without losing metadata',
    () async {
      final id = await labels
          .createLabel('Review')
          .then((result) => result.getOrThrow());
      final service = QuickAddUseCase(
        parser: const QuickAddParser(),
        taskRepository: tasks,
        projectRepository: DriftProjectRepository(db, queue),
      );
      final created =
          await VoiceQuickAddUseCase(
            quickAdd: service,
            runLocalTransaction: db.transaction,
          )([
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
      final id = await labels
          .createLabel('Review', icon: 'bookmark')
          .then((result) => result.getOrThrow());
      expect(
        (await labels
                .findByName('Review')
                .then((result) => result.getOrThrow()))!
            .icon,
        'bookmark',
      );
      await labels
          .updateLabelIcon(id, 'bolt')
          .then((result) => result.getOrThrow());
      expect(
        (await labels
                .findByName('Review')
                .then((result) => result.getOrThrow()))!
            .icon,
        'bolt',
      );
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
        labels
            .updateLabelIcon(status.first.id, 'bolt')
            .then((result) => result.getOrThrow()),
        throwsStateError,
      );
      await expectLater(
        labels
            .updateLabelIcon(id, 'folder')
            .then((result) => result.getOrThrow()),
        throwsArgumentError,
      );
    },
  );
}
