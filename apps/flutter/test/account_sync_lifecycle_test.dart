import 'dart:async';

import 'package:app_account/app_account.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/sync/account_sync_lifecycle.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/data/services/sync/account_sync_failure.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'restart bypasses one local backoff and coalesces repeated requests',
    () async {
      final queue = _FakeOutboxService();
      var calls = 0;
      final pending = Completer<Set<String>>();
      final lifecycle = AccountSyncLifecycle(
        syncNow: () async {
          calls++;
          if (calls == 1) throw StateError('offline');
          return pending.future;
        },
        deviceId: () async => 'device',
        syncHints: () => const Stream.empty(),
        syncQueueRepository: queue,
        retryDelays: const [Duration(hours: 1)],
      )..start();
      addTearDown(() async {
        lifecycle.dispose();
        await queue.dispose();
      });
      await pumpEventQueue();
      final Future<Set<String>> first = lifecycle.restart();
      final Future<Set<String>> second = lifecycle.restart();
      var completed = false;
      first.then((_) => completed = true);
      await pumpEventQueue();
      expect(calls, 2);
      expect(completed, isFalse);
      pending.complete({'task'});
      expect(await first, {'task'});
      expect(await second, {'task'});
      expect(calls, 2);
    },
  );

  test(
    'restart waits for an in-flight cycle and returns its own failure',
    () async {
      final queue = _FakeOutboxService();
      final active = Completer<Set<String>>();
      var calls = 0;
      final lifecycle = AccountSyncLifecycle(
        syncNow: () async {
          calls++;
          if (calls == 1) return active.future;
          throw StateError('offline');
        },
        deviceId: () async => 'device',
        syncHints: () => const Stream.empty(),
        syncQueueRepository: queue,
        retryDelays: const [Duration(hours: 1)],
      )..start();
      addTearDown(() async {
        lifecycle.dispose();
        await queue.dispose();
      });
      final Future<Set<String>> restart = lifecycle.restart();
      final assertion = expectLater(restart, throwsStateError);
      await pumpEventQueue();
      expect(calls, 1);
      active.complete({'task'});
      await assertion;
      expect(calls, 2);
    },
  );

  test('partial failure still notifies committed task work', () async {
    final queue = _FakeOutboxService();
    Set<String>? received;
    final lifecycle = AccountSyncLifecycle(
      syncNow: () async =>
          throw AccountSyncPartialFailure({'task'}, StateError('offline')),
      deviceId: () async => 'device',
      syncHints: () => const Stream.empty(),
      syncQueueRepository: queue,
      onSynced: (types) async => received = types,
      retryDelays: const [Duration(hours: 1)],
    )..start();
    await pumpEventQueue();
    expect(received, {'task'});
    lifecycle.dispose();
    await queue.dispose();
  });

  test('uses one-minute polling and bounded retry delays', () {
    expect(
      AccountSyncLifecycle.defaultPollInterval,
      const Duration(minutes: 1),
    );
    expect(AccountSyncLifecycle.defaultRetryDelays, const [
      Duration(seconds: 30),
      Duration(minutes: 1),
    ]);
    expect(
      AccountSyncLifecycle.boundedRetryDelay(
        const Duration(seconds: 30),
        sample: 0,
      ),
      const Duration(seconds: 27),
    );
    expect(
      AccountSyncLifecycle.boundedRetryDelay(
        const Duration(minutes: 1),
        sample: 1,
      ),
      const Duration(minutes: 1),
    );
  });

  test('pending local command schedules sync quickly', () async {
    final queue = _FakeOutboxService();
    var syncs = 0;
    final lifecycle = _lifecycle(queue: queue, syncNow: () async => syncs += 1)
      ..start();
    addTearDown(() async {
      lifecycle.dispose();
      await queue.dispose();
    });

    await Future<void>.delayed(const Duration(milliseconds: 20));
    final initialSyncs = syncs;

    queue.emit([_command()]);
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(syncs, greaterThan(initialSyncs));
  });

  test('deferred command schedules sync when it becomes available', () async {
    final queue = _FakeOutboxService();
    final hints = StreamController<AccountSyncHint>();
    var syncs = 0;
    final lifecycle = _lifecycle(
      queue: queue,
      syncNow: () async => syncs += 1,
      syncHints: () => hints.stream,
    )..start();
    addTearDown(() async {
      lifecycle.dispose();
      await hints.close();
      await queue.dispose();
    });

    await Future<void>.delayed(const Duration(milliseconds: 20));
    final initialSyncs = syncs;
    queue.emit([
      _command(
        availableAt: DateTime.now().toUtc().add(
          const Duration(milliseconds: 500),
        ),
      ),
    ]);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(syncs, initialSyncs);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(syncs, greaterThan(initialSyncs));
  });

  test('sync failure schedules retry', () async {
    final queue = _FakeOutboxService();
    var syncs = 0;
    final lifecycle = _lifecycle(
      queue: queue,
      syncNow: () async {
        syncs += 1;
        if (syncs == 1) {
          throw StateError('temporary sync failure');
        }
      },
    )..start();
    addTearDown(() async {
      lifecycle.dispose();
      await queue.dispose();
    });

    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(syncs, greaterThanOrEqualTo(2));
  });

  test('queue updates and hints cannot bypass a failed sync retry delay', () {
    fakeAsync((clock) {
      final queue = _FakeOutboxService();
      final hints = StreamController<AccountSyncHint>();
      var syncs = 0;
      final lifecycle = AccountSyncLifecycle(
        syncNow: () async {
          syncs += 1;
          // Marking an attempt writes the outbox while its request is in flight.
          queue.emit(syncs == 1 ? [_command().copyWith(attempts: syncs)] : []);
          await Future<void>.delayed(const Duration(seconds: 2));
          if (syncs == 1) throw StateError('invalid habit payload');
          return <String>{'task'};
        },
        deviceId: () async => 'device-1',
        syncHints: () => hints.stream,
        syncQueueRepository: queue,
        pollInterval: const Duration(seconds: 5),
        queueDebounce: const Duration(milliseconds: 10),
        retryDelays: const [Duration(seconds: 30)],
      )..start();
      try {
        clock.elapse(const Duration(seconds: 2));
        queue.emit([_command().copyWith(attempts: 1)]);
        hints.add(
          AccountSyncHint(
            appId: AccountAppId.pomodoist,
            deviceId: 'other-device',
            sentAt: DateTime.now().toUtc(),
          ),
        );
        clock.elapse(const Duration(seconds: 26));
        expect(syncs, 1);
        clock.elapse(const Duration(seconds: 5));
        expect(syncs, greaterThanOrEqualTo(2));
      } finally {
        lifecycle.dispose();
        unawaited(hints.close());
        unawaited(queue.dispose());
        clock.flushMicrotasks();
      }
    });
  });

  test('hint stream error resubscribes and future hints still sync', () async {
    final queue = _FakeOutboxService();
    final hintStreams = <StreamController<AccountSyncHint>>[];
    var syncs = 0;
    final lifecycle = _lifecycle(
      queue: queue,
      syncNow: () async => syncs += 1,
      syncHints: () {
        final controller = StreamController<AccountSyncHint>();
        hintStreams.add(controller);
        return controller.stream;
      },
    )..start();
    addTearDown(() async {
      lifecycle.dispose();
      for (final controller in hintStreams) {
        await controller.close();
      }
      await queue.dispose();
    });

    await Future<void>.delayed(const Duration(milliseconds: 20));
    final beforeReconnect = syncs;
    hintStreams.first.addError(StateError('realtime dropped'));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(syncs, greaterThan(beforeReconnect));
    final beforeHint = syncs;

    expect(hintStreams.length, greaterThanOrEqualTo(2));
    hintStreams.last.add(
      AccountSyncHint(
        appId: AccountAppId.pomodoist,
        deviceId: 'other-device',
        sentAt: DateTime.now().toUtc(),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(syncs, greaterThan(beforeHint));
  });

  test('successful sync forwards received entity types', () async {
    final queue = _FakeOutboxService();
    Set<String>? received;
    final lifecycle = _lifecycle(
      queue: queue,
      syncNow: () async {},
      entityTypes: const {'task'},
      onSynced: (types) async => received = types,
    )..start();
    addTearDown(() async {
      lifecycle.dispose();
      await queue.dispose();
    });

    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(received, {'task'});
  });
}

AccountSyncLifecycle _lifecycle({
  required _FakeOutboxService queue,
  required Future<void> Function() syncNow,
  Stream<AccountSyncHint> Function()? syncHints,
  Set<String> entityTypes = const {},
  Future<void> Function(Set<String>)? onSynced,
}) {
  return AccountSyncLifecycle(
    syncNow: () async {
      await syncNow();
      return entityTypes;
    },
    deviceId: () async => 'device-1',
    syncHints: syncHints ?? () => const Stream<AccountSyncHint>.empty(),
    syncQueueRepository: queue,
    onSynced: onSynced,
    pollInterval: const Duration(hours: 1),
    queueDebounce: const Duration(milliseconds: 10),
    hintResubscribeDelay: const Duration(milliseconds: 10),
    retryDelays: const [Duration(milliseconds: 10)],
  );
}

SyncCommandRow _command({DateTime? availableAt}) {
  final now = DateTime.now().toUtc();
  return SyncCommandRow(
    baseRevision: 0,
    id: 'id',
    uuid: 'uuid',
    type: 'task.complete',
    clientId: 'task-1',
    payloadJson: '{}',
    status: 'pending',
    attempts: 0,
    createdAt: now,
    updatedAt: now,
    availableAt: availableAt,
  );
}

class _FakeOutboxService implements OutboxService {
  final _controller = StreamController<List<SyncCommandRow>>.broadcast();

  @override
  Future<void> enqueue({
    required String type,
    required Map<String, Object?> payload,
    String? clientId,
    DateTime? availableAt,
  }) async {}

  @override
  Future<void> enqueueBatch(
    List<SyncQueueCommand> commands, {
    DateTime? occurredAt,
  }) async {}

  @override
  Stream<List<SyncCommandRow>> watchPending() => _controller.stream;

  void emit(List<SyncCommandRow> commands) => _controller.add(commands);

  Future<void> dispose() => _controller.close();
}
