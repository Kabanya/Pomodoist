import 'dart:async';

import 'package:app_account/app_account.dart';
import 'package:app_voice/app_voice.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/sync/account_sync_engine.dart';
import '../core/sync/account_sync_lifecycle.dart';
import '../core/sync/device_identity.dart';
import '../features/billing/billing.dart';
import '../features/focus/presentation/focus_view_mode.dart';
import '../features/integrations/google_calendar/data/google_calendar_sync_controller.dart';
import '../features/integrations/google_calendar/data/google_calendar_sync_lifecycle.dart';
import '../features/planning/data/task_decomposer.dart';
import '../features/voice/data/pomodoist_voice_controller.dart';
import '../features/voice/data/voice_transcription_mode.dart';
import 'native_captcha_startup.dart';
import 'native_link_coordinator.dart';
import 'providers.dart';
import 'runtime_public_config.dart';

const _pomodoistNativeLoginRedirect = 'pomodoist://login-callback';

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
  validateNativeCaptchaBuild(config);
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
      return GoogleCalendarSyncController(
        invoke: (body) {
          final account = ref.read(accountClientProvider);
          if (account?.currentUserId == null) {
            throw const GoogleCalendarServerException(
              'Sign in to connect Google Calendar.',
            );
          }
          return account!.invokeFunction(
            'pomodoist-google-calendar',
            body: body,
          );
        },
      );
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

final voiceRecognitionControllerProvider = Provider<VoiceRecognitionController>(
  (ref) {
    // Keep a live account reference without rebuilding an active recording on
    // bootstrap/token changes. Disposal must not access an already-disposed Ref.
    var account = ref.read(accountClientProvider);
    var disposed = false;
    ref.listen<AccountClient?>(accountClientProvider, (_, next) {
      account = next;
    });
    final controller = createPomodoistVoiceController(
      mode: effectiveVoiceTranscriptionMode(
        isWeb: kIsWeb,
        platform: defaultTargetPlatform,
        preferred: ref.read(voiceTranscriptionModeProvider),
        signedIn: account?.currentUserId != null,
      ),
      ownerId: () => account?.currentUserId,
      invoke: (body) async {
        final current = account;
        if (disposed || current == null || current.currentUserId == null) {
          throw const VoiceRecognitionException(
            'speech_unavailable',
            'Sign in to use voice transcription.',
          );
        }
        final response = await current.invokeFunction(
          'pomodoist-transcribe',
          body: body,
        );
        return response.data;
      },
    );
    ref.onDispose(() {
      disposed = true;
      controller.dispose();
    });
    return controller;
  },
);

final taskDecomposerProvider = Provider<TaskDecomposer>((ref) {
  final account = ref.watch(accountClientProvider);
  final billingStore = ref.watch(billingStoreProvider);
  return SupabaseTaskDecomposer(
    transport: (body) async {
      if (account == null) {
        throw const TaskDecompositionException(
          'Voice analysis is unavailable.',
        );
      }
      // The server accepts account authorization or verified StoreKit proofs.
      final storeTransactions = account.currentUserId != null
          ? const <String>[]
          : await billingStore.pomodoistTransactionJws();
      final response = await account.invokeFunction(
        'pomodoist-watch',
        body: {
          ...body,
          'storeTransactions': storeTransactions,
          if (pomodoistLocalStoreKit) 'localStoreKit': true,
        },
      );
      return response.data;
    },
  );
});

final pomodoistDeviceIdProvider = FutureProvider<String>((ref) {
  return pomodoistDeviceId(ref.watch(appDatabaseProvider));
});

final accountOverviewProvider = FutureProvider<AccountOverview?>((ref) async {
  final account = ref.watch(accountClientProvider);
  final authState = ref.watch(accountAuthStateProvider).value;
  final signedIn = authState?.signedIn ?? (account?.currentUserId != null);
  if (account == null || !signedIn) {
    return null;
  }
  final timeout = ref.watch(accountRequestTimeoutProvider);
  unawaited(
    (() async {
      try {
        await account
            .registerInstall(
              appId: AccountAppId.pomodoist,
              deviceId: await ref.read(pomodoistDeviceIdProvider.future),
              platform: 'flutter',
            )
            .timeout(timeout);
      } on Object {
        // Install registration is advisory and must never block the profile.
      }
    })(),
  );
  return account.getOverview().timeout(timeout);
}, retry: (_, _) => null);

final _connectedAgentsOwnerProvider = Provider<(AccountClient?, String?)>((
  ref,
) {
  final account = ref.watch(accountClientProvider);
  final auth = ref.watch(accountAuthStateProvider).value;
  if (account == null ||
      !ref.watch(accountConfiguredProvider) ||
      auth?.signedIn == false) {
    return (null, null);
  }
  return (account, account.currentUserId);
});

final connectedAgentsProvider =
    NotifierProvider<
      ConnectedAgentsController,
      AsyncValue<List<AccountOAuthGrant>>
    >(ConnectedAgentsController.new);

