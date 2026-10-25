import 'dart:async';
import 'package:pomodoist/domain/models/account/legacy_recovery_request.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/ui/settings/view_models/settings_view_model.dart';

void main() {
  test('restart reports pending repairs instead of false success', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();
    await DriftOutboxService(db).enqueue(
      type: 'task.update',
      clientId: 'task',
      payload: {'content': 'Preserved'},
    );
    final pending = Completer<void>();
    var calls = 0;
    final container = ProviderContainer(
      overrides: [
        legacyRecoveryRequestProvider.overrideWithValue(() async => null),
        appDatabaseProvider.overrideWithValue(db),
        localSyncOwnerProvider.overrideWith((ref) => Stream.value('owner')),
        accountSyncRestartProvider.overrideWithValue(() {
          calls++;
          return pending.future;
        }),
      ],
    );
    addTearDown(container.dispose);
    final listener = container.listen(syncRestartViewModelProvider, (_, _) {});
    addTearDown(listener.close);
    await container.pump();
    expect(container.read(localSyncOwnerProvider).value, 'owner');
    final action = container.read(syncRestartViewModelProvider.notifier);
    final first = action.restart();
    final second = action.restart();
    expect(
      container.read(syncRestartViewModelProvider),
      SyncRestartPhase.running,
    );
    pending.complete();
    await container.pump();
    await pumpEventQueue();
    await container.pump();
    await Future.wait([first, second]);
    expect(calls, 1);
    expect(
      container.read(syncRestartViewModelProvider),
      SyncRestartPhase.pending,
    );
    expect((await db.select(db.syncCommands).get()).length, 1);
  });
  for (final changeOwner in [true, false]) {
    test(
      changeOwner
          ? 'owner change discards late restart result'
          : 'disposed settings ignores late restart result',
      () async {
        var owner = 'A';
        final pending = Completer<void>();
        final container = ProviderContainer(
          overrides: [
            legacyRecoveryRequestProvider.overrideWithValue(() async => null),
            localSyncOwnerProvider.overrideWith((ref) => Stream.value(owner)),
            accountSyncRestartProvider.overrideWithValue(() => pending.future),
            syncQueueStatusProvider.overrideWith(
              (ref) => Stream.value((
                pending: 0,
                rejected: 0,
                repair: 0,
                recovering: false,
              )),
            ),
          ],
        );
        if (changeOwner) addTearDown(container.dispose);
        container.listen(syncRestartViewModelProvider, (_, _) {});
        await container.pump();
        final running = container
            .read(syncRestartViewModelProvider.notifier)
            .restart();
        if (changeOwner) {
          owner = 'B';
          container.invalidate(localSyncOwnerProvider);
          await container.pump();
        } else {
          container.dispose();
        }
        pending.complete();
        await running;
        if (changeOwner) {
          expect(
            container.read(syncRestartViewModelProvider),
            SyncRestartPhase.idle,
          );
        }
      },
    );
  }
  for (final confirmed in [true, false]) {
    test(
      'legacy ownership confirmation $confirmed controls enqueue and restart',
      () async {
        const request = LegacyRecoveryRequest(
          userId: 'A',
          fingerprint: 'archive',
          recordCount: 3,
        );
        final events = <String>[];
        final dialog = Completer<bool>();
        final container = ProviderContainer(
          overrides: [
            localSyncOwnerProvider.overrideWith((ref) => Stream.value('A')),
            legacyRecoveryRequestProvider.overrideWithValue(
              () async => request,
            ),
            legacyRecoveryConfirmProvider.overrideWithValue((value) async {
              expect(identical(value, request), isTrue);
              events.add('enqueue');
            }),
            accountSyncRestartProvider.overrideWithValue(() async {
              events.add('restart');
            }),
            syncQueueStatusProvider.overrideWith(
              (ref) => Stream.value((
                pending: 0,
                rejected: 0,
                repair: 0,
                recovering: false,
              )),
            ),
          ],
        );
        addTearDown(container.dispose);
        container.listen(syncRestartViewModelProvider, (_, _) {});
        await container.pump();
        final vm = container.read(syncRestartViewModelProvider.notifier);
        var confirmations = 0;
        final running = vm.restart(
          confirmRecovery: (value) {
            confirmations++;
            expect(value.recordCount, 3);
            return dialog.future;
          },
        );
        final duplicate = vm.restart(
          confirmRecovery: (_) async => throw StateError('duplicate dialog'),
        );
        await container.pump();
        expect(events, isEmpty);
        dialog.complete(confirmed);
        await Future.wait([running, duplicate]);
        expect(confirmations, 1);
        expect(events, confirmed ? ['enqueue', 'restart'] : isEmpty);
        expect(
          container.read(syncRestartViewModelProvider),
          confirmed ? SyncRestartPhase.complete : SyncRestartPhase.pending,
        );
      },
    );
  }
  test('account change while confirming prevents legacy enqueue', () async {
    var owner = 'A';
    final dialog = Completer<bool>();
    var enqueued = false;
    final container = ProviderContainer(
      overrides: [
        localSyncOwnerProvider.overrideWith((ref) => Stream.value(owner)),
        legacyRecoveryRequestProvider.overrideWithValue(
          () async => const LegacyRecoveryRequest(
            userId: 'A',
            fingerprint: 'archive',
            recordCount: 1,
          ),
        ),
        legacyRecoveryConfirmProvider.overrideWithValue((_) async {
          enqueued = true;
        }),
      ],
    );
    addTearDown(container.dispose);
    container.listen(syncRestartViewModelProvider, (_, _) {});
    await container.pump();
    final running = container
        .read(syncRestartViewModelProvider.notifier)
        .restart(confirmRecovery: (_) => dialog.future);
    await container.pump();
    owner = 'B';
    container.invalidate(localSyncOwnerProvider);
    await container.pump();
    dialog.complete(true);
    await running;
    expect(enqueued, isFalse);
    expect(container.read(syncRestartViewModelProvider), SyncRestartPhase.idle);
  });
  test(
    'unreadable archive reports preserved recovery failure without claiming sync complete',
    () async {
      var restarted = false;
      final container = ProviderContainer(
        overrides: [
          localSyncOwnerProvider.overrideWith((ref) => Stream.value('A')),
          legacyRecoveryRequestProvider.overrideWithValue(
            () async => throw const FormatException('Invalid archive'),
          ),
          accountSyncRestartProvider.overrideWithValue(() async {
            restarted = true;
          }),
        ],
      );
      addTearDown(container.dispose);
      container.listen(syncRestartViewModelProvider, (_, _) {});
      await container.pump();
      await container.read(syncRestartViewModelProvider.notifier).restart();
      expect(
        container.read(syncRestartViewModelProvider),
        SyncRestartPhase.recoveryFailed,
      );
      expect(restarted, isFalse);
    },
  );
}
