import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app/account_providers.dart';
import 'app/app_l10n.dart';
import 'app/app.dart';
import 'app/native_account_startup.dart';
import 'app/native_link_coordinator.dart';
import 'app/runtime_public_config.dart';
import 'app/runtime_public_config_loader.dart';
import 'app/sentry_observability.dart';
import 'app/web_bootstrap_loader.dart';
import 'core/sync/pomodoist_retention.dart';
import 'features/billing/billing.dart';
import 'features/settings/presentation/pomodoist_account_actions.dart';

Future<void> main() async {
  await runPomodoistStartup(
    loadMonitoringPolicy: loadSentryRuntimePolicy,
    loadRuntimeConfig: loadRuntimePublicConfig,
    monitor: const SentryStartupMonitor(),
    onStartupFailure: showWebBootstrapFailure,
    startApplication: (runtimeConfig) async {
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
        runApp(
          ProviderScope(
            overrides: [
              runtimePublicConfigProvider.overrideWithValue(runtimeConfig),
              accountBootstrapInitializerProvider.overrideWithValue(
                nativeAccountStartup.initializeAccount,
              ),
              nativeLinkCoordinatorProvider.overrideWithValue(
                nativeLinkCoordinator,
              ),
              billingActiveAccountEntitlementProvider.overrideWith((ref) {
                return activePomodoistPaidEntitlement(
                  ref.watch(accountOverviewProvider).value,
                );
              }),
              billingSignedInProvider.overrideWith((ref) {
                final account = ref.watch(accountClientProvider);
                return ref.watch(accountAuthStateProvider).value?.signedIn ??
                    account?.currentUserId != null;
              }),
              billingAccountRefreshTokenProvider.overrideWith((ref) {
                return ref.watch(accountOverviewProvider).value?.generatedAt;
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
              billingPurchaseLinkerProvider.overrideWith((ref) {
                final account = ref.watch(accountClientProvider);
                final signedIn =
                    ref.watch(accountAuthStateProvider).value?.signedIn ??
                    account?.currentUserId != null;
                if (account == null || !signedIn) {
                  return null;
                }
                return (transactions) async {
                  final response = await account.invokeFunction(
                    'pomodoist-purchase',
                    body: {'transactions': transactions},
                  );
                  final data = response.data;
                  if (data is Map &&
                      data['code'] == 'purchase_already_linked') {
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
                  ref.invalidate(accountOverviewProvider);
                };
              }),
              billingStripeGatewayProvider.overrideWith((ref) {
                final account = ref.watch(accountClientProvider);
                if (account == null) return null;
                return BillingStripeGateway(
                  loadCatalog: () async {
                    final response = await account.invokeFunction(
                      'pomodoist-stripe-billing',
                      body: {'action': 'catalog'},
                    );
                    if (response.status < 200 || response.status >= 300) {
                      throw Exception(_stripeBillingError(response.data));
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
                      },
                    );
                    if (response.status < 200 || response.status >= 300) {
                      throw Exception(_stripeBillingError(response.data));
                    }
                    return stripeCheckoutUrlFromJson(response.data);
                  },
                  openCheckout: (url) =>
                      launchUrl(url, mode: LaunchMode.externalApplication),
                );
              }),
              billingSignInPromptProvider.overrideWith((ref) {
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
              }),
              billingEntitlementRefresherProvider.overrideWith((ref) {
                return () async {
                  ref.invalidate(accountOverviewProvider);
                  final overview = await ref.read(
                    accountOverviewProvider.future,
                  );
                  return activePomodoistPaidEntitlement(overview) != null;
                };
              }),
            ],
            child: const PomodoistApp(),
          ),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          hideWebBootstrapLoader();
        });
      } on Object {
        await nativeLinkCoordinator.dispose();
        rethrow;
      }
    },
  );
}

String _stripeBillingError(Object? value) {
  if (value is Map && value['code'] is String) {
    return value['code'] as String;
  }
  return 'checkout_failed';
}
