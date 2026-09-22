import 'package:pomodoist/data/repositories/local/sync_ownership_coordinator.dart';
import 'package:pomodoist/data/services/local/account_history_policy_store.dart';
import 'package:pomodoist/data/repositories/planning/remote_task_decomposer.dart';
import 'package:pomodoist/data/repositories/planning/task_decomposition_repository.dart';
import 'package:pomodoist/data/repositories/account/account_session_repository.dart';
import 'package:pomodoist/data/repositories/account/sdk_account_session_repository.dart';
import 'package:pomodoist/data/repositories/sync/local_sync_repository.dart';
import 'package:pomodoist/data/repositories/sync/sync_repository.dart';
import 'package:pomodoist/data/services/collaboration/collaboration_api.dart';
import 'package:pomodoist/data/repositories/account/account_overview_repository.dart';
import 'package:pomodoist/domain/models/account/account_overview.dart';
import 'package:pomodoist/domain/models/account/account_session.dart';
import 'package:pomodoist/domain/use_cases/account/sync_account_use_case.dart';
import 'dart:async';

import 'package:app_account/app_account.dart' hide AccountSession;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:pomodoist/data/services/sync/account_sync_engine.dart';
import 'package:pomodoist/data/services/sync/account_sync_lifecycle.dart';
import 'package:pomodoist/data/services/local/device_identity.dart';
import 'package:pomodoist/config/billing_dependencies.dart';
import 'package:pomodoist/domain/models/billing/billing_models.dart';
import 'package:pomodoist/config/billing_store_dependencies.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/data/services/google_calendar/google_calendar_sync_controller.dart';
import 'package:pomodoist/data/services/google_calendar/google_calendar_account_transport.dart';
import 'package:pomodoist/data/services/google_calendar/google_calendar_sync_lifecycle.dart';
import 'package:pomodoist/data/services/planning/task_decomposer.dart';
import 'package:pomodoist/data/services/planning/account_task_decomposition_transport.dart';
import 'package:pomodoist/data/services/account/account_locale_service.dart';
import 'package:pomodoist/data/services/platform/native_captcha_startup.dart';
import 'package:pomodoist/data/services/platform/native_link_coordinator.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/runtime_public_config.dart';
import 'package:pomodoist/config/app_language.dart';
import 'package:pomodoist/domain/models/app_flavor.dart';
import 'package:pomodoist/ui/core/localization/app_locale.dart';

/// Native redirect Supabase sends the user back to after signing in.
///
/// Derived from the flavor so a link minted by one build can never be handled
/// by another installed side by side with it.
String get _pomodoistNativeLoginRedirect =>
    '${appFlavor.urlScheme}://login-callback';

String get pomodoistLoginRedirect =>
    pomodoistLoginRedirectFor(isWeb: kIsWeb, baseUri: Uri.base);

String pomodoistLoginRedirectFor({required bool isWeb, required Uri baseUri}) {
  return isWeb
      ? baseUri.resolve('/login-callback').toString()
      : _pomodoistNativeLoginRedirect;
}

Future<AccountClient?> initializePomodoistAccountIfConfigured(
  RuntimePublicConfig config,
) async {
  validateNativeCaptchaBuild(
    local: config.environment == RuntimeEnvironment.local,
    captchaEnabled: config.turnstileSiteKey.isNotEmpty,
  );
  return initializeAccountClientIfConfigured(
    supabaseUrl: config.supabaseUrl?.toString() ?? '',
    supabaseAnonKey: config.supabaseAnonKey,
  );
}

typedef AccountBootstrapInitializer = Future<AccountClient?> Function();

const accountBootstrapTimeout = Duration(seconds: 15);
const accountRequestTimeout = Duration(seconds: 15);

final accountBootstrapInitializerProvider =
    Provider<AccountBootstrapInitializer>((ref) {
      final config = ref.watch(runtimePublicConfigProvider);
      return () => initializePomodoistAccountIfConfigured(config);
    });

final accountBootstrapTimeoutProvider = Provider<Duration>(
  (ref) => accountBootstrapTimeout,
);

final accountRequestTimeoutProvider = Provider<Duration>(
  (ref) => accountRequestTimeout,
);

