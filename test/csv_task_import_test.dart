import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/core/sync/sync_queue_repository.dart';
import 'package:pomodoist/features/tasks/data/csv_task_import.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';

void main() {
  test('parses the complete pomodoist_csv_v1 contract', () {
    final document = CsvTaskImportDocument.parse(
      utf8.encode('''
key,content,description,project,labels,priority,due_date,start_at,end_at,time_zone,recurrence,recurrence_interval,deadline,estimate,kanban_status,parent_key
parent,Plan launch,"Owner, scope",Work,planning|urgent,1,2026-08-10,,,,week,2,2026-08-09,4,In progress,
child,Book venue,,Work,,2,,2026-08-08T09:00:00+03:00,2026-08-08T10:30:00+03:00,Europe/Moscow,,,2026-08-07,2,Backlog,parent
'''),
    );

    expect(document.tasks, hasLength(2));
    final parent = document.tasks.first;
    expect(parent.rowNumber, 2);
    expect(parent.content, 'Plan launch');
    expect(parent.description, 'Owner, scope');
    expect(parent.projectName, 'Work');
    expect(parent.labelNames, ['planning', 'urgent']);
    expect(parent.priority, 1);
    expect(parent.schedule!.date, DateTime(2026, 8, 10));
    expect(parent.recurrenceUnit, TaskRecurrenceUnit.week);
    expect(parent.recurrenceInterval, 2);
    expect(parent.deadline, DateTime(2026, 8, 9));
    expect(parent.estimatedFocusIntervals, 4);
    expect(parent.kanbanStatusName, 'In progress');

    final child = document.tasks.last;
    expect(child.parentKey, 'parent');
    expect(child.schedule!.start, DateTime.utc(2026, 8, 8, 6));
    expect(child.schedule!.end, DateTime.utc(2026, 8, 8, 7, 30));
    expect(child.schedule!.timeZone, 'Europe/Moscow');
  });

  test('accepts UTF-8 BOM, semicolons, reordered and omitted headers', () {
    final document = CsvTaskImportDocument.parse(
      utf8.encode('\ufeffcontent;labels;priority\n"Line 1\nLine 2";one|two;\n'),
    );

    expect(document.tasks.single.content, 'Line 1\nLine 2');
    expect(document.tasks.single.labelNames, ['one', 'two']);
    expect(document.tasks.single.priority, 4);
  });

  test('rejects unknown and duplicate headers', () {
    expect(
      () => CsvTaskImportDocument.parse(
        utf8.encode('content,content,mystery\nOne,Two,Three\n'),
      ),
      throwsA(
        isA<CsvTaskImportException>().having(
          (error) => error.issues.map((issue) => issue.message).join(' '),
          'issues',
          allOf(contains('Duplicate header'), contains('Unknown header')),
        ),
      ),
    );
  });

  test('reports invalid field values together', () {
    final csv = '''
content,priority,due_date,start_at,end_at,time_zone,recurrence,recurrence_interval,deadline,estimate,kanban_status,key
,5,2026-02-30,2026-08-08T09:00:00,2026-08-08T08:00:00+03:00,Mars/Olympus,year,0,08/07/2026,1000,Done,bad key
''';

    expect(
      () => CsvTaskImportDocument.parse(utf8.encode(csv)),
      throwsA(
        isA<CsvTaskImportException>().having(
          (error) => error.issues.map((issue) => issue.message).join(' '),
          'issues',
          predicate<String>(
            (messages) => [
              'content',
              'priority',
              'due_date',
              'start_at',
              'time_zone',
              'recurrence',
              'recurrence_interval',
              'deadline',
              'estimate',
              'Done',
              'key',
            ].every(messages.contains),
          ),
        ),
      ),
    );
  });

  test('requires a complete timed schedule and schedule for recurrence', () {
    expect(
      () => CsvTaskImportDocument.parse(
        utf8.encode(
          'content,start_at,end_at,time_zone,recurrence\n'
          'Timed,2026-08-08T09:00:00+03:00,,,\n'
          'Repeat,,,,day\n',
        ),
      ),
      throwsA(
        isA<CsvTaskImportException>().having(
          (error) => error.issues.map((issue) => issue.message).join(' '),
          'issues',
          allOf(contains('timed schedule'), contains('requires a schedule')),
        ),
      ),
    );
  });

  test('resolves forward parent references and inherited projects', () {
    final document = CsvTaskImportDocument.parse(
      utf8.encode(
        'key,content,project,parent_key\n'
        'child,Child,,parent\n'
        'parent,Parent,Work,\n',
      ),
    );

    expect(document.tasks.map((task) => task.key), ['parent', 'child']);
    expect(document.tasks.last.projectName, 'Work');

    final inbox = CsvTaskImportDocument.parse(
      utf8.encode(
        'key,content,project,parent_key\n'
        'parent,Parent,,\n'
        'child,Child,Inbox,parent\n',
      ),
    );
    expect(inbox.tasks.last.projectName, 'Inbox');
  });

  test('rejects missing parents, cycles and cross-project children', () {
    for (final csv in [
      'key,content,parent_key\nchild,Child,missing\n',
      'key,content,parent_key\na,A,b\nb,B,a\n',
      'key,content,project,parent_key\nparent,Parent,Work,\nchild,Child,Home,parent\n',
    ]) {
      expect(
        () => CsvTaskImportDocument.parse(utf8.encode(csv)),
        throwsA(isA<CsvTaskImportException>()),
      );
    }
  });

  test('keys are case-sensitive but exact duplicates are rejected', () {
    final document = CsvTaskImportDocument.parse(
      utf8.encode('key,content\nA,Upper\na,Lower\n'),
    );
    expect(document.tasks, hasLength(2));

    expect(
      () => CsvTaskImportDocument.parse(
        utf8.encode('key,content\nA,First\nA,Second\n'),
      ),
      throwsA(isA<CsvTaskImportException>()),
    );
  });

  test('enforces UTF-8, file-size and task-count limits', () {
    expect(
      () => CsvTaskImportDocument.parse([0xFF]),
      throwsA(isA<CsvTaskImportException>()),
    );
    expect(
      () => CsvTaskImportDocument.parse(
        List.filled(CsvTaskImportDocument.maximumBytes + 1, 0),
      ),
      throwsA(isA<CsvTaskImportException>()),
    );
    expect(
      () => CsvTaskImportDocument.parse(
        utf8.encode('content\n${List.filled(1001, 'Task').join('\n')}\n'),
      ),
      throwsA(isA<CsvTaskImportException>()),
    );
  });

  group('CsvTaskImporter', () {
    late AppDatabase db;
    late DriftSyncQueueRepository syncQueue;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.ensureSeedData();
      syncQueue = DriftSyncQueueRepository(db);
    });

    tearDown(() => db.close());

    test(
      'previews and atomically imports projects, labels and statuses',
      () async {
        final importer = CsvTaskImporter(db, syncQueue);
        final preview = await importer.prepare(
          utf8.encode(
            'key,content,project,labels,kanban_status,parent_key,recurrence,due_date\n'
            'child,Child,,Urgent,Waiting,parent,,\n'
            'parent,Parent,Work,Planning|urgent,Waiting,,week,2026-08-10\n',
          ),
        );

        expect(preview.taskCount, 2);
        expect(preview.subtaskCount, 1);
        expect(preview.newProjects, ['Work']);
        expect(preview.newLabels, ['Planning', 'urgent']);
        expect(preview.newKanbanStatuses, ['Waiting']);
        expect(await db.select(db.tasks).get(), isEmpty);

        final result = await importer.commit(preview);
        expect(result.taskIds, hasLength(2));
        final rows = await db.select(db.tasks).get();
        expect(rows, hasLength(2));
        final parent = rows.singleWhere((row) => row.content == 'Parent');
        final child = rows.singleWhere((row) => row.content == 'Child');
        expect(child.parentId, parent.id);
        expect(child.projectId, parent.projectId);
        expect(
          TaskSchedule.fromJsonString(parent.dueJson)!.recurrence,
          isNotNull,
        );

        await importer.commit(preview);
        expect(await db.select(db.tasks).get(), hasLength(4));
        expect(
          (await db.select(db.projects).get()).where(
            (project) => project.name.toLowerCase() == 'work',
          ),
          hasLength(1),
        );
        expect(
          (await db.select(db.labels).get()).where(
            (label) => label.name.toLowerCase() == 'waiting',
          ),
          hasLength(1),
        );
      },
    );

    test('rolls back every database write when an import fails', () async {
      final importer = CsvTaskImporter(
        db,
        _FailingSyncQueue(syncQueue, failOnCall: 5),
      );
      final preview = await importer.prepare(
        utf8.encode(
          'content,project,labels,kanban_status\n'
          'Task,Work,Urgent,Waiting\n',
        ),
      );

      await expectLater(() => importer.commit(preview), throwsStateError);

      expect(await db.select(db.tasks).get(), isEmpty);
      expect(
        (await db.select(db.projects).get()).where(
          (project) => project.name == 'Work',
        ),
        isEmpty,
      );
      expect(
        (await db.select(db.labels).get()).where(
          (label) => {'Waiting', 'Urgent'}.contains(label.name),
        ),
        isEmpty,
      );
    });

    test('reuses label names case-insensitively beyond SQLite ASCII', () async {
      final now = DateTime.utc(2026, 8, 4);
      await db
          .into(db.labels)
          .insert(
            LabelsCompanion.insert(
              id: 'existing-label',
              userId: localUserId,
              name: 'Ärger',
              orderKey: '1',
              createdAt: now,
              updatedAt: now,
            ),
          );
      final importer = CsvTaskImporter(db, syncQueue);
      final preview = await importer.prepare(
        utf8.encode('content,labels\nTask,ärger\n'),
      );

      expect(preview.newLabels, isEmpty);
      final result = await importer.commit(preview);
      final attached =
          await (db.select(db.taskLabels)..where(
                (row) =>
                    row.taskId.equals(result.taskIds.single) &
                    row.kind.equals(labelKindUser),
              ))
              .getSingle();
      expect(attached.labelId, 'existing-label');
      expect(
        (await db.select(db.labels).get()).where(
          (label) => label.name.toLowerCase() == 'ärger',
        ),
        hasLength(1),
      );
    });
  });
}

class _FailingSyncQueue implements SyncQueueRepository {
  _FailingSyncQueue(this.delegate, {required this.failOnCall});

  final SyncQueueRepository delegate;
  final int failOnCall;
  int _calls = 0;

  void _check() {
    _calls += 1;
    if (_calls == failOnCall) throw StateError('Injected sync queue failure');
  }

  @override
  Future<void> enqueue({
    required String type,
    required Map<String, Object?> payload,
    String? clientId,
  }) {
    _check();
    return delegate.enqueue(type: type, payload: payload, clientId: clientId);
  }

  @override
  Future<void> enqueueBatch(
    List<SyncQueueCommand> commands, {
    DateTime? occurredAt,
  }) {
    _check();
    return delegate.enqueueBatch(commands, occurredAt: occurredAt);
  }

  @override
  Stream<List<SyncCommandRow>> watchPending() => delegate.watchPending();
}
