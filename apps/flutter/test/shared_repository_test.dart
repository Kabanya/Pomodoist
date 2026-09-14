import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/core/sync/sync_queue_repository.dart';
import 'package:pomodoist/features/collaboration/domain/collaboration_models.dart';
import 'package:pomodoist/features/tasks/data/task_repository_impl.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';

void main() {
  late AppDatabase db;
  late DriftTaskRepository tasks;
  late DriftProjectRepository projects;
  late String projectId;
  late String taskId;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.ensureSeedData();
    final queue = DriftSyncQueueRepository(db);
    tasks = DriftTaskRepository(db, queue);
    projects = DriftProjectRepository(db, queue);
    projectId = await projects.createProject('Shared');
    taskId = await tasks.createTask(
      CreateTaskInput(content: 'Original', projectId: projectId),
    );
    await db.delete(db.syncCommands).go();
    await db
        .into(db.sharedScopes)
        .insert(
          SharedScopesCompanion.insert(
            id: 'scope',
            dataJson: jsonEncode({
              'id': 'scope',
              'rootProjectId': projectId,
              'ownerId': 'owner',
              'role': 'observer',
            }),
          ),
        );
    await (db.update(db.projects)..where((p) => p.id.equals(projectId))).write(
      const ProjectsCompanion(scopeId: Value('scope')),
    );
    await (db.update(db.tasks)..where((t) => t.id.equals(taskId))).write(
      const TasksCompanion(scopeId: Value('scope')),
    );
    for (final label in await db.select(db.labels).get()) {
      await db
          .into(db.labels)
          .insert(
            label.copyWith(
              id: 'scope:${label.id}',
              scopeId: const Value('scope'),
            ),
          );
    }
    await (db.update(
      db.taskLabels,
    )..where((row) => row.taskId.equals(taskId))).write(
      const TaskLabelsCompanion(
        labelId: Value('scope:kanban-status-backlog-v1'),
      ),
    );
  });
  tearDown(() => db.close());

  test('observer writes fail before local content or queue changes', () async {
    await expectLater(
      tasks.updateTask(taskId, const UpdateTaskPatch(content: 'Forbidden')),
      throwsA(isA<CollaborationException>()),
    );
    expect((await tasks.watchTask(taskId).first)!.content, 'Original');
    expect(await db.select(db.syncCommands).get(), isEmpty);
    expect((await tasks.watchTask(taskId).first)!.canEdit, isFalse);
  });

  test(
    'observer display preferences queue privately without changing shared content',
    () async {
      await tasks.updateTask(taskId, const UpdateTaskPatch(isCollapsed: true));
      final row = await (db.select(
        db.tasks,
      )..where((row) => row.id.equals(taskId))).getSingle();
      expect(row.isCollapsed, isTrue);
      expect(row.content, 'Original');
      final command = await db.select(db.syncCommands).getSingle();
      expect(command.type, 'private.preferences');
      expect(command.scopeId, 'scope');
      expect(jsonDecode(command.payloadJson)['data'], {'isCollapsed': true});
    },
  );

  test(
    'an observer can place the shared root under a private project',
    () async {
      final private = await projects.createProject('Private');
      await db.delete(db.syncCommands).go();
      await projects.moveProject(projectId, parentId: private);
      final row = await (db.select(
        db.projects,
      )..where((row) => row.id.equals(projectId))).getSingle();
      expect(row.parentId, private);
      expect(row.scopeId, 'scope');
      final commands = await db.select(db.syncCommands).get();
      expect(
        commands
            .where((c) => c.scopeId == 'scope')
            .every((c) => c.type == 'private.preferences'),
        isTrue,
      );
    },
  );

  test(
    'personal planning includes only assigned shared tasks, project filters preserve creator',
    () async {
      final today = DateTime(2026, 9, 14);
      await (db.update(db.tasks)..where((row) => row.id.equals(taskId))).write(
        TasksCompanion(
          dueJson: Value(TaskSchedule.allDay(today).toJsonString()),
          createdBy: const Value('creator'),
        ),
      );
      expect(
        await tasks
            .watchTasks(TaskQuery(kind: TaskQueryKind.today, now: today))
            .first,
        isEmpty,
      );
      await (db.update(db.tasks)..where((row) => row.id.equals(taskId))).write(
        TasksCompanion(assigneeIdsJson: Value(jsonEncode([localUserId]))),
      );
      expect(
        (await tasks
                .watchTasks(TaskQuery(kind: TaskQueryKind.today, now: today))
                .first)
            .single
            .id,
        taskId,
      );
      expect(
        await tasks
            .watchTasks(
              TaskQuery(
                kind: TaskQueryKind.project,
                projectId: projectId,
                creatorId: 'someone',
              ),
            )
            .first,
        isEmpty,
      );
      expect(
        (await tasks
                .watchTasks(
                  TaskQuery(
                    kind: TaskQueryKind.project,
                    projectId: projectId,
                    creatorId: 'creator',
                  ),
                )
                .first)
            .single
            .createdBy,
        'creator',
      );
    },
  );

  test('members cannot move shared tasks to their private Inbox', () async {
    await (db.update(
      db.sharedScopes,
    )..where((s) => s.id.equals('scope'))).write(
      SharedScopesCompanion(
        dataJson: Value(
          jsonEncode({
            'id': 'scope',
            'rootProjectId': projectId,
            'ownerId': 'owner',
            'role': 'member',
          }),
        ),
      ),
    );
    await expectLater(
      tasks.moveTask(taskId, projectId: inboxProjectId),
      throwsA(isA<CollaborationException>()),
    );
    expect((await tasks.watchTask(taskId).first)!.projectId, projectId);
  });
  test(
    'shared create captures a stable payload before later offline edits',
    () async {
      await (db.update(
        db.sharedScopes,
      )..where((s) => s.id.equals('scope'))).write(
        SharedScopesCompanion(
          dataJson: Value(
            jsonEncode({
              'id': 'scope',
              'rootProjectId': projectId,
              'ownerId': 'owner',
              'role': 'member',
            }),
          ),
        ),
      );
      final id = await tasks.createTask(
        CreateTaskInput(content: 'Created text', projectId: projectId),
      );
      await tasks.updateTask(id, const UpdateTaskPatch(content: 'Later text'));
      final create = await (db.select(
        db.syncCommands,
      )..where((row) => row.type.equals('task.create'))).getSingle();
      final payload = jsonDecode(create.payloadJson) as Map;
      expect(payload['content'], 'Created text');
      expect(payload['scopeId'], 'scope');
      expect(payload['createdBy'], localUserId);
      expect(payload.containsKey('due'), isFalse);
    },
  );

  test(
    'shared completion uses shared Done and preserves personal Kanban anchors',
    () async {
      await (db.update(
        db.sharedScopes,
      )..where((s) => s.id.equals('scope'))).write(
        SharedScopesCompanion(
          dataJson: Value(
            jsonEncode({
              'id': 'scope',
              'rootProjectId': projectId,
              'ownerId': 'owner',
              'role': 'member',
            }),
          ),
        ),
      );
      await tasks.completeTask(taskId);
      final row = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(taskId))).getSingle();
      expect(row.status, 'completed');
      expect(row.completedBy, localUserId);
      final status = await (db.select(
        db.taskLabels,
      )..where((t) => t.taskId.equals(taskId))).getSingle();
      expect(status.labelId, 'scope:$kanbanStatusDoneId');
      final labels = await (db.select(
        db.labels,
      )..where((l) => l.systemKey.equals(kanbanSystemKeyDone))).get();
      expect(labels.length, 2);
      expect(
        (await db.select(db.syncCommands).get()).every(
          (c) => c.scopeId == 'scope',
        ),
        isTrue,
      );
    },
  );
}