final _accountBootstrapAttemptProvider = Provider<_AccountBootstrapAttempt>((
  ref,
) {
  return _AccountBootstrapAttempt(
    ref.watch(accountBootstrapInitializerProvider),
  );
});

final accountBootstrapProvider =
    AsyncNotifierProvider<AccountBootstrapController, AccountClient?>(
      AccountBootstrapController.new,
    );

final accountClientProvider = Provider<AccountClient?>((ref) {
  return ref.watch(accountBootstrapProvider).value;
});

final googleCalendarSyncControllerProvider =
    Provider<GoogleCalendarSyncController>((ref) {
      final transport = GoogleCalendarAccountTransport(
        () => ref.read(accountClientProvider),
      );
      return GoogleCalendarSyncController(invoke: transport.call);
    });

final googleCalendarSyncLifecycleProvider =
    Provider<GoogleCalendarSyncLifecycle?>((ref) {
      if (ref.watch(accountAuthStateProvider).value?.signedIn != true) {
        return null;
      }
      final lifecycle = GoogleCalendarSyncLifecycle(
        connections: ref
            .watch(calendarIntegrationRepositoryProvider)
            .watchConnection(),
        syncController: ref.watch(googleCalendarSyncControllerProvider),
      )..start();
      ref.onDispose(lifecycle.dispose);
      return lifecycle;
    });

class AccountBootstrapController extends AsyncNotifier<AccountClient?> {
  var _generation = 0;

  @override
  Future<AccountClient?> build() => _load();

  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }

  Future<AccountClient?> _load() {
    final generation = ++_generation;
    final pending = ref.read(_accountBootstrapAttemptProvider).initialize();
    unawaited(
      pending.then((account) {
        if (ref.mounted && generation == _generation) {
          state = AsyncData(account);
        }
      }, onError: (Object _, StackTrace _) {}),
    );
    return pending.timeout(ref.read(accountBootstrapTimeoutProvider));
  }
}

class _AccountBootstrapAttempt {
  _AccountBootstrapAttempt(this._initializer);

  final AccountBootstrapInitializer _initializer;
  Future<AccountClient?>? _inFlight;

  Future<AccountClient?> initialize() {
    final existing = _inFlight;
    if (existing != null) {
      return existing;
    }
    final pending = Future<AccountClient?>.sync(_initializer);
    _inFlight = pending;
    pending.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {
        if (identical(_inFlight, pending)) {
          _inFlight = null;
        }
      },
    );
    return pending;
  }
}

final nativeLinkCoordinatorProvider = Provider<NativeLinkCoordinator?>((ref) {
  return null;
});

final accountConfiguredProvider = createAccountConfiguredProvider(
  accountClientProvider,
);

// Presentation preference only; failures must never block authentication.
final accountLocaleSyncProvider = Provider<void>((ref) {
  const service = AccountLocaleService();
  var disposed = false;
  var pending = Future<void>.value();
  ref.onDispose(() => disposed = true);
  void sync() {
    pending = pending
        .then((_) async {
          if (disposed ||
              ref.read(accountAuthStateProvider).value?.signedIn != true) {
            return;
          }
          final locale = resolveAppLocale(
            ref.read(appLanguageProvider),
          ).toLanguageTag();
          await service.sync(locale);
        })
        .catchError((Object _) {});
  }

  ref.listen(appLanguageProvider, (_, _) => sync());
  ref.listen(accountAuthStateProvider, (_, _) => sync(), fireImmediately: true);
});

final accountAuthStateProvider = StreamProvider<AccountAuthState>((ref) async* {
  final account = ref.watch(accountClientProvider);
  if (account == null) {
    yield const AccountAuthState(signedIn: false);
    return;
  }
  yield AccountAuthState(
    signedIn: account.currentUserId != null,
    session: account.currentSession,
  );
  yield* account.accountAuthStateChanges();
});

