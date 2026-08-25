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
import '../features/planning/data/task_decomposer.dart';
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
    final controller = VoiceRecognitionController();
    ref.onDispose(controller.dispose);
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
      final storeTransactions = await billingStore.pomodoistTransactionJws();
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
      return ref.read(billingControllerProvider).hasLocalStoreKitEntitlement;
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
      await ref.read(googleCalendarSyncControllerProvider).syncNow();
    },
  )..start();
  ref.onDispose(lifecycle.dispose);
  return lifecycle;
});

final accountSyncStartupProvider = FutureProvider<void>((ref) async {
  final engine = ref.watch(accountSyncEngineProvider);
  if (engine == null) {
    return;
  }
  await engine.prepareLocalAccountData();
});
