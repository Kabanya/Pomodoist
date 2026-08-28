import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart' as migrations;
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/core/db/app_database.dart';

import 'drift_schema/schema.dart' as v3_schema;

void main() {
  const settingsId = 'kanban-settings-primary-v1';
  const backlogId = 'kanban-status-backlog-v1';
  const todoId = 'kanban-status-todo-v1';
  const inProgressId = 'kanban-status-in-progress-v1';
  const doneId = 'kanban-status-done-v1';

  group('schema v5', () {
    late AppDatabase db;
    migrations.InitializedSchema? initializedV3;

    tearDown(() async {
      await db.close();
      initializedV3?.close();
      initializedV3 = null;
    });

    test('fresh database creates compact Kanban schema and index', () async {
      db = AppDatabase(NativeDatabase.memory());

      expect(db.schemaVersion, 5);
      if (db.schemaVersion != 5) {
        return;
      }
      await db
          .customSelect('SELECT available_at FROM sync_commands LIMIT 0')
          .get();
      await db
          .customSelect('SELECT kind, system_key FROM labels LIMIT 0')
          .get();
      await db.customSelect('SELECT kind FROM task_labels LIMIT 0').get();
      await db.customSelect('SELECT * FROM kanban_settings LIMIT 0').get();

      final index = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE type = 'index' "
            "AND name = 'task_labels_one_kanban_status_per_task'",
          )
          .getSingleOrNull();
      expect(index, isNotNull);
      expect(
        index!.read<String>('sql'),
        contains("WHERE kind = 'kanbanStatus'"),
      );
    });

    test('fresh schema rejects invalid label and assignment kinds', () async {
      db = AppDatabase(NativeDatabase.memory());

      await expectLater(
        db.customStatement(
          "INSERT INTO labels "
          "(id, user_id, name, kind, order_key, created_at, updated_at) "
          "VALUES ('invalid-label-kind', '$localUserId', 'Invalid', "
          "'invalid', 'a', 0, 0)",
        ),
        _throwsCheckConstraint,
      );
      await expectLater(
        db.customStatement(
          "INSERT INTO task_labels (task_id, label_id, kind, created_at) "
          "VALUES ('task', 'label', 'invalid', 0)",
        ),
        _throwsCheckConstraint,
      );
    });

    test('fresh schema rejects invalid and duplicate system keys', () async {
      db = AppDatabase(NativeDatabase.memory());

      await expectLater(
        db.customStatement(
          "INSERT INTO labels "
          "(id, user_id, name, kind, system_key, order_key, created_at, updated_at) "
          "VALUES ('invalid-system-key', '$localUserId', 'Invalid', "
          "'kanbanStatus', 'invalid', 'a', 0, 0)",
        ),
        _throwsCheckConstraint,
      );
      await db.customStatement(
        "INSERT INTO labels "
        "(id, user_id, name, kind, system_key, order_key, created_at, updated_at) "
        "VALUES ('todo-one', '$localUserId', 'One', "
        "'kanbanStatus', 'todo', 'a', 0, 0)",
      );
      await expectLater(
        db.customStatement(
          "INSERT INTO labels "
          "(id, user_id, name, kind, system_key, order_key, created_at, updated_at) "
          "VALUES ('todo-two', '$localUserId', 'Two', "
          "'kanbanStatus', 'todo', 'b', 0, 0)",
        ),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains(
              'UNIQUE constraint failed: labels.system_key',
            ),
          ),
        ),
      );
    });

    test(
      'migrates a complete v3 snapshot and initializes preserved data',
      () async {
        final verifier = migrations.SchemaVerifier(v3_schema.GeneratedHelper());
        initializedV3 = await verifier.schemaAt(3);
        _seedCompleteV3(initializedV3!.rawDatabase);
        db = AppDatabase(initializedV3!.newConnection());

        await db.ensureSeedData();
        await db.validateDatabaseSchema(
          options: const migrations.ValidationOptions(validateDropped: true),
        );

        final version = await db
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(version.read<int>('user_version'), 5);
        if (version.read<int>('user_version') != 5) {
          return;
        }
        final userLabels = await db
            .customSelect(
              "SELECT id, name, kind, system_key FROM labels "
              "WHERE id IN ('user-backlog', 'user-done') ORDER BY id",
            )
            .get();
        final taskLabel = await db
            .customSelect(
              "SELECT kind FROM task_labels "
              "WHERE task_id = 'task-open' AND label_id = 'user-backlog'",
            )
            .getSingle();
        expect(userLabels.map((row) => row.read<String>('name')).toSet(), {
          'Backlog',
          'Done',
        });
        expect(
          userLabels.map((row) => row.read<String>('kind')),
          everyElement('user'),
        );
        expect(
          userLabels.map((row) => row.readNullable<String>('system_key')),
          everyElement(isNull),
        );
        expect(taskLabel.read<String>('kind'), 'user');

        final projects = await db.select(db.projects).get();
        expect(projects.map((project) => project.id).toSet(), {
          inboxProjectId,
          'project-active',
          'project-archived',
        });
        expect(
          projects
              .singleWhere((row) => row.id == 'project-archived')
              .isArchived,
          isTrue,
        );
        final tasks = await db.select(db.tasks).get();
        expect(
          {for (final task in tasks) task.id: task.status},
          {'task-open': 'open', 'task-completed': 'completed'},
        );

        final assignments = await db
            .customSelect(
              "SELECT tl.task_id, l.system_key FROM task_labels tl "
              'JOIN labels l ON l.id = tl.label_id '
              "WHERE tl.kind = 'kanbanStatus' ORDER BY tl.task_id",
            )
            .get();
        expect(
          assignments
              .map(
                (row) => (
                  row.read<String>('task_id'),
                  row.read<String>('system_key'),
                ),
              )
              .toList(),
          const [('task-completed', 'done'), ('task-open', 'backlog')],
        );
        expect(await db.select(db.taskCompletions).get(), isEmpty);

        final settings = await db.select(db.kanbanSettings).getSingle();
        expect(settings.id, settingsId);
        expect(settings.selectedProjectIdsJson, '["project-active"]');
        expect(settings.focusStatusLabelId, inProgressId);
      },
    );

    test('resumes a partially applied v4 migration', () async {
      final verifier = migrations.SchemaVerifier(v3_schema.GeneratedHelper());
      initializedV3 = await verifier.schemaAt(3);
      initializedV3!.rawDatabase.execute(
        "ALTER TABLE labels ADD COLUMN kind TEXT NOT NULL DEFAULT 'user' "
        "CHECK(kind IN ('user', 'kanbanStatus'))",
      );
      db = AppDatabase(initializedV3!.newConnection());

      final version = await db.customSelect('PRAGMA user_version').getSingle();

      expect(version.read<int>('user_version'), 5);
      expect(
        await _columnNames(db, 'labels'),
        containsAll(['kind', 'system_key']),
      );
      expect(await _columnNames(db, 'task_labels'), contains('kind'));
      await db.customSelect('SELECT * FROM kanban_settings LIMIT 0').get();

      await db.customStatement('PRAGMA user_version = 3');
      await db.close();
      db = AppDatabase(initializedV3!.newConnection());

      final retriedVersion = await db
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(retriedVersion.read<int>('user_version'), 5);
    });
  });

  group('Kanban initialization', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.ensureSeedData();
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'creates deterministic defaults beside duplicate user names and assigns existing tasks',
      () async {
        final now = DateTime.utc(2026, 7, 10, 9);
        await db
            .into(db.labels)
            .insert(
              LabelsCompanion.insert(
                id: 'user-backlog',
                userId: localUserId,
                name: 'Backlog',
                orderKey: 'user-a',
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db
            .into(db.labels)
            .insert(
              LabelsCompanion.insert(
                id: 'user-done',
                userId: localUserId,
                name: 'Done',
                orderKey: 'user-b',
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db
            .into(db.projects)
            .insert(
              ProjectsCompanion.insert(
                id: 'project-first',
                userId: localUserId,
                name: 'First project',
                orderKey: '0',
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db
            .into(db.tasks)
            .insert(
              TasksCompanion.insert(
                id: 'task-open',
                userId: localUserId,
                content: 'Open task',
                projectId: 'project-first',
                orderKey: 'a',
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db
            .into(db.tasks)
            .insert(
              TasksCompanion.insert(
                id: 'task-completed',
                userId: localUserId,
                content: 'Completed task',
                projectId: 'project-first',
                status: const Value('completed'),
                orderKey: 'b',
                createdAt: now,
                updatedAt: now,
                completedAt: Value(now),
              ),
            );

        await db.customStatement('DELETE FROM kanban_settings');
        await db.ensureSeedData();
        await db.ensureSeedData();

        final labelColumns = await _columnNames(db, 'labels');
        expect(labelColumns, containsAll(<String>['kind', 'system_key']));
        if (!labelColumns.containsAll(<String>['kind', 'system_key'])) {
          return;
        }
        final statuses = await db
            .customSelect(
              "SELECT id, name, system_key FROM labels "
              "WHERE kind = 'kanbanStatus' AND is_deleted = 0 ORDER BY order_key",
            )
            .get();
        expect(
          statuses
              .map(
                (row) => (
                  row.read<String>('id'),
                  row.read<String>('name'),
                  row.read<String>('system_key'),
                ),
              )
              .toList(),
          const [
            (backlogId, 'Backlog', 'backlog'),
            (todoId, 'To do', 'todo'),
            (inProgressId, 'In progress', 'inProgress'),
            (doneId, 'Done', 'done'),
          ],
        );

        final userLabels = await db
            .customSelect(
              "SELECT id, kind, system_key, is_deleted FROM labels "
              "WHERE id IN ('user-backlog', 'user-done') ORDER BY id",
            )
            .get();
        expect(userLabels, hasLength(2));
        for (final row in userLabels) {
          expect(row.read<String>('kind'), 'user');
          expect(row.readNullable<String>('system_key'), isNull);
          expect(row.read<int>('is_deleted'), 0);
        }

        final assignments = await db
            .customSelect(
              "SELECT tl.task_id, l.system_key FROM task_labels tl "
              'JOIN labels l ON l.id = tl.label_id '
              "WHERE tl.kind = 'kanbanStatus' ORDER BY tl.task_id",
            )
            .get();
        expect(
          assignments
              .map(
                (row) => (
                  row.read<String>('task_id'),
                  row.read<String>('system_key'),
                ),
              )
              .toList(),
          const [('task-completed', 'done'), ('task-open', 'backlog')],
        );
        expect(await db.select(db.taskCompletions).get(), isEmpty);

        final settings = await db
            .customSelect(
              'SELECT id, selected_project_ids_json, focus_status_label_id '
              'FROM kanban_settings',
            )
            .getSingle();
        expect(settings.read<String>('id'), settingsId);
        expect(
          settings.read<String>('selected_project_ids_json'),
          '["project-first"]',
        );
        expect(settings.read<String>('focus_status_label_id'), inProgressId);
      },
    );

    test(
      'repairs protected anchors without resurrecting deleted middles',
      () async {
        final labelColumns = await _columnNames(db, 'labels');
        expect(labelColumns, containsAll(<String>['kind', 'system_key']));
        if (!labelColumns.containsAll(<String>['kind', 'system_key'])) {
          return;
        }
        await db.customStatement(
          "UPDATE labels SET name = 'Renamed Backlog', kind = 'user', "
          "system_key = NULL, is_deleted = 1 WHERE id = '$backlogId'",
        );
        await db.customStatement(
          "UPDATE labels SET name = '', order_key = 'a', "
          "is_deleted = 1 WHERE id = '$doneId'",
        );
        await db.customStatement(
          "UPDATE labels SET is_deleted = 1 "
          "WHERE id IN ('$todoId', '$inProgressId')",
        );

        await db.ensureSeedData();

        final anchors = await db
            .customSelect(
              "SELECT id, name, kind, system_key, is_deleted FROM labels "
              "WHERE id IN ('$backlogId', '$doneId') ORDER BY id",
            )
            .get();
        expect(anchors, hasLength(2));
        expect(
          anchors.map((row) => row.read<int>('is_deleted')),
          everyElement(0),
        );
        expect(
          anchors.map((row) => row.read<String>('kind')),
          everyElement('kanbanStatus'),
        );
        final namesById = {
          for (final row in anchors)
            row.read<String>('id'): row.read<String>('name'),
        };
        expect(namesById[backlogId], 'Renamed Backlog');
        expect(namesById[doneId], 'Done');

        final middles = await db
            .customSelect(
              "SELECT is_deleted FROM labels WHERE id IN ('$todoId', '$inProgressId')",
            )
            .get();
        expect(
          middles.map((row) => row.read<int>('is_deleted')),
          everyElement(1),
        );

        final settings = await db
            .customSelect('SELECT focus_status_label_id FROM kanban_settings')
            .getSingle();
        expect(settings.read<String>('focus_status_label_id'), backlogId);
      },
    );

    test(
      'partial unique index permits user labels but rejects a second status',
      () async {
        final taskLabelColumns = await _columnNames(db, 'task_labels');
        expect(taskLabelColumns, contains('kind'));
        if (!taskLabelColumns.contains('kind')) {
          return;
        }
        final now = DateTime.utc(2026, 7, 10, 9);
        await db
            .into(db.tasks)
            .insert(
              TasksCompanion.insert(
                id: 'task-1',
                userId: localUserId,
                content: 'Task',
                projectId: inboxProjectId,
                orderKey: 'a',
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db.ensureSeedData();
        await db
            .into(db.labels)
            .insert(
              LabelsCompanion.insert(
                id: 'user-label',
                userId: localUserId,
                name: 'User label',
                orderKey: 'user',
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db.customStatement(
          "INSERT INTO task_labels (task_id, label_id, kind, created_at) "
          "VALUES ('task-1', 'user-label', 'user', 0)",
        );

        await expectLater(
          db.customStatement(
            "INSERT INTO task_labels (task_id, label_id, kind, created_at) "
            "VALUES ('task-1', '$todoId', 'kanbanStatus', 0)",
          ),
          throwsA(
            predicate<Object>(
              (error) => error.toString().contains(
                'UNIQUE constraint failed: task_labels.task_id',
              ),
            ),
          ),
        );
      },
    );
  });
}

Future<Set<String>> _columnNames(AppDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

final _throwsCheckConstraint = throwsA(
  predicate<Object>(
    (error) => error.toString().contains('CHECK constraint failed'),
  ),
);

void _seedCompleteV3(dynamic database) {
  database.execute(
    "INSERT INTO users (id, display_name, created_at, updated_at) "
    "VALUES ('$localUserId', 'Migrated User', 1, 1)",
  );
  database.execute(
    "INSERT INTO workspaces (id, user_id, name, created_at, updated_at) "
    "VALUES ('$localWorkspaceId', '$localUserId', 'Personal', 1, 1)",
  );
  database.execute(
    "INSERT INTO projects "
    "(id, user_id, name, order_key, created_at, updated_at) VALUES "
    "('$inboxProjectId', '$localUserId', 'Inbox', 'a', 1, 1), "
    "('project-active', '$localUserId', 'Active', '0', 1, 1), "
    "('project-archived', '$localUserId', 'Archived', '-1', 1, 1)",
  );
  database.execute(
    "UPDATE projects SET is_archived = 1 WHERE id = 'project-archived'",
  );
  database.execute(
    "INSERT INTO tasks "
    "(id, user_id, content, project_id, status, order_key, created_at, updated_at, completed_at) VALUES "
    "('task-open', '$localUserId', 'Open', 'project-active', 'open', 'a', 1, 1, NULL), "
    "('task-completed', '$localUserId', 'Completed', 'project-active', 'completed', 'b', 1, 1, 2)",
  );
  database.execute(
    "INSERT INTO labels "
    "(id, user_id, name, order_key, created_at, updated_at) VALUES "
    "('user-backlog', '$localUserId', 'Backlog', 'a', 1, 1), "
    "('user-done', '$localUserId', 'Done', 'b', 1, 1)",
  );
  database.execute(
    "INSERT INTO task_labels (task_id, label_id, created_at) "
    "VALUES ('task-open', 'user-backlog', 1), "
    "('task-completed', 'user-done', 1)",
  );
}
