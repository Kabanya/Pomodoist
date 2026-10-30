import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:app_account/app_account.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/runtime_public_config.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/data/services/local/sync_owner_store.dart';
import 'package:pomodoist/data/services/notifications/notification_scheduler.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pomodoist/data/repositories/local/sync_ownership_coordinator.dart';

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
    'Cloud bootstrap keeps saved account data recoverable without its old session',
    () async {
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp(
        'backend-switch-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/saved.sqlite');
      final original = AppDatabase(NativeDatabase(file));
      await original.ensureSeedData();
      await _writeOwner(original, 'persisted-account');
      await DriftTaskRepository(
        original,
        DriftOutboxService(original),
      ).createTask(
        CreateTaskInput(content: 'Unsent before backend correction'),
      );
      final tasksBefore = await original.select(original.tasks).get();
      final commandsBefore = await original.select(original.syncCommands).get();
      expect(tasksBefore, isNotEmpty);
      expect(commandsBefore, isNotEmpty);
      await original.close();

      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      final config = RuntimePublicConfig.fromBuildTimeValues(
        environment: 'production',
        release: '0123456789abcdef0123456789abcdef01234567',
        webAppUrl: 'https://app.pomodoist.com',
        supabaseUrl: '',
        supabaseAnonKey: '',
        turnstileSiteKey: 'public-site-key',
        sentryDsn: '',
        nativeRelease: true,
      );
      late SupabaseClient client;
      final container = ProviderContainer(
        overrides: [
          runtimePublicConfigProvider.overrideWithValue(config),
          // Keep native plugins outside this account/SQLite lifecycle test.
          accountBootstrapInitializerProvider.overrideWith((ref) {
            final config = ref.watch(runtimePublicConfigProvider);
            client = SupabaseClient(
              config.supabaseUrl!.toString(),
              config.supabaseAnonKey,
              authOptions: const AuthClientOptions(
                autoRefreshToken: false,
                authFlowType: AuthFlowType.implicit,
              ),
            );
            addTearDown(client.dispose);
            return () async => AccountClient.fromSupabaseClient(client);
          }),
          appDatabaseProvider.overrideWithValue(db),
          focusAutoCompletionCoordinatorProvider.overrideWith((ref) {}),
          notificationSchedulerProvider.overrideWithValue(
            _NoopNotificationScheduler(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final account = await container.read(accountBootstrapProvider.future);
      expect(account, isNotNull);
      expect(account!.currentUserId, isNull);
      final oauth = await client.auth.getOAuthSignInUrl(
        provider: OAuthProvider.google,
      );
      expect(Uri.parse(oauth.url).host, 'pomodoist.supabase.co');
      final guestListener = container.listen(
        guestDataStartupProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(guestListener.close);
      await container.read(guestDataStartupProvider.future);
      expect(
        (await db.select(db.accountRecoverySnapshots).getSingle()).ownerId,
        'persisted-account',
      );

      String part(Object value) =>
          base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      final token =
          '${part({'alg': 'HS256'})}.${part({'sub': 'persisted-account', 'exp': 2100000000})}.signature';
      await client.auth.recoverSession(
        jsonEncode({
          'access_token': token,
          'refresh_token': 'test-refresh-token',
          'expires_in': 3600,
          'token_type': 'bearer',
          'user': {
            'id': 'persisted-account',
            'aud': 'authenticated',
            'app_metadata': {},
            'user_metadata': {},
            'created_at': '2026-10-30T00:00:00Z',
          },
        }),
      );
      await SyncOwnershipCoordinator(
        db,
        const Uuid(),
        () => account.currentUserId,
      ).prepareAccount();
      expect(await db.select(db.tasks).get(), tasksBefore);
      expect(await db.select(db.syncCommands).get(), commandsBefore);
      expect(
        (await SyncOwnerStore(db, const Uuid()).owner())?.cursor,
        'persisted-account',
      );
    },
  );

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
