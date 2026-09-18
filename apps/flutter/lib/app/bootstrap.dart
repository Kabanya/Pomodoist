import 'package:app_account/app_account.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config/account_providers.dart';
import 'app_environment.dart';
import 'config/app_language.dart';
import 'config/app_l10n.dart';
import 'app.dart';
import 'platform/global_quick_add_window.dart';
import 'auth/native_account_startup.dart';
import 'platform/native_link_coordinator.dart';
import 'config/runtime_public_config.dart';
import 'config/runtime_public_config_loader.dart';
import 'config/sentry_observability.dart';
import 'platform/web_bootstrap_loader.dart';
import '../core/sync/pomodoist_retention.dart';
import '../features/billing/billing.dart';
import '../features/settings/presentation/pomodoist_account_actions.dart';

Future<void> bootstrapPomodoist(AppEnvironment appEnvironment) async {
  await runPomodoistStartup(
    loadMonitoringPolicy: loadSentryRuntimePolicy,
    loadRuntimeConfig: loadRuntimePublicConfig,
    monitor: const SentryStartupMonitor(),
    onStartupFailure: showWebBootstrapFailure,
    startApplication: (runtimeConfig) =>
        _startPomodoist(appEnvironment, runtimeConfig),
  );
}

Future<void> _startPomodoist(
  AppEnvironment appEnvironment,
  RuntimePublicConfig runtimeConfig,
) async {
  validateEnvironment(appEnvironment: appEnvironment, config: runtimeConfig);
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  final nativeLinkCoordinator = createNativeLinkCoordinator();
  try {
    updateWebBootstrapStage('session');
    final nativeAccountStartup = await prepareNativeAccountStartup(
      links: nativeLinkCoordinator,
      initializeAccount: () =>
          initializePomodoistAccountIfConfigured(runtimeConfig),
    );
    updateWebBootstrapStage('app');
    _runPomodoist(
      _pomodoistOverrides(
        runtimeConfig: runtimeConfig,
        nativeAccountStartup: nativeAccountStartup,
        nativeLinkCoordinator: nativeLinkCoordinator,
      ),
    );
  } on Object {
    await nativeLinkCoordinator.dispose();
    rethrow;
  }
}

void _runPomodoist(List<Override> overrides) {
  Widget scope(Widget child) =>
      ProviderScope(overrides: overrides, child: child);

  if (_supportsDesktopMultiView) {
    runMultiApp(
      home: (context, id) => const PomodoistApp(),
      globalScope: scope,
      config: MultiAppConfig(
        globalWindowOptions: const WindowOptions(
          titleBarStyle: TitleBarStyle.normal,
          windowButtonVisibility: true,
        ),
        macosParams: const MacosPlatformParams(
          closeAppAfterLastWindowClosed: false,
          saveLastWindowToReopen: true,
        ),
        observers: [globalQuickAddWindowManager],
      ),
    );
  } else {
    runApp(scope(const PomodoistApp()));
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    hideWebBootstrapLoader();
  });
}

List<Override> _pomodoistOverrides({
  required RuntimePublicConfig runtimeConfig,
  required NativeAccountStartup<AccountClient?> nativeAccountStartup,
  required NativeLinkCoordinator nativeLinkCoordinator,
}) {
  return [
    runtimePublicConfigProvider.overrideWithValue(runtimeConfig),
    accountBootstrapInitializerProvider.overrideWithValue(
      nativeAccountStartup.initializeAccount,
    ),
    nativeLinkCoordinatorProvider.overrideWithValue(nativeLinkCoordinator),
    ..._billingEntitlementOverrides(runtimeConfig: runtimeConfig),
    ..._billingPurchaseOverrides(),
  ];
}

List<Override> _billingEntitlementOverrides({
  required RuntimePublicConfig runtimeConfig,
}) {
  return [
    billingActiveAccountEntitlementProvider.overrideWith((ref) {
      return activePomodoistPaidEntitlement(
        ref.watch(accountOverviewProvider).value,
      );
    }),
    billingAccountEntitlementProvider.overrideWith((ref) {
      return hasActivePomodoistPaidEntitlement(
        ref.watch(accountOverviewProvider).value,
      );
    }),
    billingEnvironmentEntitlementProvider.overrideWithValue(
      runtimeConfig.selfHostedFeaturesUnlocked,
    ),
    billingSignedInProvider.overrideWith((ref) => _accountSignedIn(ref)),
    billingAccountRefreshTokenProvider.overrideWith((ref) {
      return ref.watch(accountOverviewProvider).value?.generatedAt;
    }),
    billingAccountIdentityProvider.overrideWith((ref) {
      final account = ref.watch(accountClientProvider);
      ref.watch(accountAuthStateProvider);
      return (account, account?.currentUserId);
    }),
    billingAppAccountTokenLoaderProvider.overrideWith((ref) {
      final account = ref.watch(accountClientProvider);
      return () async {
        if (account?.currentUserId == null) {
          return null;
        }
        return account!.getAppleAppAccountToken();
      };
    }),
    billingEntitlementRefresherProvider.overrideWith((ref) {
      return () async {
        ref.invalidate(accountOverviewProvider);
        final overview = await ref.read(accountOverviewProvider.future);
        return hasActivePomodoistPaidEntitlement(overview);
      };
    }),
  ];
}

