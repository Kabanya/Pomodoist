import 'dart:async';
import 'dart:io';

import 'package:app_account/app_account.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/startup_wiring.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/core/view_models/app_startup_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sdk;
import 'package:uuid/uuid.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final endpoint = Platform.environment['POMODOIST_AUTH_EXPIRY_TEST_URL'];
  test(
    'real expiry and revoked refresh preserve readiness, tasks and queued writes across restart',
    () async {
      final elapsed = Stopwatch()..start();
      void stage(String name) {
        // ignore: avoid_print
        print(
          'live-token stage=$name elapsedMs=${elapsed.elapsedMilliseconds}',
        );
      }

      SharedPreferences.setMockInitialValues(const {});
      final live = await _LiveSession.create(endpoint!);
      AppDatabase? db;
      ProviderContainer? container;
      Future<void> closeDatabase() async {
        container?.dispose();
        container = null;
        await db?.close();
        db = null;
      }

      Future<List<TaskItem>> waitForTasks(Set<String> ids) async {
        final ready = Completer<List<TaskItem>>();
        final subscription = container!.listen(
          tasksByQueryProvider(const TaskQuery.inbox()),
          (_, next) {
            final tasks = next.value;
            if (tasks != null &&
                tasks.map((task) => task.id).toSet().containsAll(ids) &&
                !ready.isCompleted) {
              ready.complete(tasks);
            }
          },
          fireImmediately: true,
        );
        try {
          return await ready.future.timeout(const Duration(seconds: 5));
        } finally {
          subscription.close();
        }
      }

      Future<void> openDatabase() async {
        db = AppDatabase(NativeDatabase(live.databaseFile));
        container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db!),
            accountClientProvider.overrideWithValue(live.account),
            accountBootstrapInitializerProvider.overrideWithValue(
              () async => live.account,
            ),
            focusAutoCompletionCoordinatorProvider.overrideWith((ref) {}),
            startupBackgroundWiringProvider.overrideWith((ref) {}),
          ],
        );
        final ownerReady = Completer<void>();
        container!.listen(localSyncOwnerProvider, (_, next) {
          if (next.value == live.userId && !ownerReady.isCompleted) {
            ownerReady.complete();
          }
        });
        container!.listen(appStartupViewModelProvider, (_, _) {});
        await container!
            .read(appStartupViewModelProvider.future)
            .timeout(const Duration(seconds: 5));
        await ownerReady.future.timeout(const Duration(seconds: 5));
        container!.listen(
          tasksByQueryProvider(const TaskQuery.inbox()),
          (_, _) {},
        );
      }

      try {
        await openDatabase();
        final repository = container!.read(taskRepositoryProvider);
        final first =
            (await repository
                    .createTask(
                      CreateTaskInput(content: 'Unsynced before token expiry'),
                    )
                    .timeout(const Duration(seconds: 5)))
                .getOrThrow();
        final query = tasksByQueryProvider(const TaskQuery.inbox());
        await waitForTasks({first});
        stage('local-tasks-ready');
        final engine = container!.read(accountSyncEngineProvider);
        await live.waitForActualExpiry();
        stage('expired-jwt-rejected');
        live.transport.holdRefresh = true;
        final refreshed = live.client.auth.onAuthStateChange.firstWhere(
          (event) => event.event == sdk.AuthChangeEvent.tokenRefreshed,
        );
        live.client.auth.startAutoRefresh();
        await live.transport.refreshStarted.future.timeout(
          const Duration(seconds: 5),
        );
        await Future<void>.delayed(const Duration(seconds: 2));
        expect(container!.read(appStartupViewModelProvider).isLoading, isFalse);
        expect(container!.read(accountSyncEngineProvider), same(engine));
        expect(
          container!.read(query).requireValue.any((task) => task.id == first),
          isTrue,
        );
        final second =
            (await repository
                    .createTask(
                      CreateTaskInput(content: 'Saved while refresh waits'),
                    )
                    .timeout(const Duration(seconds: 5)))
                .getOrThrow();
        expect((await db!.select(db!.tasks).get()).length, 2);
        await waitForTasks({first, second});
        stage('local-write-during-refresh');
        live.transport.releaseRefresh.complete();
        await refreshed.timeout(const Duration(seconds: 5));
        live.client.auth.stopAutoRefresh();
        await pumpEventQueue();
        expect(live.transport.refreshStatuses, [200]);
        expect(live.account.currentUserId, live.userId);
        expect(container!.read(accountSyncEngineProvider), same(engine));
        expect(container!.read(appStartupViewModelProvider).isLoading, isFalse);
        stage('refresh-succeeded');
        final savedTasks = await db!.select(db!.tasks).get();
        final pendingCommands = await db!.select(db!.syncCommands).get();
        expect(pendingCommands, isNotEmpty);

        await live.admin.auth.admin.signOut(
          live.client.auth.currentSession!.accessToken,
        );
        await live.waitForActualExpiry();
        stage('revoked-jwt-expired');
        final signedOut = live.client.auth.onAuthStateChange.firstWhere(
          (event) => event.event == sdk.AuthChangeEvent.signedOut,
        );
        live.client.auth.startAutoRefresh();
        await signedOut.timeout(const Duration(seconds: 5));
        live.client.auth.stopAutoRefresh();
        await pumpEventQueue();
        await container!
            .read(appStartupViewModelProvider.future)
            .timeout(const Duration(seconds: 5));
        expect(live.account.currentUserId, isNull);
        expect(live.transport.refreshStatuses, [200, 400]);
        expect(container!.read(appStartupViewModelProvider).isLoading, isFalse);
        expect((await db!.select(db!.tasks).get()).length, 2);
        stage('refresh-rejected-local-data-preserved');
        container!.listen(guestDataStartupProvider, (_, _) {});
        await container!
            .read(guestDataStartupProvider.future)
            .timeout(const Duration(seconds: 5));
        final snapshots = await db!.select(db!.accountRecoverySnapshots).get();
        expect(
          snapshots.any(
            (row) =>
                row.ownerId == live.userId &&
                row.payloadJson.contains(first) &&
                row.payloadJson.contains(second),
          ),
          isTrue,
        );
        expect(await db!.select(db!.tasks).get(), isEmpty);
        await expectLater(
          repository
              .createTask(CreateTaskInput(content: 'Stale account writer'))
              .then((result) => result.getOrThrow()),
          throwsStateError,
        );
        expect(await db!.select(db!.tasks).get(), isEmpty);
        stage('guest-owner-data-archived');
        await closeDatabase();
        await live.signIn();
        await openDatabase();
        final restored = await waitForTasks({first, second});
        expect(restored.map((task) => task.id).toSet(), {first, second});
        expect(
          await db!.select(db!.syncCommands).get(),
          unorderedEquals(pendingCommands),
        );
        expect(
          (await db!.select(db!.accountRecoverySnapshots).get()).any(
            (row) => row.ownerId == live.userId,
          ),
          isFalse,
        );
        expect(await db!.select(db!.tasks).get(), unorderedEquals(savedTasks));
        stage('restart-restored-tasks-and-pending-writes');
      } finally {
        live.transport.releaseIfHeld();
        await closeDatabase();
        await live.dispose();
      }
    },
    skip: endpoint == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

