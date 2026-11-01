import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/tasks/csv_task_export_repository_impl.dart';
import 'package:pomodoist/data/services/files/csv_task_export_service.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/sync_owner_store.dart';
import 'package:pomodoist/domain/models/account/account_session.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/utils/result.dart';
import 'package:uuid/uuid.dart';

void main() {
  late AppDatabase db;
  late AccountSession session;
  late Uint8List saved;
  late String filename;
  late int writes;
  final now = DateTime(2026, 11, 2, 9, 8, 7);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.ensureSeedData();
    session = (userId: null, generation: 0);
    writes = 0;
  });
  tearDown(() => db.close());

  DriftCsvTaskExportRepository repository({
    Future<String?> Function(String)? selectPath,
    Future<void> Function(Uint8List, String, String)? writeFile,
  }) => DriftCsvTaskExportRepository(
    CsvTaskExportService(
      db,
      selectPath: selectPath ?? (name) async => '/chosen/tasks.csv',
      writeFile:
          writeFile ??
          (bytes, name, path) async {
            expect(path, '/chosen/tasks.csv');
            saved = bytes;
            filename = name;
            writes++;
          },
    ),
    currentSession: () => session,
    now: () => now,
  );

  List<Map<String, String>> rows() {
    final decoded = Csv(autoDetect: false).decode(utf8.decode(saved));
    final header = decoded.first.cast<String>();
    return [
      for (final row in decoded.skip(1))
        Map.fromIterables(header, row.map((cell) => cell.toString())),
    ];
  }

  Future<void> task(
    String id, {
    String? projectId,
    String? parentId,
    String? scopeId,
    bool deleted = false,
    String status = 'open',
    String? content,
    String? dueJson,
    DateTime? createdAt,
  }) => db
      .into(db.tasks)
      .insert(
        TasksCompanion.insert(
          id: id,
          userId: localUserId,
          content: content ?? id,
          projectId: projectId ?? inboxProjectId,
          orderKey: id,
          createdAt: createdAt ?? now,
          updatedAt: now,
          parentId: Value(parentId),
          scopeId: Value(scopeId),
          status: Value(status),
          isDeleted: Value(deleted),
          dueJson: Value(dueJson),
        ),
      );

  test(
    'exports completed tasks, archived projects and children, excluding deleted and unavailable scopes',
    () async {
      await db
          .into(db.projects)
          .insert(
            ProjectsCompanion.insert(
              id: 'archive',
              userId: localUserId,
              name: 'Archive',
              orderKey: '1',
              createdAt: now,
              updatedAt: now,
              isArchived: const Value(true),
            ),
          );
      await db
          .into(db.sharedScopes)
          .insert(SharedScopesCompanion.insert(id: 'shared', dataJson: '{}'));
      await db
          .into(db.projects)
          .insert(
            ProjectsCompanion.insert(
              id: 'team',
              userId: 'owner',
              name: 'Команда',
              orderKey: '2',
              createdAt: now,
              updatedAt: now,
              scopeId: const Value('shared'),
            ),
          );
      await task(
        'parent',
        projectId: 'archive',
        createdAt: now.subtract(const Duration(days: 1)),
      );
      await task(
        'child',
        projectId: 'archive',
        parentId: 'parent',
        status: 'completed',
      );
      await task('shared', projectId: 'team', scopeId: 'shared');
      await db.batch((batch) {
        batch.insertAll(db.labels, [
          LabelsCompanion.insert(
            id: 'team-label',
            userId: 'owner',
            name: 'Общая',
            orderKey: '1',
            createdAt: now,
            updatedAt: now,
            scopeId: const Value('shared'),
          ),
          LabelsCompanion.insert(
            id: 'team-status',
            userId: 'owner',
            name: 'В работе',
            orderKey: '2',
            createdAt: now,
            updatedAt: now,
            scopeId: const Value('shared'),
            kind: const Value(labelKindKanbanStatus),
          ),
          LabelsCompanion.insert(
            id: 'deleted-label',
            userId: 'owner',
            name: 'Deleted',
            orderKey: '3',
            createdAt: now,
            updatedAt: now,
            scopeId: const Value('shared'),
            isDeleted: const Value(true),
          ),
          LabelsCompanion.insert(
            id: 'personal-label',
            userId: localUserId,
            name: 'Personal',
            orderKey: '4',
            createdAt: now,
            updatedAt: now,
          ),
        ]);
        batch.insertAll(db.taskLabels, [
          for (final id in ['team-label', 'deleted-label', 'personal-label'])
            TaskLabelsCompanion.insert(
              taskId: 'shared',
              labelId: id,
              createdAt: now,
            ),
          TaskLabelsCompanion.insert(
            taskId: 'shared',
            labelId: 'team-status',
            kind: const Value(labelKindKanbanStatus),
            createdAt: now,
          ),
        ]);
      });
      await task('removed', deleted: true);
      await task('revoked', scopeId: 'missing');

      expect((await repository().exportAllTasks()).getOrThrow(), isTrue);
      final result = rows();
      expect(result.map((r) => r['id']), ['parent', 'child', 'shared']);
      expect(result[1]['status'], 'completed');
      expect(result[1]['parent_id'], 'parent');
      expect(result[1]['project'], 'Archive');
      expect(result[1]['project_archived'], 'true');
      expect(result[2]['scope_id'], 'shared');
      expect(result[2]['project'], 'Команда');
      expect(jsonDecode(result[2]['labels']!), ['Общая']);
      expect(result[2]['kanban_status'], 'В работе');
      expect(filename, 'pomodoist-tasks-2026-11-02-090807.csv');
      expect(saved.take(3), [239, 187, 191]);
      expect(utf8.decode(saved), contains('\r\n'));
    },
  );

  test('preserves text, schedule, relations, dates and focus totals', () async {
    final schedule = TaskSchedule.timed(
      start: DateTime.parse('2026-11-03T09:00:00+03:00'),
      end: DateTime.parse('2026-11-03T10:00:00+03:00'),
      timeZone: 'Europe/Moscow',
      recurrence: const TaskRecurrence(
        interval: 2,
        unit: TaskRecurrenceUnit.week,
        seriesId: 'series',
      ),
    );
    await task(
      'task',
      content: 'Задача, "важная"\nВторая строка',
      dueJson: schedule.toJsonString(),
    );
    await (db.update(db.tasks)..where((t) => t.id.equals('task'))).write(
      TasksCompanion(
        description: const Value('Описание'),
        sectionId: const Value('section'),
        deadlineJson: const Value(
          '{"type":"date","date":"2026-11-05T00:00:00.000"}',
        ),
        durationSeconds: const Value(3600),
        estimatedFocusIntervals: const Value(4),
        isFocusEstimateManual: const Value(true),
        completedFocusIntervals: const Value(2),
        totalFocusSeconds: const Value(3000),
        assigneeIdsJson: const Value('["alice","bob"]'),
        createdBy: const Value('alice'),
        completedBy: const Value('bob'),
        completedAt: Value(DateTime.utc(2026, 11, 4)),
      ),
    );
    await db
        .into(db.sections)
        .insert(
          SectionsCompanion.insert(
            id: 'section',
            projectId: inboxProjectId,
            name: 'Раздел',
            orderKey: '1',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.labels)
        .insert(
          LabelsCompanion.insert(
            id: 'label',
            userId: localUserId,
            name: 'метка|с запятой,',
            orderKey: '1',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.taskLabels)
        .insert(
          TaskLabelsCompanion.insert(
            taskId: 'task',
            labelId: 'label',
            createdAt: now,
          ),
        );
    await repository().exportAllTasks();
    final row = rows().single;
    expect(row['content'], 'Задача, "важная"\nВторая строка');
    expect(row['description'], 'Описание');
    expect(row['section'], 'Раздел');
    expect(jsonDecode(row['labels']!), ['метка|с запятой,']);
    expect(jsonDecode(row['assignee_ids']!), ['alice', 'bob']);
    expect(row['due_date'], isEmpty);
    expect(row['start_at'], '2026-11-03T06:00:00.000Z');
    expect(row['end_at'], '2026-11-03T07:00:00.000Z');
    expect(row['time_zone'], 'Europe/Moscow');
    expect(row['recurrence'], 'week');
    expect(row['recurrence_interval'], '2');
    expect(row['deadline'], '2026-11-05');
    expect(row['duration_seconds'], '3600');
    expect(row['estimated_focus_intervals'], '4');
    expect(row['is_focus_estimate_manual'], 'true');
    expect(row['completed_focus_intervals'], '2');
    expect(row['total_focus_seconds'], '3000');
    expect(row['completed_at'], '2026-11-04T00:00:00.000Z');
    expect(row['created_by'], 'alice');
    expect(row['completed_by'], 'bob');
  });

  test(
    'keeps all-day dates and neutralizes formulas after leading spaces',
    () async {
      final dangerous = [
        '=SUM(1,2)',
        '+1',
        '-1',
        '@SUM(1)',
        '\ttext',
        '\rtext',
        '\ntext',
        '  =1',
        '  \t=1',
      ];
      for (var i = 0; i < dangerous.length; i++) {
        await task(
          '$i',
          content: dangerous[i],
          dueJson: TaskSchedule.allDay(DateTime(2026, 11, 3)).toJsonString(),
        );
      }
      await repository().exportAllTasks();
      expect(rows().map((r) => r['content']), dangerous.map((s) => "'$s"));
      expect(rows().first['due_date'], '2026-11-03');
      expect(rows().first['start_at'], isEmpty);
    },
  );

  test(
    'exports an empty file with a header and has no 1000-task limit',
    () async {
      expect((await repository().exportAllTasks()).getOrThrow(), isTrue);
      expect(rows(), isEmpty);
      await db.batch((batch) {
        batch.insertAll(db.tasks, [
          for (var i = 0; i < 1001; i++)
            TasksCompanion.insert(
              id: '$i',
              userId: localUserId,
              content: 'Task $i',
              projectId: inboxProjectId,
              orderKey: '$i',
              createdAt: now,
              updatedAt: now,
            ),
        ]);
      });
      await repository().exportAllTasks();
      expect(rows(), hasLength(1001));
    },
  );

  test('cancel does not write, and a write error can be retried', () async {
    expect(
      (await repository(
        selectPath: (_) async => null,
      ).exportAllTasks()).getOrThrow(),
      isFalse,
    );
    expect(writes, 0);
    var attempts = 0;
    final exporter = repository(
      writeFile: (_, _, _) async {
        if (attempts++ == 0) throw StateError('disk full');
        writes++;
      },
    );
    expect(await exporter.exportAllTasks(), isA<Failure<bool>>());
    expect((await exporter.exportAllTasks()).getOrThrow(), isTrue);
    expect(writes, 1);
  });

  test(
    'account change while choosing a path prevents writing the old snapshot',
    () async {
      final exporter = repository(
        selectPath: (_) async {
          session = (userId: 'other', generation: 1);
          return '/chosen/tasks.csv';
        },
      );
      expect((await exporter.exportAllTasks()).getOrThrow(), isFalse);
      expect(writes, 0);
    },
  );

  test(
    'owner reset while choosing a path prevents writing, even in the same session',
    () async {
      final exporter = repository(
        selectPath: (_) async {
          await SyncOwnerStore(db, const Uuid()).writeOwner('guest');
          return '/chosen/tasks.csv';
        },
      );
      expect((await exporter.exportAllTasks()).getOrThrow(), isFalse);
      expect(writes, 0);
    },
  );

  test('does not export data still owned by a different account', () async {
    await SyncOwnerStore(db, const Uuid()).writeOwner('previous');
    expect((await repository().exportAllTasks()).getOrThrow(), isFalse);
    expect(writes, 0);
  });

  test('exports a dataset bound to the signed-in account', () async {
    await SyncOwnerStore(db, const Uuid()).writeOwner('alice');
    session = (userId: 'alice', generation: 1);
    await task('personal');
    expect((await repository().exportAllTasks()).getOrThrow(), isTrue);
    expect(rows().single['id'], 'personal');
  });

  test(
    'session change during the snapshot does not open a save dialog',
    () async {
      final exporter = repository(
        selectPath: (_) async {
          fail('An obsolete snapshot must not reach the save dialog.');
        },
      );
      final pending = exporter.exportAllTasks();
      session = (userId: 'other', generation: 1);
      expect((await pending).getOrThrow(), isFalse);
      expect(writes, 0);
    },
  );

  test(
    'a new session generation cancels even when the user ID is unchanged',
    () async {
      final exporter = repository(
        selectPath: (_) async {
          session = (userId: null, generation: 1);
          return '/chosen/tasks.csv';
        },
      );
      expect((await exporter.exportAllTasks()).getOrThrow(), isFalse);
      expect(writes, 0);
    },
  );
}
