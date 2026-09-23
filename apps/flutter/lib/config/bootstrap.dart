import 'package:app_account/app_account.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:multiview_desktop/multiview_desktop.dart';

import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/app_environment.dart';
import 'package:pomodoist/config/app_language.dart';
import 'package:pomodoist/config/collaboration_dependencies.dart';
import 'package:pomodoist/ui/core/localization/app_locale.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/widgets/pomodoist_app.dart';
import 'package:pomodoist/ui/quick_add/widgets/global_quick_add_window.dart';
import 'package:pomodoist/config/auth/native_account_startup.dart';
import 'package:pomodoist/data/services/platform/native_link_coordinator.dart';
import 'package:pomodoist/config/runtime_public_config.dart';
import 'package:pomodoist/config/runtime_public_config_loader.dart';
import 'package:pomodoist/config/runtime_public_config_loader_core.dart';
import 'package:pomodoist/config/sentry_observability.dart';
import 'package:pomodoist/data/services/platform/web_bootstrap_loader.dart';
import 'package:pomodoist/domain/use_cases/account/pomodoist_retention.dart';
import 'package:pomodoist/config/billing_dependencies.dart';
import 'package:pomodoist/data/repositories/billing/billing_repository.dart';
import 'package:pomodoist/data/services/billing/account_billing_service.dart';
import 'package:pomodoist/domain/models/app_flavor.dart';
import 'package:pomodoist/domain/models/billing/billing_models.dart';
import 'package:pomodoist/ui/settings/widgets/pomodoist_account_actions.dart';

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

/// Publishes the flavor this process runs as.
///
/// Off the web the entry point decides: each `main_*.dart` names exactly one
/// [AppEnvironment] and [validateEnvironment] has already refused a build whose
/// compile-time flavor disagrees with it.
///
/// On the web every environment is served by the same `lib/main.dart`, so the
/// entry point always declares production and the deployed `config.js` is
/// authoritative instead. The loader has already read that configuration and
/// published the same flavor; deriving it here again keeps bootstrap the single
/// place that guarantees the value is set before any layer is constructed.
void publishAppFlavor({
  required AppEnvironment appEnvironment,
  required RuntimePublicConfig config,
  bool isWeb = kIsWeb,
}) {
  setAppFlavor(
    isWeb
        ? appFlavorForRuntimeEnvironment(config.environment)
        : appEnvironment.flavor,
  );
}

Future<void> _startPomodoist(
  AppEnvironment appEnvironment,
  RuntimePublicConfig runtimeConfig,
) async {
  validateEnvironment(appEnvironment: appEnvironment, config: runtimeConfig);
  // Publish the flavor before anything else is constructed so every layer
  // built below reads the same identity.
  publishAppFlavor(appEnvironment: appEnvironment, config: runtimeConfig);
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
    projectCollaborationOverride,
    ..._billingEntitlementOverrides(runtimeConfig: runtimeConfig),
    ..._billingPurchaseOverrides(),
  ];
}

List<Override> _billingEntitlementOverrides({
  required RuntimePublicConfig runtimeConfig,
}) {
  return [
    billingActiveAccountEntitlementProvider.overrideWith((ref) {
      final entitlement = activePomodoistPaidEntitlement(
        ref.watch(accountOverviewProvider).value,
      );
      return entitlement == null
          ? null
          : BillingEntitlement(
              appId: entitlement.appId,
              entitlementId: entitlement.entitlementId,
              status: entitlement.status,
              purchaseType: entitlement.purchaseType,
              source: entitlement.source,
              productId: entitlement.productId,
              store: entitlement.store,
              validUntil: entitlement.validUntil,
              renewsAt: entitlement.renewsAt,
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
  return _accountBillingService(ref)?.linkPurchases;
}

BillingOfferRequest? _offerRequest(Ref ref) {
  return _accountBillingService(ref)?.requestOffer;
}

BillingStripeGateway? _stripeGateway(Ref ref) {
  final service = _accountBillingService(ref);
  if (service == null) return null;
  return BillingStripeGateway(
    loadCatalog: service.loadStripeCatalog,
    createCheckout: service.createStripeCheckout,
    openCheckout: service.openCheckout,
  );
}

AccountBillingService? _accountBillingService(Ref ref) {
  final account = ref.watch(accountClientProvider);
  if (account == null || !_accountSignedIn(ref)) return null;
  return AccountBillingService(
    stripeTestOffers: appFlavor == AppFlavor.development,
    account: account,
    locale: () =>
        resolveAppLocale(ref.read(appLanguageProvider)).toLanguageTag(),
    onLinked: () {
      if (ref.mounted) ref.invalidate(accountOverviewProvider);
    },
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
              canSignIn: account != null && account.currentUserId == null,
              redirectTo: pomodoistLoginRedirect,
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