class _LiveSession {
  _LiveSession(
    this.client,
    this.admin,
    this.transport,
    this.directory,
    this.email,
    this.password,
    this.userId,
  ) : account = AccountClient.fromSupabaseClient(client);
  final sdk.SupabaseClient client;
  final sdk.SupabaseClient admin;
  final _RefreshTransport transport;
  final Directory directory;
  final String email;
  final String password;
  final String userId;
  final AccountClient account;
  File get databaseFile => File('${directory.path}/tasks.sqlite');

  static Future<_LiveSession> create(String endpoint) async {
    final uri = Uri.parse(endpoint);
    if (uri.scheme != 'http' ||
        uri.host != '127.0.0.1' ||
        uri.path.isNotEmpty && uri.path != '/') {
      throw StateError('Live auth tests require loopback HTTP');
    }
    // Widget tests normally block HTTP; only this transport uses a real client.
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    final transport = _RefreshTransport(IOClient(HttpClient()));
    HttpOverrides.global = overrides;
    const options = sdk.AuthClientOptions(autoRefreshToken: false);
    final client = sdk.SupabaseClient(
      endpoint,
      Platform.environment['POMODOIST_AUTH_EXPIRY_TEST_ANON_KEY']!,
      httpClient: transport,
      authOptions: options,
    );
    final admin = sdk.SupabaseClient(
      endpoint,
      Platform.environment['POMODOIST_AUTH_EXPIRY_TEST_SERVICE_KEY']!,
      httpClient: transport,
      authOptions: options,
    );
    final email = 'token-expiry-${const Uuid().v4()}@example.invalid';
    final password = '${const Uuid().v4()}${const Uuid().v4()}';
    final user = (await admin.auth.admin.createUser(
      sdk.AdminUserAttributes(
        email: email,
        password: password,
        emailConfirm: true,
      ),
    )).user!;
    final directory = await Directory.systemTemp.createTemp(
      'pomodoist-token-expiry-',
    );
    final live = _LiveSession(
      client,
      admin,
      transport,
      directory,
      email,
      password,
      user.id,
    );
    try {
      await live.signIn();
      return live;
    } catch (_) {
      await live.dispose();
      rethrow;
    }
  }

  Future<void> signIn() async {
    await client.auth.signInWithPassword(email: email, password: password);
    client.auth.stopAutoRefresh();
    final remaining =
        client.auth.currentSession!.expiresAt! -
        DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (remaining <= 30 || remaining > 60) {
      throw StateError(
        'The isolated server must issue JWTs lasting 31–60 seconds',
      );
    }
  }

  Future<void> waitForActualExpiry() async {
    final session = client.auth.currentSession!;
    final expiry = DateTime.fromMillisecondsSinceEpoch(
      session.expiresAt! * 1000,
    );
    await Future<void>.delayed(
      expiry.difference(DateTime.now()) + const Duration(seconds: 2),
    );
    expect(DateTime.now().isAfter(expiry), isTrue);
    var rejected = false;
    try {
      await client.auth.getUser(session.accessToken);
    } on sdk.AuthApiException catch (error) {
      rejected = error.statusCode == '403' || error.statusCode == '401';
    }
    expect(
      rejected,
      isTrue,
      reason: 'The real server must reject the expired JWT',
    );
  }

  Future<void> dispose() async {
    client.auth.stopAutoRefresh();
    await admin.auth.admin.deleteUser(userId);
    await client.dispose();
    await admin.dispose();
    transport.close();
    await directory.delete(recursive: true);
  }
}

class _RefreshTransport extends http.BaseClient {
  _RefreshTransport(this.inner);
  final http.Client inner;
  bool holdRefresh = false;
  final refreshStarted = Completer<void>();
  final releaseRefresh = Completer<void>();
  final refreshStatuses = <int>[];
  void releaseIfHeld() {
    if (!releaseRefresh.isCompleted) releaseRefresh.complete();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final refresh =
        request.url.queryParameters['grant_type'] == 'refresh_token';
    if (refresh && holdRefresh) {
      if (!refreshStarted.isCompleted) refreshStarted.complete();
      await releaseRefresh.future;
    }
    final response = await inner.send(request);
    if (refresh) refreshStatuses.add(response.statusCode);
    return response;
  }

  @override
  void close() => inner.close();
}