final accountSessionRepositoryProvider = Provider<AccountSessionRepository>((
  ref,
) {
  final repository = SdkAccountSessionRepository(
    currentUserId: () => ref.read(accountClientProvider)?.currentUserId,
    authChanges: () {
      final account = ref.read(accountClientProvider);
      return account == null
          ? const Stream<AccountAuthState>.empty()
          : account.accountAuthStateChanges();
    },
    overviewLoader: () async {
      final account = ref.read(accountClientProvider);
      if (account == null || account.currentUserId == null) {
        return null;
      }
      return ref
          .read(accountOverviewProvider.future)
          .timeout(ref.read(accountRequestTimeoutProvider));
    },
  );
  ref.listen(accountClientProvider, (previous, next) {
    if (!identical(previous, next)) repository.reconnect();
  });
  ref.listen(accountOverviewProvider, (_, next) {
    if (next.hasValue) unawaited(repository.refresh());
  });
  ref.onDispose(repository.dispose);
  return repository;
});

final accountSessionProvider = StreamProvider<AccountSession>((ref) {
  return ref.watch(accountSessionRepositoryProvider).watchSession();
});

final _accountProfileSnapshotProvider =
    StreamProvider<PomodoistAccountProfile?>((ref) {
      return ref.watch(accountSessionRepositoryProvider).watchProfile();
    });
final accountProfileProvider = Provider<PomodoistAccountProfile?>((ref) {
  ref.watch(accountSessionProvider);
  final profile = ref.watch(_accountProfileSnapshotProvider).value;
  final session = ref.watch(accountSessionRepositoryProvider).currentSession;
  return profile?.id == session.userId ? profile : null;
});

final accountSignedInProvider = Provider<bool>((ref) {
  final session = ref.watch(accountSessionProvider).value;
  if (session != null) {
    return session.userId != null;
  }
  final authState = ref.watch(accountAuthStateProvider).value;
  final account = ref.watch(accountClientProvider);
  return (authState?.signedIn ?? false) || account?.currentUserId != null;
});

typedef AccountAvailability = ({
  bool configured,
  bool available,
  bool loading,
  Object? error,
});

final accountAvailabilityProvider = Provider<AccountAvailability>((ref) {
  final bootstrap = ref.watch(accountBootstrapProvider);
  final account = ref.watch(accountClientProvider);
  return (
    configured: ref.watch(accountConfiguredProvider),
    available: account != null,
    loading: bootstrap.isLoading,
    error: bootstrap.error,
  );
});

final taskDecomposerProvider = Provider<TaskDecomposer>((ref) {
  final endpoint = taskDecompositionEndpoint();
  final transport = AccountTaskDecompositionTransport(
    account: ref.watch(accountClientProvider),
    billingStore: ref.watch(billingStoreProvider),
    localStoreKit: pomodoistUsesLocalStoreKit,
    endpoint: endpoint,
  );
  return SupabaseTaskDecomposer(transport: transport.call);
});

final pomodoistDeviceIdProvider = FutureProvider<String>((ref) {
  return pomodoistDeviceId(ref.watch(appDatabaseProvider));
});

final accountOverviewRepositoryProvider = Provider<AccountOverviewRepository?>((
  ref,
) {
  final account = ref.watch(accountClientProvider);
  final authState = ref.watch(accountAuthStateProvider).value;
  final signedIn =
      (authState?.signedIn ?? false) || account?.currentUserId != null;
  return account == null || !signedIn
      ? null
      : AccountOverviewRepository(account);
});

final accountOverviewProvider = FutureProvider<PomodoistAccountOverview?>((
  ref,
) async {
  final repository = ref.watch(accountOverviewRepositoryProvider);
  if (repository == null) return null;
  return repository.load(
    deviceId: () => ref.read(pomodoistDeviceIdProvider.future),
    timeout: ref.watch(accountRequestTimeoutProvider),
  );
}, retry: (_, _) => null);

final accountSyncEngineProvider = Provider<AccountSyncEngine?>((ref) {
  final account = ref.watch(accountClientProvider);
  final authState = ref.watch(accountAuthStateProvider).value;
  if (account == null ||
      !((authState?.signedIn ?? false) || account.currentUserId != null)) {
    return null;
  }
  return AccountSyncEngine(
    db: ref.watch(appDatabaseProvider),
    account: account,
    uuid: const Uuid(),
    collaboration: CollaborationApi.account(account),
    prepareAccount: SyncOwnershipCoordinator(
      ref.watch(appDatabaseProvider),
      const Uuid(),
      () => account.currentUserId,
    ).prepareAccount,
    repairKanban: ref
        .watch(kanbanTransitionCoordinatorProvider)
        .repairAfterRemotePullInTransaction,
  );
});