List<Override> _billingPurchaseOverrides() {
  return [
    billingPurchaseLinkerProvider.overrideWith(_purchaseLinker),
    billingOfferRequestProvider.overrideWith(_offerRequest),
    billingStripeGatewayProvider.overrideWith(_stripeGateway),
    billingSignInPromptProvider.overrideWith(_signInPrompt),
  ];
}

bool _accountSignedIn(Ref ref) {
  final account = ref.watch(accountClientProvider);
  final authState = ref.watch(accountAuthStateProvider).value;
  return (authState?.signedIn ?? false) || account?.currentUserId != null;
}

BillingPurchaseLinker? _purchaseLinker(Ref ref) {
  final account = ref.watch(accountClientProvider);
  final signedIn = _accountSignedIn(ref);
  if (account == null || !signedIn) {
    return null;
  }
  final ownerId = account.currentUserId;
  return (transactions) async {
    final session = account.currentSession;
    if (!ref.mounted ||
        ownerId == null ||
        account.currentUserId != ownerId ||
        session == null ||
        session.userId != ownerId ||
        session.accessToken == null ||
        session.accessToken!.isEmpty) {
      throw StateError('The purchase account changed.');
    }
    final response = await account.invokeFunction(
      'pomodoist-purchase',
      headers: {'Authorization': 'Bearer ${session.accessToken}'},
      body: {'transactions': transactions},
    );
    final data = response.data;
    if (data is Map && data['code'] == 'purchase_already_linked') {
      throw Exception(
        'This App Store purchase is linked to another '
        'Pomodoist account.',
      );
    }
    if (response.status < 200 ||
        response.status >= 300 ||
        data is! Map ||
        data['ok'] != true) {
      throw Exception(
        'App Store Pro works on this device, but account '
        'linking failed.',
      );
    }
    if (ref.mounted && account.currentUserId == ownerId) {
      ref.invalidate(accountOverviewProvider);
    }
  };
}

BillingOfferRequest? _offerRequest(Ref ref) {
  final account = ref.watch(accountClientProvider);
  if (account == null) return null;
  return (body) async {
    final response = await account.invokeFunction(
      'pomodoist-subscription-offer',
      body: body,
    );
    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      throw BillingOfferException(
        data is Map && data['code'] is String
            ? data['code'] as String
            : 'verification_failed',
      );
    }
    return response.data;
  };
}

BillingStripeGateway? _stripeGateway(Ref ref) {
  final account = ref.watch(accountClientProvider);
  if (account == null) return null;
  return BillingStripeGateway(
    loadCatalog: () async {
      final response = await account.invokeFunction(
        'pomodoist-stripe-billing',
        body: {'action': 'catalog'},
      );
      if (response.status < 200 || response.status >= 300) {
        throw StripeBillingException(_stripeBillingError(response.data));
      }
      return StripeBillingCatalog.fromJson(response.data);
    },
    createCheckout: (productId, surface) async {
      final response = await account.invokeFunction(
        'pomodoist-stripe-billing',
        body: {
          'action': 'checkout',
          'productId': productId,
          'surface': surface.name,
          'locale': resolveAppLocale(
            ref.read(appLanguageProvider),
          ).toLanguageTag(),
        },
      );
      if (response.status < 200 || response.status >= 300) {
        throw StripeBillingException(_stripeBillingError(response.data));
      }
      return stripeCheckoutUrlFromJson(response.data);
    },
    openCheckout: (url) => launchUrl(url, mode: LaunchMode.externalApplication),
  );
}

BillingSignInPrompt? _signInPrompt(Ref ref) {
  final account = ref.watch(accountClientProvider);
  return (context) => showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.loginTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            ...pomodoistAccountSignInActions(
              context: sheetContext,
              account: account,
              redirectTo: pomodoistLoginRedirect,
              config: ref.read(runtimePublicConfigProvider),
              nativeCaptchaCallbacks: ref
                  .read(nativeLinkCoordinatorProvider)
                  ?.captchaCallbacks,
              onSignedIn: () {
                if (sheetContext.mounted) {
                  Navigator.of(sheetContext).pop();
                }
              },
              appleLabel: context.l10n.accountApple,
              googleLabel: context.l10n.accountGoogle,
              emailLabel: context.l10n.accountEmail,
            ),
          ],
        ),
      ),
    ),
  );
}

bool get _supportsDesktopMultiView =>
    !kIsWeb &&
    const {
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }.contains(defaultTargetPlatform);

String _stripeBillingError(Object? value) {
  if (value is Map && value['code'] is String) {
    return value['code'] as String;
  }
  return 'checkout_failed';
}
