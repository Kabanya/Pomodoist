import 'dart:async';
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
}