final localSyncRepositoryProvider = Provider<SyncRepository>((ref) {
  return LocalSyncRepository(
    engine: () {
      final engine = ref.read(accountSyncEngineProvider);
      if (engine == null) {
        throw StateError('Sync is unavailable while signed out');
      }
      return engine;
    },
    currentSession: () =>
        ref.read(accountSessionRepositoryProvider).currentSession,
  );
});

final syncAccountUseCaseProvider = Provider<SyncAccountUseCase>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SyncAccountUseCase(
    sessions: ref.watch(accountSessionRepositoryProvider),
    sync: ref.watch(localSyncRepositoryProvider),
    access: ref.watch(billingRepositoryProvider),
    loadOverview: () async {
      final overview = await ref
          .read(accountOverviewProvider.future)
          .timeout(ref.read(accountRequestTimeoutProvider));
      return overview;
    },
    selfHostedFeaturesUnlocked: () =>
        ref.read(runtimePublicConfigProvider).selfHostedFeaturesUnlocked,
    loadHistoryPolicy: AccountHistoryPolicyStore(db).load,
  );
});

final accountSyncLifecycleProvider = Provider<AccountSyncLifecycle?>((ref) {
  final account = ref.watch(accountClientProvider);
  final engine = ref.watch(accountSyncEngineProvider);
  final useCase = ref.watch(syncAccountUseCaseProvider);
  if (account == null || engine == null) {
    return null;
  }
  final lifecycle = AccountSyncLifecycle(
    syncNow: () async => (await useCase.call()).getOrThrow(),
    deviceId: engine.deviceId,
    syncHints: () => account.syncHints(appId: AccountAppId.pomodoist),
    syncQueueRepository: ref.watch(syncQueueRepositoryProvider),
    onSynced: (entityTypes) async {
      if (!entityTypes.contains('task')) {
        return;
      }
      await ref
          .read(taskRepositoryProvider)
          .materializeDueRecurringTasks()
          .then((result) => result.getOrThrow());
    },
  )..start();
  ref.onDispose(lifecycle.dispose);
  return lifecycle;
});

final _focusPreferenceCleanupProvider = Provider<Future<void> Function()>((
  ref,
) {
  return () => ref
      .read(focusPreferencesRepositoryProvider)
      .clear()
      .then((result) => result.getOrThrow());
});

final accountSyncStartupProvider = FutureProvider<void>((ref) async {
  final engine = ref.watch(accountSyncEngineProvider);
  if (engine == null) {
    return;
  }
  await engine.prepareLocalAccountData(
    onReset: ref.read(_focusPreferenceCleanupProvider),
  );
});

final guestDataStartupProvider = FutureProvider.autoDispose<void>((ref) async {
  final appStartup = ref.watch(appStartupProvider.future);
  final accountBootstrap = ref.watch(accountBootstrapProvider.future);
  final db = ref.watch(appDatabaseProvider);
  final clearFocusPreferences = ref.read(_focusPreferenceCleanupProvider);
  var disposed = false;
  var signedInObserved = false;
  ref.onDispose(() => disposed = true);
  ref.listen(accountAuthStateProvider, (_, next) {
    if (next.value?.signedIn == true) {
      signedInObserved = true;
    }
  }, fireImmediately: true);

  await appStartup;
  final account = await accountBootstrap;
  if (disposed) {
    return;
  }
  final authState = await ref.read(accountAuthStateProvider.future);
  signedInObserved =
      signedInObserved || authState.signedIn || account?.currentUserId != null;
  if (disposed || signedInObserved) {
    return;
  }
  await SyncOwnershipCoordinator.prepareGuestLocalData(
    db: db,
    uuid: const Uuid(),
    shouldPrepare: () => !disposed && !signedInObserved,
    onReset: clearFocusPreferences,
  );
});
