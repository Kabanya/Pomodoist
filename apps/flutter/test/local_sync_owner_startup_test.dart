import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/data/services/local/sync_owner_store.dart';
import 'package:pomodoist/data/services/notifications/notification_scheduler.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:uuid/uuid.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final owner in ['account-A', 'guest', null]) {
    test('cold startup preserves local data for owner $owner', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();
      if (owner != null) await _writeOwner(db, owner);
      final id =
          (await DriftTaskRepository(db, DriftOutboxService(db)).createTask(
            CreateTaskInput(content: 'Unsent before update'),
          )).getOrThrow();
      final tasksBefore = await db.select(db.tasks).get();
      final commandsBefore = await db.select(db.syncCommands).get();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          focusAutoCompletionCoordinatorProvider.overrideWith((ref) {}),
          notificationSchedulerProvider.overrideWithValue(
            _NoopNotificationScheduler(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(appStartupProvider.future);

      expect(await db.select(db.tasks).get(), tasksBefore);
      expect(await db.select(db.syncCommands).get(), commandsBefore);
      expect((await db.select(db.tasks).getSingle()).id, id);
    });
  }

  test(
    'a queue created before owner loading stays bound after a switch',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();
      await _writeOwner(db, 'account-A');
      final firstOwner = Completer<String?>();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          localSyncOwnerProvider.overrideWith(
            (ref) => Stream.fromFuture(firstOwner.future),
          ),
        ],
      );
      addTearDown(container.dispose);
      final queue = container.read(syncQueueRepositoryProvider);
      final command = queue.enqueue(
        type: 'task.create',
        clientId: 'task-A',
        payload: {'content': 'Owner A'},
      );
      firstOwner.complete('account-A');
      await command;
      final commandsBefore = await db.select(db.syncCommands).get();

      await _writeOwner(db, 'account-B');
      await expectLater(
        queue.enqueue(
          type: 'task.create',
          clientId: 'stale',
          payload: {'content': 'Must not reach B'},
        ),
        throwsStateError,
      );
      expect(await db.select(db.syncCommands).get(), commandsBefore);
    },
  );
  test(
    'owner changes rebuild the queue without unbinding old writers',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();
      await _writeOwner(db, 'account-A');
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      final switched = Completer<void>();
      final subscription = container.listen(localSyncOwnerProvider, (_, next) {
        if (next.value == 'account-B' && !switched.isCompleted) {
          switched.complete();
        }
      });
      addTearDown(subscription.close);
      await container.read(localSyncOwnerProvider.future);
      final oldQueue = container.read(syncQueueRepositoryProvider);

      await _writeOwner(db, 'account-B');
      await switched.future;
      await container
          .read(syncQueueRepositoryProvider)
          .enqueue(
            type: 'task.create',
            clientId: 'task-B',
            payload: {'content': 'Owner B'},
          );
      await expectLater(
        oldQueue.enqueue(type: 'task.create', payload: {'content': 'Stale A'}),
        throwsStateError,
      );
      expect((await db.select(db.syncCommands).getSingle()).clientId, 'task-B');
    },
  );
}

Future<void> _writeOwner(AppDatabase db, String owner) =>
    SyncOwnerStore(db, const Uuid()).writeOwner(owner);

class _NoopNotificationScheduler extends NotificationScheduler {
  @override
  Future<void> initialize() async {}
}
