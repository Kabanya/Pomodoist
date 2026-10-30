import 'dart:async';

import 'package:app_account/app_account.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/startup_wiring.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/sync_owner_store.dart';
import 'package:pomodoist/ui/core/view_models/app_startup_view_model.dart';
import 'package:uuid/uuid.dart';

import '../testing/fakes/fake_task_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('retry does not restart an unfinished local startup', () async {
    final pending = Completer<void>();
    var attempts = 0;
    final container = ProviderContainer(
      overrides: [
        appStartupProvider.overrideWith((ref) {
          attempts++;
          return pending.future;
        }),
        accountSyncStartupProvider.overrideWith((ref) async {}),
        startupBackgroundWiringProvider.overrideWith((ref) {}),
      ],
    );
    addTearDown(container.dispose);
    container.listen(appStartupViewModelProvider, (_, _) {});
    await pumpEventQueue();
    for (var attempt = 0; attempt < 1000; attempt++) {
      container.read(appStartupViewModelProvider.notifier).retry();
    }
    await pumpEventQueue();
    pending.complete();
    await container.read(appStartupViewModelProvider.future);
    expect(attempts, 1);
  });

  test('local startup does not wait for recurring task generation', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        taskRepositoryProvider.overrideWithValue(
          _PendingRecurrenceRepository(),
        ),
        focusAutoCompletionCoordinatorProvider.overrideWith((ref) {}),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(appStartupProvider.future)
        .timeout(const Duration(seconds: 5));
  });

  test(
    'token refresh keeps local startup ready while sync is blocked',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();
      await SyncOwnerStore(db, const Uuid()).writeOwner('account-A');
      final account = _Account();
      addTearDown(account.events.close);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          accountClientProvider.overrideWithValue(account),
          appStartupProvider.overrideWith((ref) async {}),
          startupBackgroundWiringProvider.overrideWith((ref) {}),
        ],
      );
      addTearDown(container.dispose);
      container.listen(appStartupViewModelProvider, (_, _) {});
      await container.read(localSyncOwnerProvider.future);
      await container.read(accountAuthStateProvider.future);
      await pumpEventQueue();
      await container.read(appStartupViewModelProvider.future);
      final engine = container.read(accountSyncEngineProvider);
      final releaseSync = Completer<void>();
      final blockedSync = SyncOwnerStore.serialized(
        db,
        () => releaseSync.future,
      );
      try {
        for (var batch = 0; batch < 20; batch++) {
          for (var event = 0; event < 50; event++) {
            account.events.add(
              AccountAuthState(signedIn: true, session: account.currentSession),
            );
          }
          await pumpEventQueue();
          expect(container.read(accountSyncEngineProvider), same(engine));
          expect(
            container.read(appStartupViewModelProvider).isLoading,
            isFalse,
          );
          expect(container.read(appStartupViewModelProvider).hasError, isFalse);
        }
      } finally {
        releaseSync.complete();
        await blockedSync;
        await pumpEventQueue();
      }

      account.userId = 'account-B';
      account.events.add(
        AccountAuthState(signedIn: true, session: account.currentSession),
      );
      await pumpEventQueue();
      await container.read(appStartupViewModelProvider.future);
      expect(container.read(accountSyncEngineProvider), isNot(same(engine)));
      expect(
        (await SyncOwnerStore(db, const Uuid()).owner())?.cursor,
        'account-B',
      );
    },
  );
}

class _PendingRecurrenceRepository extends FakeTaskRepository {
  @override
  Future<Never> materializeDueRecurringTasks({DateTime? now}) =>
      Completer<Never>().future;
}

class _Account implements AccountClient {
  String? userId = 'account-A';
  final events = StreamController<AccountAuthState>.broadcast();
  @override
  String? get currentUserId => userId;
  @override
  AccountSession? get currentSession =>
      userId == null ? null : AccountSession(userId: userId!);
  @override
  Stream<AccountAuthState> accountAuthStateChanges() => events.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
