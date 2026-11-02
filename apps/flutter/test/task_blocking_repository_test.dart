import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:pomodoist/data/repositories/focus/focus_repository_impl.dart';
import 'package:pomodoist/data/services/notifications/notification_scheduler.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';
import 'package:pomodoist/data/repositories/tasks/task_blocking_repository.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/tasks/task_blocking.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late DriftOutboxService queue;
  late DriftTaskRepository tasks;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.ensureSeedData();
    queue = DriftOutboxService(db);
    tasks = DriftTaskRepository(db, queue);
  });
  tearDown(() => db.close());
  Future<String> create(
    String title, {
    String? parent,
    List<String> needs = const [],
  }) async => (await tasks.createTask(
    CreateTaskInput(content: title, parentId: parent, prerequisiteIds: needs),
  )).getOrThrow();
  test(
    'completion rejects external predecessor without history or outbox writes',
    () async {
      final a = await create('a');
      final b = await create('b', needs: [a]);
      final before = (await queue.watchPending().first).length;
      await expectLater(
        () async => (await tasks.completeTask(b)).getOrThrow(),
        throwsA(isA<TaskBlockedException>()),
      );
      expect((await tasks.watchTask(b).first)!.isCompleted, isFalse);
      expect(await db.select(db.taskCompletions).get(), isEmpty);
      expect((await queue.watchPending().first).length, before);
    },
  );
  test(
    'a branch completes with internal dependencies and undo restores predecessors',
    () async {
      final root = await create('root');
      final a = await create('a', parent: root);
      final b = await create('b', parent: root, needs: [a]);
      (await tasks.completeTask(root)).getOrThrow();
      expect((await tasks.watchTask(b).first)!.isCompleted, isTrue);
      (await tasks.uncompleteTask(a)).getOrThrow();
      expect((await tasks.watchTask(b).first)!.isCompleted, isTrue);
    },
  );
  test(
    'updating dependencies persists and rejects a cycle transactionally',
    () async {
      final a = await create('a');
      final b = await create('b', needs: [a]);
      await expectLater(
        () async => (await tasks.updateTask(
          a,
          UpdateTaskPatch(prerequisiteIds: [b]),
        )).getOrThrow(),
        throwsArgumentError,
      );
      expect((await tasks.watchTask(a).first)!.prerequisiteIds, isEmpty);
      (await tasks.updateTask(
        b,
        UpdateTaskPatch(content: 'renamed'),
      )).getOrThrow();
      expect((await tasks.watchTask(b).first)!.prerequisiteIds, [a]);
    },
  );
  test(
    'deleting a predecessor releases it and undo restores blocking',
    () async {
      final a = await create('a');
      final b = await create('b', needs: [a]);
      final blocking = DriftTaskBlockingRepository(db, queue);
      final deleted = (await tasks.deleteTask(a)).getOrThrow();
      expect((await blocking.policy()).availability(b).canComplete, isTrue);
      (await tasks.restoreDeletedTasks(deleted)).getOrThrow();
      expect((await blocking.policy()).availability(b).canComplete, isFalse);
    },
  );
  test(
    'private urgent selection persists in the personal outbox and resets with owner',
    () async {
      final id = await create('urgent');
      final other = await create('other');
      final blocking = DriftTaskBlockingRepository(db, queue);
      (await blocking.setUrgent(
        (await tasks.watchTask(id).first)!,
        urgent: true,
      )).getOrThrow();
      expect(
        (await blocking.policy()).availability(other).canComplete,
        isFalse,
      );
      final commands = (await queue.watchPending().first).where(
        (c) => c.type == 'task_blocking.upsert',
      );
      expect(commands.length, 2);
      expect(jsonDecode(commands.last.payloadJson)['taskId'], id);
      await db.resetAccountData();
      expect(await db.select(db.taskBlockingRecords).get(), isEmpty);
    },
  );
  test(
    'Focus start, resume and restart check blocking while a running interval keeps credit',
    () async {
      final a = await create('a');
      final b = await create('b');
      final focus = DriftFocusRepository(db, queue, _Notifications());
      final blocking = DriftTaskBlockingRepository(db, queue);
      final now = DateTime.now().toUtc();
      (await focus.startRun(
        StartFocusRunInput(taskId: b, targetWorkIntervals: 2),
        now: now,
      )).getOrThrow();
      (await blocking.setUrgent(
        (await tasks.watchTask(a).first)!,
        urgent: true,
      )).getOrThrow();
      await expectLater(
        () async =>
            (await focus.startRun(StartFocusRunInput(taskId: b))).getOrThrow(),
        throwsA(isA<TaskBlockedException>()),
      );
      await expectLater(
        () async =>
            (await focus.startRun(const StartFocusRunInput())).getOrThrow(),
        throwsA(isA<TaskBlockedException>()),
      );
      await expectLater(
        () async => (await focus.restartActiveInterval()).getOrThrow(),
        throwsA(isA<TaskBlockedException>()),
      );
      (await focus.pauseActiveInterval(
        now: now.add(const Duration(seconds: 20)),
      )).getOrThrow();
      await expectLater(
        () async => (await focus.resumeActiveInterval()).getOrThrow(),
        throwsA(isA<TaskBlockedException>()),
      );
      (await focus.completeActiveInterval(
        now: now.add(const Duration(seconds: 60)),
      )).getOrThrow();
      expect((await tasks.watchTask(b).first)!.totalFocusSeconds, 20);
      (await focus.startReadyInterval()).getOrThrow();
      (await focus.completeActiveInterval()).getOrThrow();
      expect((await focus.watchActiveInterval().first)!.type, 'work');
      expect((await focus.watchActiveInterval().first)!.status, 'ready');
      await expectLater(
        () async => (await focus.startReadyInterval()).getOrThrow(),
        throwsA(isA<TaskBlockedException>()),
      );
    },
  );

  test(
    'automatic work waits when urgent changes during an existing work interval',
    () async {
      final a = await create('a');
      final b = await create('b');
      await db
          .update(db.focusPresets)
          .write(
            const FocusPresetsCompanion(
              autoStartWork: Value(true),
              autoStartBreaks: Value(true),
            ),
          );
      final focus = DriftFocusRepository(db, queue, _Notifications());
      (await focus.startRun(
        StartFocusRunInput(taskId: b, targetWorkIntervals: 2),
      )).getOrThrow();
      (await DriftTaskBlockingRepository(db, queue).setUrgent(
        (await tasks.watchTask(a).first)!,
        urgent: true,
      )).getOrThrow();
      (await focus.completeActiveInterval()).getOrThrow();
      expect((await focus.watchActiveInterval().first)!.status, 'running');
      (await focus.completeActiveInterval()).getOrThrow();
      expect((await focus.watchActiveInterval().first)!.status, 'ready');
    },
  );

  test(
    'moving a predecessor under its dependent rolls back hierarchy and outbox',
    () async {
      final a = await create('a');
      final b = await create('b', needs: [a]);
      final before = (await queue.watchPending().first).length;
      await expectLater(
        () async => (await tasks.moveTask(a, parentId: b)).getOrThrow(),
        throwsArgumentError,
      );
      expect((await tasks.watchTask(a).first)!.parentId, isNull);
      expect((await queue.watchPending().first).length, before);
    },
  );
}

class _Notifications extends NotificationScheduler {
  @override
  Future<void> initialize() async {}
  @override
  Future<void> cancelFocusNotification() async {}
  @override
  Future<void> scheduleFocusIntervalEnd({
    required DateTime expectedEndAt,
    required String title,
    required String body,
  }) async {}
}
