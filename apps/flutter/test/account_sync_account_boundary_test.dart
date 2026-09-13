import 'dart:async';

import 'package:app_account/app_account.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/account_providers.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/core/sync/account_sync_engine.dart';
import 'package:pomodoist/features/focus/presentation/focus_view_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  test(
    'guest preparation preserves custom focus data for the same guest',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();
      await AccountSyncEngine.prepareGuestLocalData(db: db, uuid: const Uuid());
      await _insertFocusPreset(db, id: 'guest-custom-preset');

      final reset = await AccountSyncEngine.prepareGuestLocalData(
        db: db,
        uuid: const Uuid(),
      );

      expect(reset, isFalse);
      expect(await _focusPreset(db, 'guest-custom-preset'), isNotNull);
    },
  );

  test('guest preparation removes account focus data', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();
    await _engine(
      db,
      _RecordingAccountClient(userId: 'account-user-id', nextCursor: 0),
    ).prepareLocalAccountData();
    await _insertFocusPreset(db, id: 'account-custom-preset');

    final reset = await AccountSyncEngine.prepareGuestLocalData(
      db: db,
      uuid: const Uuid(),
    );

    expect(reset, isTrue);
    expect(await _focusPreset(db, 'account-custom-preset'), isNull);
  });

  test(
    'account preparation removes guest focus data before its first push',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();
      await AccountSyncEngine.prepareGuestLocalData(db: db, uuid: const Uuid());
      await _insertFocusPreset(db, id: 'guest-custom-preset');
      final account = _RecordingAccountClient(
        userId: 'account-user-id',
        nextCursor: 0,
      );
      final engine = _engine(db, account);

      expect(await engine.prepareLocalAccountData(), isTrue);
      expect(await _focusPreset(db, 'guest-custom-preset'), isNull);
      await engine.syncNow();

      expect(
        account.pushed.where(
          (operation) => operation.entityId == 'guest-custom-preset',
        ),
        isEmpty,
      );
    },
  );

  test(
    'guest startup waits for pending bootstrap that resolves signed in',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();
      await _engine(
        db,
        _RecordingAccountClient(userId: 'persisted-user-id', nextCursor: 0),
      ).prepareLocalAccountData();
      await _insertFocusPreset(db, id: 'unsynced-account-preset');
      final bootstrap = Completer<AccountClient?>();
      final account = _MutableAuthAccountClient(userId: 'persisted-user-id');
      addTearDown(account.close);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          appStartupProvider.overrideWith((ref) async {}),
          accountBootstrapInitializerProvider.overrideWithValue(
            () => bootstrap.future,
          ),
        ],
      );
      addTearDown(container.dispose);
      final listener = container.listen(
        guestDataStartupProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);

      final guest = container.read(guestDataStartupProvider.future);
      await pumpEventQueue();
      bootstrap.complete(account);
      await guest;

      expect((await _owner(db))?.cursor, 'persisted-user-id');
      expect(await _focusPreset(db, 'unsynced-account-preset'), isNotNull);
    },
  );

  test('account preparation wins when sign-in races a guest reset', () async {
    final db = _BlockingResetDatabase();
    addTearDown(db.close);
    await db.ensureSeedData();
    final account = _RecordingAccountClient(
      userId: 'account-user-id',
      nextCursor: 0,
    );
    await _engine(db, account).prepareLocalAccountData();

    final guest = AccountSyncEngine.prepareGuestLocalData(
      db: db,
      uuid: const Uuid(),
    );
    await db.resetStarted.future;
    final accountStartup = _engine(db, account).prepareLocalAccountData();

    db.releaseReset.complete();
    await Future.wait([guest, accountStartup]);

    expect((await _owner(db))?.cursor, 'account-user-id');
  });

  testWidgets(
    'blocked guest reset clears preferences after auth removes its listener',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        focusViewModePreferenceKey: 'full',
        focusTimerVisualStylePreferenceKey: 'bar',
        lastFocusPresetIdPreferenceKey: 'account-preset',
        focusCompletionCelebrationEnabledPreferenceKey: false,
      });
      final db = _BlockingResetDatabase();
      addTearDown(db.close);
      await db.ensureSeedData();
      await _engine(
        db,
        _RecordingAccountClient(userId: 'old-user-id', nextCursor: 0),
      ).prepareLocalAccountData();
      final account = _MutableAuthAccountClient();
      addTearDown(account.close);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          appStartupProvider.overrideWith((ref) async {}),
          accountBootstrapInitializerProvider.overrideWithValue(
            () async => null,
          ),
          accountClientProvider.overrideWithValue(account),
          accountAuthStateProvider.overrideWith((ref) async* {
            yield const AccountAuthState(signedIn: false);
            yield* account.accountAuthStateChanges();
          }),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, child) {
              ref.watch(guestDataStartupProvider);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final guest = container.read(guestDataStartupProvider.future);
      await db.resetStarted.future;

      account.signIn('new-user-id');
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      final accountStartup = _engine(
        db,
        _RecordingAccountClient(userId: 'new-user-id', nextCursor: 0),
      ).prepareLocalAccountData();
      db.releaseReset.complete();
      await Future.wait([guest, accountStartup]);

      expect((await _owner(db))?.cursor, 'new-user-id');
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.containsKey(focusViewModePreferenceKey), isFalse);
      expect(
        preferences.containsKey(focusTimerVisualStylePreferenceKey),
        isFalse,
      );
      expect(preferences.containsKey(lastFocusPresetIdPreferenceKey), isFalse);
      expect(
        preferences.containsKey(focusCompletionCelebrationEnabledPreferenceKey),
        isFalse,
      );
    },
  );

  test('queued guest preparation aborts after sign-in', () async {
    final db = _BlockingResetDatabase();
    addTearDown(db.close);
    await db.ensureSeedData();
    await AccountSyncEngine.prepareGuestLocalData(db: db, uuid: const Uuid());
    final account = _RecordingAccountClient(
      userId: 'account-user-id',
      nextCursor: 0,
    );
    final accountStartup = _engine(db, account).prepareLocalAccountData();
    await db.resetStarted.future;
    var signedIn = false;
    final guest = AccountSyncEngine.prepareGuestLocalData(
      db: db,
      uuid: const Uuid(),
      shouldPrepare: () => !signedIn,
    );

    signedIn = true;
    db.releaseReset.complete();
    expect(await guest, isFalse);
    await accountStartup;

    expect((await _owner(db))?.cursor, 'account-user-id');
  });

  test('guest transition waits for a blocked account pull', () async {
    final db = _BlockingResetDatabase();
    addTearDown(db.close);
    await db.ensureSeedData();
    final account = _RecordingAccountClient(
      userId: 'account-user-id',
      nextCursor: 0,
    );
    final pull = Completer<AccountSyncPullResult>();
    account.pendingPull = pull.future;
    final engine = _engine(db, account);
    await engine.prepareLocalAccountData();

    final sync = engine.syncNow();
    await account.pullStarted.future;
    final guest = AccountSyncEngine.prepareGuestLocalData(
      db: db,
      uuid: const Uuid(),
    );
    await pumpEventQueue(times: 50);
    final guestResetStartedBeforePull = db.resetStarted.isCompleted;
    final result = AccountSyncPullResult(
      nextCursor: 1,
      hasMore: false,
      changes: [_focusPresetEntity('remote-account-preset')],
    );

    if (guestResetStartedBeforePull) {
      db.releaseReset.complete();
      await guest;
      pull.complete(result);
    } else {
      pull.complete(result);
    }
    await sync;
    if (!db.releaseReset.isCompleted) {
      await db.resetStarted.future;
      db.releaseReset.complete();
    }
    await guest;

    expect(guestResetStartedBeforePull, isFalse);
    expect((await _owner(db))?.cursor, 'guest');
    expect(await _focusPreset(db, 'remote-account-preset'), isNull);
    expect(await _syncCursor(db), isNull);
  });

  test(
    'guest startup clears Focus preferences at an account boundary',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();
      await _engine(
        db,
        _RecordingAccountClient(userId: 'account-user-id', nextCursor: 0),
      ).prepareLocalAccountData();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          appStartupProvider.overrideWith((ref) async {}),
        ],
      );
      addTearDown(container.dispose);
      final listener = container.listen(
        guestDataStartupProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);
      await _loadFocusPreferences(container);

      await container.read(guestDataStartupProvider.future);

      await _expectClearedFocusPreferences(container);
    },
  );

  test(
    'account startup clears Focus preferences at a guest boundary',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();
      await AccountSyncEngine.prepareGuestLocalData(db: db, uuid: const Uuid());
      final container = ProviderContainer(
        overrides: [
          appStartupProvider.overrideWith((ref) async {}),
          accountSyncEngineProvider.overrideWithValue(
            _engine(
              db,
              _RecordingAccountClient(userId: 'account-user-id', nextCursor: 0),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await _loadFocusPreferences(container);

      await container.read(accountSyncStartupProvider.future);

      await _expectClearedFocusPreferences(container);
    },
  );

  test('guest startup waits for app startup and can be retried', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();
    final startup = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        appStartupProvider.overrideWith((ref) => startup.future),
      ],
    );
    addTearDown(container.dispose);
    final listener = container.listen(
      guestDataStartupProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);

    final firstStartup = container.read(guestDataStartupProvider.future);
    await Future<void>.delayed(Duration.zero);
    expect(await _owner(db), isNull);

    startup.complete();
    await firstStartup;
    expect((await _owner(db))?.cursor, 'guest');

    container.invalidate(guestDataStartupProvider);
    await container.read(guestDataStartupProvider.future);
    expect((await _owner(db))?.cursor, 'guest');
  });

  test(
    'switching accounts never imports the previous account snapshot',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();
      final now = DateTime.utc(2026, 7, 12, 12);
      await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              id: 'ethan-private-task',
              userId: localUserId,
              content: 'Ethan private task',
              projectId: inboxProjectId,
              orderKey: 'private',
              createdAt: now,
              updatedAt: now,
            ),
          );

      final ethan = _RecordingAccountClient(
        userId: 'ethan-user-id',
        nextCursor: 10,
      );
      await _engine(db, ethan).syncNow();
      expect(
        ethan.pushed.any(
          (operation) => operation.entityId == 'ethan-private-task',
        ),
        isTrue,
      );

      final other = _RecordingAccountClient(
        userId: 'other-user-id',
        nextCursor: 0,
      );
      await _engine(db, other).syncNow();

      expect(
        other.pushed.any(
          (operation) => operation.entityId == 'ethan-private-task',
        ),
        isFalse,
      );
      expect(
        await (db.select(
          db.tasks,
        )..where((row) => row.id.equals('ethan-private-task'))).get(),
        isEmpty,
      );
    },
  );

  test('the boundary upgrade clears previously synced unowned data', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();
    final now = DateTime.utc(2026, 7, 12, 12);
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: 'legacy-private-task',
            userId: localUserId,
            content: 'Legacy private task',
            projectId: inboxProjectId,
            orderKey: 'legacy-private',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.syncState)
        .insert(
          SyncStateCompanion.insert(
            id: 'pomodoist-import',
            deviceId: 'legacy-device',
            cursor: const Value('done-v3'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.syncState)
        .insert(
          SyncStateCompanion.insert(
            id: 'pomodoist',
            deviceId: 'legacy-device',
            cursor: const Value('10'),
            createdAt: now,
            updatedAt: now,
          ),
        );

    final account = _RecordingAccountClient(
      userId: 'first-user-after-upgrade',
      nextCursor: 0,
    );
    await _engine(db, account).syncNow();

    expect(
      account.pushed.any(
        (operation) => operation.entityId == 'legacy-private-task',
      ),
      isFalse,
    );
    expect(
      await (db.select(
        db.tasks,
      )..where((row) => row.id.equals('legacy-private-task'))).get(),
      isEmpty,
    );
  });

  test(
    'account startup prepares local data without requiring network',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();
      final account = _RecordingAccountClient(
        userId: 'offline-user-id',
        nextCursor: 0,
        throwOnPull: true,
      );
      final container = ProviderContainer(
        overrides: [
          accountSyncEngineProvider.overrideWithValue(_engine(db, account)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(accountSyncStartupProvider.future);

      expect(account.pullCalls, 0);
    },
  );
}

Future<void> _insertFocusPreset(AppDatabase db, {required String id}) {
  final now = DateTime.utc(2026, 9, 1, 12);
  return db
      .into(db.focusPresets)
      .insert(
        FocusPresetsCompanion.insert(
          id: id,
          userId: localUserId,
          name: 'Custom',
          workSeconds: 1200,
          shortBreakSeconds: 300,
          longBreakSeconds: 900,
          intervalsBeforeLongBreak: 4,
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<FocusPresetRow?> _focusPreset(AppDatabase db, String id) {
  return (db.select(
    db.focusPresets,
  )..where((row) => row.id.equals(id))).getSingleOrNull();
}

Future<SyncStateRow?> _owner(AppDatabase db) {
  return (db.select(db.syncState)
        ..where((row) => row.id.equals('pomodoist-account-owner-v1')))
      .getSingleOrNull();
}

Future<SyncStateRow?> _syncCursor(AppDatabase db) {
  return (db.select(
    db.syncState,
  )..where((row) => row.id.equals('pomodoist'))).getSingleOrNull();
}

AccountSyncEntity _focusPresetEntity(String id) {
  final now = DateTime.utc(2026, 9, 1, 12);
  return AccountSyncEntity(
    entityType: 'focus_preset',
    entityId: id,
    serverRevision: 1,
    data: {
      'id': id,
      'userId': localUserId,
      'name': 'Remote account preset',
      'workSeconds': 1200,
      'shortBreakSeconds': 300,
      'longBreakSeconds': 900,
      'intervalsBeforeLongBreak': 4,
      'autoStartBreaks': false,
      'autoStartWork': false,
      'allowPause': true,
      'strictMode': false,
      'isDefault': false,
      'isDeleted': false,
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    },
  );
}

Future<void> _loadFocusPreferences(ProviderContainer container) async {
  await container.read(sharedPreferencesProvider.future);
  await container
      .read(focusViewModeProvider.notifier)
      .setMode(FocusViewMode.full);
  await container
      .read(focusTimerVisualStyleProvider.notifier)
      .setStyle(FocusTimerVisualStyle.bar);
  await container
      .read(lastFocusPresetIdProvider.notifier)
      .setPresetId('custom-preset');
  await container
      .read(focusCompletionCelebrationEnabledProvider.notifier)
      .setEnabled(false);
  expect(container.read(focusViewModeProvider), FocusViewMode.full);
  expect(
    container.read(focusTimerVisualStyleProvider),
    FocusTimerVisualStyle.bar,
  );
  expect(container.read(lastFocusPresetIdProvider), 'custom-preset');
  expect(container.read(focusCompletionCelebrationEnabledProvider), isFalse);
}

Future<void> _expectClearedFocusPreferences(ProviderContainer container) async {
  final preferences = await container.read(sharedPreferencesProvider.future);
  expect(preferences?.containsKey(focusViewModePreferenceKey), isFalse);
  expect(preferences?.containsKey(focusTimerVisualStylePreferenceKey), isFalse);
  expect(preferences?.containsKey(lastFocusPresetIdPreferenceKey), isFalse);
  expect(
    preferences?.containsKey(focusCompletionCelebrationEnabledPreferenceKey),
    isFalse,
  );
  expect(container.read(focusViewModeProvider), FocusViewMode.minimal);
  expect(
    container.read(focusTimerVisualStyleProvider),
    FocusTimerVisualStyle.circle,
  );
  expect(container.read(lastFocusPresetIdProvider), isNull);
  expect(container.read(focusCompletionCelebrationEnabledProvider), isTrue);
}

AccountSyncEngine _engine(AppDatabase db, _RecordingAccountClient account) {
  return AccountSyncEngine(
    db: db,
    account: account,
    uuid: const Uuid(),
    localPaidEntitlementLoader: () async => true,
  );
}

class _RecordingAccountClient implements AccountClient {
  _RecordingAccountClient({
    required this.userId,
    required this.nextCursor,
    this.throwOnPull = false,
  });

  final String userId;
  final int nextCursor;
  final bool throwOnPull;
  final List<AccountSyncOperation> pushed = [];
  final pullStarted = Completer<void>();
  Future<AccountSyncPullResult>? pendingPull;
  var pullCalls = 0;

  @override
  String? get currentUserId => userId;

  @override
  Future<AccountSyncPushResult> pushChanges({
    required String appId,
    required String deviceId,
    required List<AccountSyncOperation> operations,
  }) async {
    pushed.addAll(operations);
    return AccountSyncPushResult(serverRevision: nextCursor, applied: const []);
  }

  @override
  Future<AccountSyncPullResult> pullChanges({
    required String appId,
    required String deviceId,
    required int sinceRevision,
    int limit = 500,
  }) async {
    pullCalls += 1;
    if (!pullStarted.isCompleted) {
      pullStarted.complete();
    }
    if (throwOnPull) {
      throw StateError('network unavailable');
    }
    final pending = pendingPull;
    if (pending != null) {
      return pending;
    }
    return AccountSyncPullResult(
      nextCursor: nextCursor,
      hasMore: false,
      changes: const [],
    );
  }

  @override
  Future<void> broadcastSyncHint({
    required String appId,
    required String deviceId,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MutableAuthAccountClient implements AccountClient {
  _MutableAuthAccountClient({this.userId});

  String? userId;
  final _authStates = StreamController<AccountAuthState>.broadcast();

  @override
  String? get currentUserId => userId;

  @override
  AccountSession? get currentSession => userId == null
      ? null
      : AccountSession(userId: userId!, accessToken: 'test-token');

  @override
  Stream<AccountAuthState> accountAuthStateChanges() => _authStates.stream;

  void signIn(String id) {
    userId = id;
    _authStates.add(AccountAuthState(signedIn: true, session: currentSession));
  }

  Future<void> close() => _authStates.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BlockingResetDatabase extends AppDatabase {
  _BlockingResetDatabase() : super(NativeDatabase.memory());

  final resetStarted = Completer<void>();
  final releaseReset = Completer<void>();
  var _blocksNextReset = true;

  @override
  Future<void> resetAccountData() async {
    if (_blocksNextReset) {
      _blocksNextReset = false;
      resetStarted.complete();
      await releaseReset.future;
    }
    await super.resetAccountData();
  }
}