class ConnectedAgentsController
    extends Notifier<AsyncValue<List<AccountOAuthGrant>>> {
  AccountClient? _account;
  String? _userId;
  List<AccountOAuthGrant>? _grants;
  Future<void>? _inFlight;
  var _generation = 0;
  var _loadGeneration = 0;

  // AsyncError retains the error; the last successful list stays visible too.
  List<AccountOAuthGrant>? get grants => _grants;

  @override
  AsyncValue<List<AccountOAuthGrant>> build() {
    // Keep session changes observable even while Settings has no listeners.
    final owner = ref.container.listen(
      _connectedAgentsOwnerProvider,
      (_, _) => ref.invalidateSelf(),
    );
    ref.onDispose(() {
      owner.close();
      _generation += 1;
      _grants = null;
      _inFlight = null;
    });
    final (account, userId) = owner.read();
    _account = account;
    _userId = userId;
    _grants = null;
    _inFlight = null;
    final generation = ++_generation;
    if (account == null || userId == null) return const AsyncData([]);
    unawaited(
      Future<void>.microtask(() {
        if (_isCurrent(account, userId, generation)) return refresh();
      }),
    );
    return const AsyncLoading();
  }

  bool _isCurrent(AccountClient account, String userId, int generation) =>
      ref.mounted &&
      generation == _generation &&
      identical(account, _account) &&
      userId == _userId &&
      userId == account.currentUserId &&
      ref.read(_connectedAgentsOwnerProvider) == (account, userId);

  Future<void> refresh() {
    final account = _account;
    final userId = _userId;
    final generation = _generation;
    if (account == null ||
        userId == null ||
        !_isCurrent(account, userId, generation)) {
      return Future.value();
    }
    if (_inFlight case final pending?) return pending;
    final loadGeneration = ++_loadGeneration;
    return _inFlight = _load(account, userId, generation, loadGeneration)
        .whenComplete(() {
          if (generation == _generation && loadGeneration == _loadGeneration) {
            _inFlight = null;
          }
        });
  }

  Future<void> _load(
    AccountClient account,
    String userId,
    int generation,
    int loadGeneration,
  ) async {
    try {
      final grants = await account.listOAuthGrants().timeout(
        ref.read(accountRequestTimeoutProvider),
      );
      if (!_isCurrent(account, userId, generation) ||
          loadGeneration != _loadGeneration) {
        return;
      }
      _grants = List.unmodifiable(grants);
      state = AsyncData(_grants!);
    } catch (error, stackTrace) {
      if (_isCurrent(account, userId, generation) &&
          loadGeneration == _loadGeneration) {
        state = AsyncError(error, stackTrace);
      }
    }
  }

  Future<void> revoke(String clientId) async {
    final account = _account;
    final userId = _userId;
    final generation = _generation;
    if (account == null ||
        userId == null ||
        !_isCurrent(account, userId, generation)) {
      return;
    }
    await account
        .revokeOAuthGrant(clientId)
        .timeout(ref.read(accountRequestTimeoutProvider));
    if (!_isCurrent(account, userId, generation)) return;
    // A list requested before revocation must not put the removed agent back.
    _loadGeneration += 1;
    _inFlight = null;
    _grants = List.unmodifiable([
      for (final grant in _grants ?? <AccountOAuthGrant>[])
        if (grant.clientId != clientId) grant,
    ]);
    state = AsyncData(_grants!);
    await refresh();
  }
}

final accountSyncEngineProvider = Provider<AccountSyncEngine?>((ref) {
  final account = ref.watch(accountClientProvider);
  final authState = ref.watch(accountAuthStateProvider).value;
  if (account == null ||
      !(authState?.signedIn ?? (account.currentUserId != null))) {
    return null;
  }
  return AccountSyncEngine(
    db: ref.watch(appDatabaseProvider),
    account: account,
    uuid: const Uuid(),
    kanbanTransitions: ref.watch(kanbanTransitionCoordinatorProvider),
    localPaidEntitlementLoader: () async {
      return ref.read(runtimePublicConfigProvider).selfHostedFeaturesUnlocked ||
          ref.read(billingControllerProvider).hasLocalStoreKitEntitlement;
    },
  );
});

final accountSyncLifecycleProvider = Provider<AccountSyncLifecycle?>((ref) {
  final account = ref.watch(accountClientProvider);
  final engine = ref.watch(accountSyncEngineProvider);
  if (account == null || engine == null) {
    return null;
  }
  final lifecycle = AccountSyncLifecycle(
    account: account,
    engine: engine,
    syncQueueRepository: ref.watch(syncQueueRepositoryProvider),
    onSynced: (entityTypes) async {
      if (!entityTypes.contains('task')) {
        return;
      }
      await ref.read(taskRepositoryProvider).materializeDueRecurringTasks();
    },
  )..start();
  ref.onDispose(lifecycle.dispose);
  return lifecycle;
});

final _focusPreferenceCleanupProvider = Provider<Future<void> Function()>((
  ref,
) {
  return () => clearFocusPreferences(ref);
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
  await AccountSyncEngine.prepareGuestLocalData(
    db: db,
    uuid: const Uuid(),
    shouldPrepare: () => !disposed && !signedInObserved,
    onReset: clearFocusPreferences,
  );
});
